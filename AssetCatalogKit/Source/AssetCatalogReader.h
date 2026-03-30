//
//  AssetCatalogReader.h
//  AssetCatalogKit
//
//  Reads compiled Asset Catalog (.car) files using CoreUI
//

#import <Cocoa/Cocoa.h>

NS_ASSUME_NONNULL_BEGIN

/// Keys for asset dictionary
extern NSString *const kACKNameKey;
extern NSString *const kACKImageKey;
extern NSString *const kACKThumbnailKey;
extern NSString *const kACKFilenameKey;
extern NSString *const kACKContentsDataKey;
extern NSString *const kACKImageRepKey;
extern NSString *const kACKScaleKey;
extern NSString *const kACKIsVectorKey;
extern NSString *const kACKAssetTypeKey;
extern NSString *const kACKWidthKey;
extern NSString *const kACKHeightKey;

/// Asset types
typedef NS_ENUM(NSInteger, ACKAssetType) {
    ACKAssetTypeImage = 0,
    ACKAssetTypeImageSet,
    ACKAssetTypeIcon,
    ACKAssetTypeColor,
    ACKAssetTypeVector,
    ACKAssetTypeData,
    ACKAssetTypeUnknown
};

/// Reads assets from compiled .car files
@interface AssetCatalogReader : NSObject

/// Size for generated thumbnails (default: 64x64)
@property (nonatomic, assign) NSSize thumbnailSize;

/// Array of asset dictionaries after reading completes
@property (nonatomic, strong, readonly) NSArray<NSDictionary<NSString *, id> *> *assets;

/// Name of the catalog being read
@property (nonatomic, copy, nullable) NSString *catalogName;

/// Error encountered during reading, if any
@property (nonatomic, copy, nullable) NSError *error;

/// Total number of assets in the catalog
@property (readonly) NSUInteger totalNumberOfAssets;

/// Set to YES to cancel an in-progress read
@property (nonatomic, assign) BOOL cancelled;

/// Initialize with a file URL to a .car file or app bundle
- (instancetype)initWithFileURL:(NSURL *)URL;

/// Read all assets with progress reporting
/// @param callback Called on main thread when reading completes
/// @param progressCallback Called on main thread with progress (0.0 - 1.0)
- (void)readWithCompletionHandler:(void (^)(void))callback
                  progressHandler:(void (^_Nullable)(double progress))progressCallback;

/// Lightweight read for QuickLook (limits asset count, uses image reps instead of full images)
/// @param max Maximum number of assets to load
/// @param callback Called on main thread when reading completes
- (void)resourceConstrainedReadWithMaxCount:(int)max
                          completionHandler:(void (^)(void))callback;

/// Synchronous read for use in extension contexts (no main queue dispatch)
/// @param max Maximum number of assets to load
- (void)readSyncWithMaxCount:(int)max;

/// Cancel an in-progress read operation
- (void)cancelReading;

@end

NS_ASSUME_NONNULL_END
