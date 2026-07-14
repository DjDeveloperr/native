#import "objc_stub_base.h"

@class ForwardOnly;

__attribute__((objc_root_class))
@interface LocalUser <ExternalProtocol>
- (ExternalBase *)externalBase;
- (ForwardOnly *)forwardOnly;
@end
