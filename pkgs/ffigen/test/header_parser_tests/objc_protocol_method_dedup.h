@protocol UniqueProtocol
- (void)uniqueMethod;
@end

@protocol LeftProtocol
- (void)collidingMethod;
@end

@protocol RightProtocol
- (void)collidingMethod;
@end

@protocol ParentProtocol
- (void)inheritedMethod;
@end

@protocol ChildProtocol <ParentProtocol>
- (void)childMethod;
@end

__attribute__((objc_root_class))
@interface ProtocolConsumer <
    UniqueProtocol,
    LeftProtocol,
    RightProtocol,
    ChildProtocol>
@end
