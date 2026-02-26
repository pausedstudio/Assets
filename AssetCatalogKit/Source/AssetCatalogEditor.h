//
//  AssetCatalogEditor.h
//  AssetCatalogKit
//
//  Editor for modifying compiled Asset Catalog (.car) files
//

#import <Cocoa/Cocoa.h>

NS_ASSUME_NONNULL_BEGIN

/// Editor for modifying .car files
@interface AssetCatalogEditor : NSObject

/// Initialize editor with a .car file URL
/// @param URL Path to the .car file
/// @note The file will be opened in write mode
- (nullable instancetype)initWithFileURL:(NSURL *)URL error:(NSError **)error;

/// Replace an image rendition with a new image
/// @param name The rendition name
/// @param scale The scale factor (@1x, @2x, @3x)
/// @param newImage The replacement CGImage
/// @param error Error output
/// @return YES if successful
- (BOOL)replaceImageNamed:(NSString *)name
                    scale:(CGFloat)scale
                withImage:(CGImageRef)newImage
                    error:(NSError **)error;

/// Replace a color rendition with a new color
/// @param name The color name
/// @param newColor The replacement CGColor
/// @param error Error output
/// @return YES if successful
- (BOOL)replaceColorNamed:(NSString *)name
                withColor:(CGColorRef)newColor
                    error:(NSError **)error;

/// Remove a rendition from the catalog
/// @param name The rendition name
/// @param scale The scale factor (0 for colors)
/// @param error Error output
/// @return YES if successful
- (BOOL)removeRenditionNamed:(NSString *)name
                       scale:(CGFloat)scale
                       error:(NSError **)error;

/// Save all changes to disk
/// @param error Error output
/// @return YES if successful
- (BOOL)saveWithError:(NSError **)error;

/// Discard changes and close the editor
- (void)close;

@end

NS_ASSUME_NONNULL_END
