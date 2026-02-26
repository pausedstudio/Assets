//
//  CoreUI.h
//  AssetCatalogKit
//
//  Private CoreUI framework headers for reading .car files
//  Class-dumped from Apple's private CoreUI framework
//

#import <Cocoa/Cocoa.h>
#import "CoreSVG.h"

#pragma mark - Forward Declarations

@class CUIRenditionKey, CUIThemeRendition, CUIStructuredThemeStore, CUICommonAssetStorage;

#pragma mark - Theme State Constants

#define kCoreThemeStateNone -1

NS_INLINE NSString * _Nullable themeStateNameForThemeState(long long state) {
    switch (state) {
        case 0: return @"Normal";
        case 1: return @"Rollover";
        case 2: return @"Pressed";
        case 3: return @"Inactive";
        case 4: return @"Disabled";
        case 5: return @"DeeplyPressed";
        default: return nil;
    }
}

#pragma mark - Symbol Enums

typedef NS_ENUM(NSInteger, UIImageSymbolScale) {
    UIImageSymbolScaleDefault = -1,
    UIImageSymbolScaleUnspecified = 0,
    UIImageSymbolScaleSmall = 1,
    UIImageSymbolScaleMedium,
    UIImageSymbolScaleLarge,
};

typedef NS_ENUM(NSInteger, UIImageSymbolWeight) {
    UIImageSymbolWeightUnspecified = 0,
    UIImageSymbolWeightUltraLight = 1,
    UIImageSymbolWeightThin,
    UIImageSymbolWeightLight,
    UIImageSymbolWeightRegular,
    UIImageSymbolWeightMedium,
    UIImageSymbolWeightSemibold,
    UIImageSymbolWeightBold,
    UIImageSymbolWeightHeavy,
    UIImageSymbolWeightBlack
};

typedef NS_ENUM(NSInteger, UIImageSymbolRenderingMode) {
    UIImageSymbolRenderingModeAutomatic,
    UIImageSymbolRenderingModeTemplate,
    UIImageSymbolRenderingModeMulticolor,
    UIImageSymbolRenderingModeHierarchical,
};

#pragma mark - Rendition Key Token

struct _renditionkeytoken {
    unsigned short identifier;
    unsigned short value;
};

#pragma mark - CUINamedData

@interface CUINamedData : NSObject
@end

#pragma mark - CUINamedImage

@interface CUINamedImage : NSObject

@property (copy, nonatomic) NSString *name;
@property (readonly, nonatomic) int exifOrientation;
@property (readonly, nonatomic) BOOL isStructured;
@property (readonly, nonatomic) NSInteger templateRenderingMode;
@property (readonly, nonatomic) BOOL isTemplate;
@property (readonly, nonatomic) BOOL isVectorBased;
@property (readonly, nonatomic) BOOL hasSliceInformation;
@property (readonly, nonatomic) NSInteger resizingMode;
@property (readonly, nonatomic) int blendMode;
@property (readonly, nonatomic) CGFloat opacity;
@property (readonly, nonatomic) NSInteger imageType;
@property (readonly, nonatomic) CGFloat scale;
@property (readonly, nonatomic) NSSize size;
@property (readonly, nonatomic) CGImageRef image;

@end

#pragma mark - CUINamedLayerStack

@interface CUINamedLayerStack : CUINamedImage

@property (readonly, nonatomic) NSArray *layers;
@property (readonly, nonatomic) CGImageRef flattenedImage;

@end

#pragma mark - CUIRenditionKey

@interface CUIRenditionKey : NSObject <NSCopying>

@property (readonly) struct _renditionkeytoken *keyList;
@property (readonly) long long themeScale;
@property (readonly) long long themeState;
@property (readonly) long long themeDirection;
@property (readonly) long long themeSize;
@property (readonly) long long themeElement;
@property (readonly) long long themePart;
@property (readonly) long long themeGlyphWeight;
@property (readonly) long long themeGlyphSize;

- (struct _renditionkeytoken *)keyList;

@end

#pragma mark - CUIThemeRendition

@interface CUIThemeRendition : NSObject

@property (nonatomic, readonly) CGFloat scale;
@property (nonatomic, readonly) NSString *name;
@property (nonatomic, readonly) NSData *data;
@property (nonatomic, readonly) CGImageRef unslicedImage;
@property (nonatomic, readonly) BOOL isVectorBased;
@property (nonatomic, readonly) struct CGSVGDocument *svgDocument;
@property (nonatomic, readonly) long long vectorGlyphRenderingMode;
@property (nonatomic, readonly) int pixelFormat;
@property (nonatomic, readonly) NSInteger type;

