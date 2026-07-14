typedef enum SharedMode : unsigned long {
  SharedModeOff = 0,
  SharedModeOn = 1,
} SharedMode;

__attribute__((objc_root_class))
@interface SharedBase
@end

@protocol SharedProtocol
- (void)sharedMethod;
@end

@interface SharedBase (UpstreamExtras)
- (void)upstreamMethod;
@end

@interface LocalChild : SharedBase <SharedProtocol>
@property SharedMode mode;
@end

@interface SharedBase (LocalExtras)
- (SharedMode)localMode;
@end
