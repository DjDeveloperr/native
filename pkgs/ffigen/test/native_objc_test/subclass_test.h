#import <Foundation/Foundation.h>

@interface SubclassBase : NSObject
@property(nonatomic, assign) int number;
- (int)value;
- (NSString *)label;
- (void)loadValue:(int)value;
@end

@interface SubclassConsumer : NSObject
- (int)callValue:(SubclassBase *)object;
- (NSString *)callLabel:(SubclassBase *)object;
- (void)callLoadValue:(SubclassBase *)object value:(int)value;
@end
