//
//  QuartzCorePrivate.h
//  Assets
//
//  Private QuartzCore headers for CAPackage / CAStateController support
//  Originally from Guilherme Rambo's CAARPlayer
//

#import <Cocoa/Cocoa.h>
#import <QuartzCore/QuartzCore.h>

@interface CAFilter : NSObject <NSCopying, NSMutableCopying, NSCoding>

+ (instancetype)filterWithType:(NSString *)type;
+ (NSArray <NSString *> *)filterTypes;

- (NSArray <NSString *> *)outputKeys;
- (NSArray <NSString *> *)inputKeys;
- (void)setDefaults;

@property(copy) NSString *name;
@property(readonly) NSString *type;

@property(getter=isEnabled) BOOL enabled;

@end

extern NSData *CAEncodeLayerTree(CALayer *rootLayer);

extern NSString *kCAPackageTypeArchive;
extern NSString *kCAPackageTypeCAMLBundle;

@interface CAPackage : NSObject

+ (id)packageWithData:(NSData *)data type:(NSString *)type options:(id)opts error:(NSError **)outError;
+ (id)packageWithContentsOfURL:(NSURL *)url type:(NSString *)type options:(id)opts error:(NSError **)outError;

- (NSArray <NSString *> *)publishedObjectNames;

@property(readonly, getter=isGeometryFlipped) BOOL geometryFlipped;
@property(readonly) CALayer *rootLayer;

@end

@interface CAStateController : NSObject;
@property (readonly) CALayer* layer;
-(void)setState:(id)arg1 ofLayer:(id)arg2 transitionSpeed:(float)arg3 ;
-(void)setState:(id)arg1 ofLayer:(id)arg2 ;
-(id)stateOfLayer:(id)arg1 ;
-(id)initWithLayer:(id)arg1;
-(void)setInitialStatesOfLayer:(id)arg1 transitionSpeed:(float)arg2 ;
-(void)_applyTransition:(id)arg1 layer:(id)arg2 undo:(id)arg3 speed:(float)arg4 ;
@end


@interface CAState : NSObject;
@end

@interface CALayer (CAState)
- (nullable NSString *)caStateName:(id)state;
@end
