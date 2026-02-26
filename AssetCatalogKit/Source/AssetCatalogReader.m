//
//  AssetCatalogReader.m
//  AssetCatalogKit
//
//  Implementation for reading compiled Asset Catalog (.car) files
//

#import "AssetCatalogReader.h"
#import "CoreUI.h"

// Key constants
NSString *const kACKNameKey = @"name";
NSString *const kACKImageKey = @"image";
NSString *const kACKThumbnailKey = @"thumbnail";
NSString *const kACKFilenameKey = @"filename";
NSString *const kACKContentsDataKey = @"data";
NSString *const kACKImageRepKey = @"imagerep";
NSString *const kACKScaleKey = @"scale";
NSString *const kACKIsVectorKey = @"isVector";
NSString *const kACKAssetTypeKey = @"assetType";
NSString *const kACKWidthKey = @"width";
NSString *const kACKHeightKey = @"height";

static NSString *const kAssetCatalogReaderErrorDomain = @"com.assets.AssetCatalogReader";

@interface AssetCatalogReader ()

@property (nonatomic, copy) NSURL *fileURL;
@property (nonatomic, strong) CUICatalog *catalog;
@property (nonatomic, strong) NSMutableArray<NSDictionary<NSString *, id> *> *mutableAssets;
@property (assign) NSUInteger totalNumberOfAssets;
@property (nonatomic, assign, getter=isResourceConstrained) BOOL resourceConstrained;
@property (nonatomic, assign) int maxCount;

@end

@implementation AssetCatalogReader {
    BOOL _computedCatalogHasRetinaContent;
    BOOL _catalogHasRetinaContent;
}

#pragma mark - Initialization

- (instancetype)initWithFileURL:(NSURL *)URL {
    self = [super init];
    if (self) {
        _fileURL = [URL copy];
        _thumbnailSize = NSMakeSize(128, 128);
        _mutableAssets = [NSMutableArray new];
    }
    return self;
}

#pragma mark - Properties

- (NSArray<NSDictionary<NSString *, id> *> *)assets {
    return [self.mutableAssets copy];
}

#pragma mark - Public Methods

- (void)cancelReading {
    self.cancelled = YES;
}

- (void)resourceConstrainedReadWithMaxCount:(int)max completionHandler:(void (^)(void))callback {
    self.resourceConstrained = YES;
    self.maxCount = max;
    [self readWithCompletionHandler:callback progressHandler:nil];
}

- (void)readWithCompletionHandler:(void (^)(void))callback
                  progressHandler:(void (^)(double))progressCallback {
    NSString *catalogPath = [self resolveCatalogPath];

    if (!catalogPath) {
        dispatch_async(dispatch_get_main_queue(), ^{
            self.error = [NSError errorWithDomain:kAssetCatalogReaderErrorDomain
                                             code:1
                                         userInfo:@{NSLocalizedDescriptionKey: @"Unable to find asset catalog path"}];
            callback();
        });
        return;
    }

    __weak typeof(self) weakSelf = self;

    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        [weakSelf loadCatalogAtPath:catalogPath
                 completionHandler:callback
                   progressHandler:progressCallback];
    });
}

#pragma mark - Private Methods

- (NSString *)resolveCatalogPath {
    NSString *catalogPath = nil;

    // Check if it's a bundle
    NSBundle *bundle = [NSBundle bundleWithURL:self.fileURL];
    if (bundle) {
        catalogPath = [bundle pathForResource:@"Assets" ofType:@"car"];
        if (!catalogPath) {
            // Try looking in Resources
            NSString *resourcePath = [bundle.bundlePath stringByAppendingPathComponent:@"Contents/Resources/Assets.car"];
            if ([[NSFileManager defaultManager] fileExistsAtPath:resourcePath]) {
                catalogPath = resourcePath;
            }
        }
        self.catalogName = [NSString stringWithFormat:@"%@ | %@",
                           bundle.bundlePath.lastPathComponent,
                           catalogPath.lastPathComponent ?: @"Assets.car"];
    } else {
        // Direct .car file
        catalogPath = self.fileURL.path;
        self.catalogName = catalogPath.lastPathComponent;
    }

    return catalogPath;
}

- (void)loadCatalogAtPath:(NSString *)path
        completionHandler:(void (^)(void))callback
          progressHandler:(void (^)(double))progressCallback {
    NSError *catalogError = nil;
    self.catalog = [[CUICatalog alloc] initWithURL:[NSURL fileURLWithPath:path] error:&catalogError];

    if (catalogError || !self.catalog) {
        dispatch_async(dispatch_get_main_queue(), ^{
            self.error = catalogError ?: [NSError errorWithDomain:kAssetCatalogReaderErrorDomain
                                                             code:2
                                                         userInfo:@{NSLocalizedDescriptionKey: @"Failed to open asset catalog"}];
            callback();
        });
        return;
    }

    // Read via theme store for comprehensive asset access
    [self readThemeStoreWithCompletionHandler:callback progressHandler:progressCallback];
}

