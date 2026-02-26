//
//  AssetCatalogEditor.m
//  AssetCatalogKit
//
//  Implementation for editing compiled Asset Catalog (.car) files
//

#import "AssetCatalogEditor.h"
#import "CoreUI.h"

static NSString *const kAssetCatalogEditorErrorDomain = @"com.assets.AssetCatalogEditor";

@interface AssetCatalogEditor ()

@property (nonatomic, copy) NSURL *fileURL;
@property (nonatomic, strong) CUICatalog *catalog;
@property (nonatomic, strong) CUIMutableCommonAssetStorage *mutableStorage;
@property (nonatomic, strong) CUIStructuredThemeStore *themeStore;

@end

@implementation AssetCatalogEditor

#pragma mark - Initialization

- (nullable instancetype)initWithFileURL:(NSURL *)URL error:(NSError **)error {
    self = [super init];
    if (self) {
        _fileURL = [URL copy];

        // Open the catalog for reading (to get rendition info)
        NSError *catalogError = nil;
        _catalog = [[CUICatalog alloc] initWithURL:URL error:&catalogError];
        if (catalogError) {
            if (error) *error = catalogError;
            return nil;
        }

        _themeStore = [_catalog _themeStore];
        if (!_themeStore) {
            if (error) {
                *error = [NSError errorWithDomain:kAssetCatalogEditorErrorDomain
                                             code:1
                                         userInfo:@{NSLocalizedDescriptionKey: @"Unable to access theme store"}];
            }
            return nil;
        }

        // Open mutable storage for writing
        _mutableStorage = [[CUIMutableCommonAssetStorage alloc] initWithPath:URL.path forWriting:YES];
        if (!_mutableStorage) {
            if (error) {
                *error = [NSError errorWithDomain:kAssetCatalogEditorErrorDomain
                                             code:2
                                         userInfo:@{NSLocalizedDescriptionKey: @"Unable to open catalog for writing"}];
            }
            return nil;
        }
    }
    return self;
}

#pragma mark - Image Editing

- (BOOL)replaceImageNamed:(NSString *)name
                    scale:(CGFloat)scale
                withImage:(CGImageRef)newImage
                    error:(NSError **)error {
    if (!newImage) {
        if (error) {
            *error = [NSError errorWithDomain:kAssetCatalogEditorErrorDomain
                                         code:10
                                     userInfo:@{NSLocalizedDescriptionKey: @"New image cannot be nil"}];
        }
        return NO;
    }

    // Find the rendition
    CUIThemeRendition *rendition = [self findRenditionNamed:name scale:scale];
    if (!rendition) {
        if (error) {
            *error = [NSError errorWithDomain:kAssetCatalogEditorErrorDomain
                                         code:11
                                     userInfo:@{NSLocalizedDescriptionKey:
                                         [NSString stringWithFormat:@"Rendition '%@' at scale %.0fx not found", name, scale]}];
        }
        return NO;
    }

    // Get the key data for this rendition
    NSData *keyData = [_themeStore convertRenditionKeyToKeyData:[rendition key]];
    if (!keyData) {
        if (error) {
            *error = [NSError errorWithDomain:kAssetCatalogEditorErrorDomain
                                         code:12
                                     userInfo:@{NSLocalizedDescriptionKey: @"Unable to convert rendition key"}];
        }
        return NO;
    }

    // Get image dimensions
    size_t width = CGImageGetWidth(newImage);
    size_t height = CGImageGetHeight(newImage);
    CGSize canvasSize = CGSizeMake(width, height);

    // Create CSI generator
    // Layout 0 = one-part image (no slicing)
    CSIGenerator *generator = [[CSIGenerator alloc] initWithCanvasSize:canvasSize sliceCount:1 layout:0];
    if (!generator) {
        if (error) {
            *error = [NSError errorWithDomain:kAssetCatalogEditorErrorDomain
                                         code:13
                                     userInfo:@{NSLocalizedDescriptionKey: @"Unable to create CSI generator"}];
        }
        return NO;
    }

    // Create bitmap wrapper and draw new image
    CSIBitmapWrapper *wrapper = [[CSIBitmapWrapper alloc] initWithPixelWidth:(uint32_t)width
                                                                 pixelHeight:(uint32_t)height];
    if (!wrapper) {
        if (error) {
            *error = [NSError errorWithDomain:kAssetCatalogEditorErrorDomain
                                         code:14
                                     userInfo:@{NSLocalizedDescriptionKey: @"Unable to create bitmap wrapper"}];
        }
        return NO;
    }

    // Get the bitmap context and draw the new image
    void *bitmapContextPtr = [wrapper bitmapContext];
    if (bitmapContextPtr) {
        CGContextRef context = (CGContextRef)bitmapContextPtr;
        CGContextDrawImage(context, CGRectMake(0, 0, width, height), newImage);
    }

    // Configure generator from original rendition
    [generator addBitmap:wrapper];
    [generator addSliceRect:CGRectMake(0, 0, width, height)];
    [generator prepareToEditForRendition:rendition];
    generator.scaleFactor = scale;

    // Generate new CSI data
    NSData *csiData = [generator CSIRepresentationWithCompression:YES];
    if (!csiData) {
        if (error) {
            *error = [NSError errorWithDomain:kAssetCatalogEditorErrorDomain
                                         code:15
                                     userInfo:@{NSLocalizedDescriptionKey: @"Unable to generate CSI representation"}];
        }
        return NO;
    }

    // Write to storage
    [_mutableStorage setAsset:csiData forKey:keyData];

    return YES;
}

#pragma mark - Color Editing