@end

#pragma mark - CUICommonAssetStorage

@interface CUICommonAssetStorage : NSObject

@property (readonly) NSArray<CUIRenditionKey *> *allAssetKeys;
@property (readonly) NSString *path;
@property (readonly) NSUInteger storageVersion;
@property (readonly) NSArray *allRenditionNames;

- (void)enumerateKeysAndObjectsUsingBlock:(void (^)(CUIRenditionKey *key, id obj, BOOL *stop))block;

@end

#pragma mark - CUIStructuredThemeStore

@interface CUIStructuredThemeStore : NSObject

- (instancetype)initWithURL:(NSURL *)URL;
- (instancetype)initWithPath:(NSString *)path;
- (NSData *)lookupAssetForKey:(struct _renditionkeytoken *)key;
- (CUIThemeRendition *)renditionWithKey:(const struct _renditionkeytoken *)key;

@property (readonly) CUICommonAssetStorage *themeStore;

@end

#pragma mark - CUICatalog

@interface CUICatalog : NSObject

+ (instancetype)systemUICatalog;
+ (instancetype)defaultUICatalog;

- (instancetype)initWithURL:(NSURL *)url error:(NSError **)outError;
- (instancetype)initWithName:(NSString *)name fromBundle:(NSBundle *)bundle error:(NSError **)error;

@property (nonatomic, readonly) NSArray<NSString *> *allImageNames;
@property (nonatomic, readonly) NSArray<NSString *> *allColorNames;

- (CUINamedImage *)imageWithName:(NSString *)name scaleFactor:(CGFloat)scaleFactor;
- (CUINamedImage *)imageWithName:(NSString *)name
                     scaleFactor:(CGFloat)scaleFactor
                    deviceIdiom:(int)idiom;

- (NSArray *)imagesWithName:(NSString *)name;

- (CUIStructuredThemeStore *)_themeStore;

@end

#pragma mark - CUINamedColor

@interface CUINamedColor : NSObject

@property (nonatomic, readonly) NSString *name;
@property (nonatomic, readonly) CGColorRef cgColor;
@property (nonatomic, readonly) NSString *systemColorName;

@end

#pragma mark - CUIMutableCommonAssetStorage (for editing)

@interface CUIMutableCommonAssetStorage : CUICommonAssetStorage

- (instancetype)initWithPath:(NSString *)path forWriting:(BOOL)forWriting;
- (void)setAsset:(NSData *)asset forKey:(NSData *)key;
- (void)removeAssetForKey:(NSData *)key;
- (BOOL)writeToDiskAndCompact:(BOOL)compact;

@end

#pragma mark - CSIBitmapWrapper

@interface CSIBitmapWrapper : NSObject

- (instancetype)initWithPixelWidth:(uint32_t)width pixelHeight:(uint32_t)height;
- (void *)bitmapContext;
- (void)setSourceAlphaInfo:(CGImageAlphaInfo)alphaInfo;

@end

#pragma mark - CSIGenerator

@interface CSIGenerator : NSObject

// For images
- (instancetype)initWithCanvasSize:(CGSize)size sliceCount:(NSUInteger)count layout:(NSInteger)layout;

// For colors
- (instancetype)initWithColorNamed:(NSString *)name
                      colorSpaceID:(short)colorSpaceID
                        components:(const CGFloat *)components;

// Properties
@property (nonatomic, copy) NSString *name;
@property (nonatomic, assign) short colorSpaceID;
@property (nonatomic, assign) CGFloat scaleFactor;
@property (nonatomic, assign) int blendMode;
@property (nonatomic, assign) int templateRenderingMode;
@property (nonatomic, assign) BOOL isVectorBased;
@property (nonatomic, assign) BOOL excludedFromContrastFilter;

// Methods
- (void)addBitmap:(CSIBitmapWrapper *)wrapper;
- (void)addSliceRect:(CGRect)rect;
- (void)prepareToEditForRendition:(CUIThemeRendition *)rendition;
- (NSData *)CSIRepresentationWithCompression:(BOOL)compression;

@end

#pragma mark - CUIStructuredThemeStore Additions

@interface CUIStructuredThemeStore (Editing)

- (NSData *)convertRenditionKeyToKeyData:(const struct _renditionkeytoken *)key;

@end

#pragma mark - CUIThemeRendition Additions

@interface CUIThemeRendition (Editing)

- (BOOL)isInternalLink;
- (CGRect)_destinationFrame;
- (struct _renditionkeytoken *)key;

@end