- (void)readThemeStoreWithCompletionHandler:(void (^)(void))callback
                            progressHandler:(void (^)(double))progressCallback {
    CUIStructuredThemeStore *themeStore = [self.catalog _themeStore];
    if (!themeStore) {
        dispatch_async(dispatch_get_main_queue(), ^{
            self.error = [NSError errorWithDomain:kAssetCatalogReaderErrorDomain
                                             code:3
                                         userInfo:@{NSLocalizedDescriptionKey: @"Unable to access theme store"}];
            callback();
        });
        return;
    }

    NSArray<CUIRenditionKey *> *allKeys = themeStore.themeStore.allAssetKeys;
    NSUInteger realTotalItemCount = allKeys.count;
    __block NSUInteger loadedItemCount = 0;
    NSUInteger totalItemCount = self.resourceConstrained ? MIN(_maxCount, realTotalItemCount) : realTotalItemCount;

    _totalNumberOfAssets = realTotalItemCount;

    __weak typeof(self) weakSelf = self;

    for (CUIRenditionKey *key in allKeys) {
        @autoreleasepool {
            if (weakSelf.resourceConstrained && loadedItemCount >= totalItemCount) {
                break;
            }

            if (self.cancelled) {
                break;
            }

            // Report progress
            if (progressCallback && loadedItemCount % 10 == 0) {
                double progress = (double)loadedItemCount / (double)totalItemCount;
                dispatch_async(dispatch_get_main_queue(), ^{
                    progressCallback(progress);
                });
            }

            @try {
                CUIThemeRendition *rendition = [themeStore renditionWithKey:key.keyList];
                if (!rendition) continue;

                // Skip non-retina in constrained mode if retina available
                if ([self catalogHasRetinaContent] && weakSelf.resourceConstrained && rendition.scale < 2) {
                    continue;
                }

                [self processRendition:rendition withKey:key];
                loadedItemCount++;

            } @catch (NSException *exception) {
                NSLog(@"Exception reading rendition: %@", exception);
            }
        }
    }

    dispatch_async(dispatch_get_main_queue(), ^{
        if (progressCallback) {
            progressCallback(1.0);
        }
        callback();
    });
}

- (void)processRendition:(CUIThemeRendition *)rendition withKey:(CUIRenditionKey *)key {
    // Check for SVG/Vector support
    const BOOL coreSVGPresent = CGSVGDocumentGetCanvasSize != NULL &&
                                CGContextDrawSVGDocument != NULL &&
                                CGSVGDocumentWriteToData != NULL;
    const BOOL isSVG = coreSVGPresent && rendition.isVectorBased && rendition.svgDocument;

    if (isSVG) {
        [self processSVGRendition:rendition withKey:key];
    } else if (rendition.unslicedImage) {
        [self processBitmapRendition:rendition withKey:key];
    }
}

- (void)processSVGRendition:(CUIThemeRendition *)rendition withKey:(CUIRenditionKey *)key {
    CGSize canvasSize = CGSVGDocumentGetCanvasSize(rendition.svgDocument);

    // Create image rep that draws SVG
    NSCustomImageRep *imageRep = [[NSCustomImageRep alloc] initWithSize:canvasSize
                                                                flipped:NO
                                                         drawingHandler:^BOOL(NSRect dstRect) {
        CGContextRef context = NSGraphicsContext.currentContext.CGContext;
        if (context && rendition.svgDocument) {
            CGContextDrawSVGDocument(context, rendition.svgDocument);
        }
        return YES;
    }];

    NSString *cleanName = [self cleanupRenditionName:rendition.name];
    NSString *filename = [NSString stringWithFormat:@"%@.svg", cleanName];

    // Export SVG data
    NSMutableData *svgData = [NSMutableData new];
    CGSVGDocumentWriteToData(rendition.svgDocument, (__bridge CFMutableDataRef)svgData, NULL);

    NSDictionary *desc = [self assetDescriptionWithName:rendition.name
                                               filename:filename
                                         representation:imageRep
                                           contentsData:svgData
                                                  scale:rendition.scale
                                                  width:canvasSize.width
                                                 height:canvasSize.height
                                               isVector:YES
                                              assetType:ACKAssetTypeVector];

    if (desc && !self.cancelled) {
        @synchronized (self.mutableAssets) {
            [self.mutableAssets addObject:desc];
        }
    }
}

- (void)processBitmapRendition:(CUIThemeRendition *)rendition withKey:(CUIRenditionKey *)key {
    CGImageRef cgImage = rendition.unslicedImage;
    if (!cgImage) return;

    NSBitmapImageRep *imageRep = [[NSBitmapImageRep alloc] initWithCGImage:cgImage];
    CGFloat width = CGImageGetWidth(cgImage);
    CGFloat height = CGImageGetHeight(cgImage);
    imageRep.size = NSMakeSize(width, height);

    NSString *cleanName = [self cleanupRenditionName:rendition.name];
    NSString *filename = [self filenameForAssetNamed:cleanName
                                               scale:rendition.scale
                                   presentationState:key.themeState];

    // Skip packed assets
    if ([filename containsString:@"ZZPackedAsset"] || [filename containsString:@"ZZZZPackedAsset"]) {
        return;
    }

    // Generate PNG data
    NSData *pngData = [imageRep representationUsingType:NSBitmapImageFileTypePNG
                                             properties:@{NSImageInterlaced: @(NO)}];

    NSDictionary *desc = [self assetDescriptionWithName:rendition.name
                                               filename:filename
                                         representation:imageRep
                                           contentsData:pngData
                                                  scale:rendition.scale
                                                  width:width
                                                 height:height
                                               isVector:NO
                                              assetType:ACKAssetTypeImage];

    if (desc && !self.cancelled) {
        @synchronized (self.mutableAssets) {
            [self.mutableAssets addObject:desc];
        }
    }
}

