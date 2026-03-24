#import "subclass_test.h"

@implementation SubclassBase
- (int)value {
  return self.number + 1;
}

- (NSString *)label {
  return [NSString stringWithFormat:@"objc:%d", self.number];
}

- (void)loadValue:(int)value {
  self.number = value;
}
@end

@implementation SubclassConsumer
- (int)callValue:(SubclassBase *)object {
  return [object value];
}

- (NSString *)callLabel:(SubclassBase *)object {
  return [object label];
}

- (void)callLoadValue:(SubclassBase *)object value:(int)value {
  [object loadValue:value];
}
@end