- (BOOL)replaceColorNamed:(NSString *)name
                withColor:(CGColorRef)newColor
                    error:(NSError **)error {
    if (!newColor) {
        if (error) {
            *error = [NSError errorWithDomain:kAssetCatalogEditorErrorDomain
                                         code:20
                                     userInfo:@{NSLocalizedDescriptionKey: @"New color cannot be nil"}];
        }
        return NO;
    }

    // Find the color rendition
    CUIThemeRendition *rendition = [self findColorRenditionNamed:name];
    if (!rendition) {
        if (error) {
            *error = [NSError errorWithDomain:kAssetCatalogEditorErrorDomain
                                         code:21
                                     userInfo:@{NSLocalizedDescriptionKey:
                                         [NSString stringWithFormat:@"Color '%@' not found", name]}];
        }
        return NO;
    }

    // Get the key data
    NSData *keyData = [_themeStore convertRenditionKeyToKeyData:[rendition key]];
    if (!keyData) {
        if (error) {
            *error = [NSError errorWithDomain:kAssetCatalogEditorErrorDomain
                                         code:22
                                     userInfo:@{NSLocalizedDescriptionKey: @"Unable to convert rendition key"}];
        }
        return NO;
    }

    // Get color components
    const CGFloat *components = CGColorGetComponents(newColor);
    size_t numComponents = CGColorGetNumberOfComponents(newColor);

    // Determine color space ID (1 = sRGB, common default)
    short colorSpaceID = 1;

    // Create color generator
    CSIGenerator *generator = [[CSIGenerator alloc] initWithColorNamed:name
                                                          colorSpaceID:colorSpaceID
                                                            components:components];
    if (!generator) {
        if (error) {
            *error = [NSError errorWithDomain:kAssetCatalogEditorErrorDomain
                                         code:23
                                     userInfo:@{NSLocalizedDescriptionKey: @"Unable to create color generator"}];
        }
        return NO;
    }

    // Generate CSI representation
    NSData *csiData = [generator CSIRepresentationWithCompression:YES];
    if (!csiData) {
        if (error) {
            *error = [NSError errorWithDomain:kAssetCatalogEditorErrorDomain
                                         code:24
                                     userInfo:@{NSLocalizedDescriptionKey: @"Unable to generate color CSI"}];
        }
        return NO;
    }

    // Write to storage
    [_mutableStorage setAsset:csiData forKey:keyData];

    return YES;
}

#pragma mark - Remove Rendition

- (BOOL)removeRenditionNamed:(NSString *)name
                       scale:(CGFloat)scale
                       error:(NSError **)error {
    CUIThemeRendition *rendition = nil;

    if (scale > 0) {
        rendition = [self findRenditionNamed:name scale:scale];
    } else {
        rendition = [self findColorRenditionNamed:name];
    }

    if (!rendition) {
        if (error) {
            *error = [NSError errorWithDomain:kAssetCatalogEditorErrorDomain
                                         code:30
                                     userInfo:@{NSLocalizedDescriptionKey:
                                         [NSString stringWithFormat:@"Rendition '%@' not found", name]}];
        }
        return NO;
    }

    NSData *keyData = [_themeStore convertRenditionKeyToKeyData:[rendition key]];
    if (!keyData) {
        if (error) {
            *error = [NSError errorWithDomain:kAssetCatalogEditorErrorDomain
                                         code:31
                                     userInfo:@{NSLocalizedDescriptionKey: @"Unable to convert rendition key"}];
        }
        return NO;
    }

    [_mutableStorage removeAssetForKey:keyData];

    return YES;
}

#pragma mark - Save

- (BOOL)saveWithError:(NSError **)error {
    BOOL success = [_mutableStorage writeToDiskAndCompact:YES];

    if (!success && error) {
        *error = [NSError errorWithDomain:kAssetCatalogEditorErrorDomain
                                     code:40
                                 userInfo:@{NSLocalizedDescriptionKey: @"Failed to write changes to disk"}];
    }

    return success;
}

- (void)close {
    _mutableStorage = nil;
    _themeStore = nil;
    _catalog = nil;
}

#pragma mark - Private Helpers

- (CUIThemeRendition *)findRenditionNamed:(NSString *)name scale:(CGFloat)scale {
    // Get image at specified scale
    CUINamedImage *namedImage = [_catalog imageWithName:name scaleFactor:scale];
    if (!namedImage) {
        return nil;
    }

    // We need to iterate through the theme store to find the matching rendition
    // This is a simplified approach - in production you'd want to be more precise
    __block CUIThemeRendition *foundRendition = nil;

    NSArray<CUIRenditionKey *> *allKeys = _themeStore.themeStore.allAssetKeys;
    for (CUIRenditionKey *key in allKeys) {
        @autoreleasepool {
            CUIThemeRendition *rendition = [_themeStore renditionWithKey:key.keyList];
            if (rendition &&
                [rendition.name isEqualToString:name] &&
                fabs(rendition.scale - scale) < 0.01) {
                foundRendition = rendition;
                break;
            }
        }
    }

    return foundRendition;
}

- (CUIThemeRendition *)findColorRenditionNamed:(NSString *)name {
    __block CUIThemeRendition *foundRendition = nil;

    NSArray<CUIRenditionKey *> *allKeys = _themeStore.themeStore.allAssetKeys;
    for (CUIRenditionKey *key in allKeys) {
        @autoreleasepool {
            CUIThemeRendition *rendition = [_themeStore renditionWithKey:key.keyList];
            // Color renditions have type that indicates color
            if (rendition && [rendition.name isEqualToString:name]) {
                // Check if this is a color type (simplified check)
                foundRendition = rendition;
                break;
            }
        }
    }

    return foundRendition;
}

@end