- (NSDictionary *)assetDescriptionWithName:(NSString *)name
                                  filename:(NSString *)filename
                            representation:(NSImageRep *)imageRep
                              contentsData:(NSData *)data
                                     scale:(CGFloat)scale
                                     width:(CGFloat)width
                                    height:(CGFloat)height
                                  isVector:(BOOL)isVector
                                 assetType:(ACKAssetType)assetType {

    if (_resourceConstrained) {
        // Lightweight version for QuickLook
        return @{
            kACKNameKey: name ?: @"Unknown",
            kACKFilenameKey: filename ?: @"unknown.png",
            kACKImageRepKey: imageRep,
            kACKScaleKey: @(scale),
            kACKWidthKey: @(width),
            kACKHeightKey: @(height),
            kACKIsVectorKey: @(isVector),
            kACKAssetTypeKey: @(assetType)
        };
    } else {
        // Full version with images and data
        if (!data.length) {
            NSLog(@"Unable to get data for rendition named %@", name);
            return nil;
        }

        NSImage *originalImage = [[NSImage alloc] initWithSize:NSMakeSize(width, height)];
        [originalImage addRepresentation:imageRep];

        NSImage *thumbnail = [self constrainImage:originalImage toSize:self.thumbnailSize];

        return @{
            kACKNameKey: name ?: @"Unknown",
            kACKImageKey: originalImage,
            kACKThumbnailKey: thumbnail,
            kACKFilenameKey: filename ?: @"unknown.png",
            kACKContentsDataKey: data,
            kACKScaleKey: @(scale),
            kACKWidthKey: @(width),
            kACKHeightKey: @(height),
            kACKIsVectorKey: @(isVector),
            kACKAssetTypeKey: @(assetType)
        };
    }
}

#pragma mark - Helpers

- (NSString *)cleanupRenditionName:(NSString *)name {
    if (!name) return @"Unknown";

    NSString *cleaned = name.stringByDeletingPathExtension;
    NSArray *components = [cleaned componentsSeparatedByString:@"@"];
    return components.firstObject ?: cleaned;
}

- (NSString *)filenameForAssetNamed:(NSString *)name
                              scale:(CGFloat)scale
                  presentationState:(NSInteger)state {
    NSString *stateSuffix = @"";
    if (state != kCoreThemeStateNone && state > 0) {
        NSString *stateName = themeStateNameForThemeState(state);
        if (stateName) {
            stateSuffix = [NSString stringWithFormat:@"_%@", stateName];
        }
    }

    NSString *scaleSuffix = @"";
    if (scale > 1.0) {
        scaleSuffix = [NSString stringWithFormat:@"@%.0fx", scale];
    }

    return [NSString stringWithFormat:@"%@%@%@.png", name, stateSuffix, scaleSuffix];
}

- (NSImage *)constrainImage:(NSImage *)image toSize:(NSSize)size {
    if (image.size.width <= size.width && image.size.height <= size.height) {
        return [image copy];
    }

    CGFloat newWidth, newHeight;
    double rw = image.size.width / size.width;
    double rh = image.size.height / size.height;

    if (rw > rh) {
        newHeight = MAX(roundl(image.size.height / rw), 1);
        newWidth = size.width;
    } else {
        newWidth = MAX(roundl(image.size.width / rh), 1);
        newHeight = size.height;
    }

    NSImage *thumbnail = [[NSImage alloc] initWithSize:NSMakeSize(newWidth, newHeight)];
    [thumbnail lockFocus];

    [[NSGraphicsContext currentContext] setImageInterpolation:NSImageInterpolationHigh];
    [image drawInRect:NSMakeRect(0, 0, newWidth, newHeight)
             fromRect:NSZeroRect
            operation:NSCompositingOperationSourceOver
             fraction:1.0];

    [thumbnail unlockFocus];

    return thumbnail;
}

- (BOOL)catalogHasRetinaContent {
    if (!_computedCatalogHasRetinaContent) {
        for (NSString *name in self.catalog.allImageNames) {
            @autoreleasepool {
                CUINamedImage *image = [self.catalog imageWithName:name scaleFactor:2.0];
                if (image && image.scale > 1) {
                    _catalogHasRetinaContent = YES;
                    break;
                }
            }
        }
        _computedCatalogHasRetinaContent = YES;
    }
    return _catalogHasRetinaContent;
}

@end
