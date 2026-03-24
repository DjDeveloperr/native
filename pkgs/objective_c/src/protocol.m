// Copyright (c) 2024, the Dart project authors. Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

#include "protocol.h"

#import <Foundation/Foundation.h>
#import <objc/runtime.h>

#if !__has_feature(objc_arc)
#error "This file must be compiled with ARC enabled"
#endif

@class DOBJCDartProtocolBuilder;

@interface DOBJCDartGeneratedObjectContext : NSObject
- (instancetype)initWithBuilder:(DOBJCDartProtocolBuilder*)builder
                    disposePort:(Dart_Port)port;
- (id)getMethodForSelector:(SEL)sel;
@end

static uint8_t DOBJCDartGeneratedObjectContextKey = 0;

static id DOBJCGetMethodForSelector(id targetObject, SEL sel) {
  DOBJCDartGeneratedObjectContext* context = objc_getAssociatedObject(
    targetObject,
    &DOBJCDartGeneratedObjectContextKey
  );
  if (context == nil) return nil;
  return [context getMethodForSelector:sel];
}

static id DOBJCDartGeneratedObjectGetMethodForSelector(
    id self,
    SEL _cmd,
    SEL sel) {
  (void)_cmd;
  return DOBJCGetMethodForSelector(self, sel);
}

@implementation DOBJCDartProtocolBuilder {
  @public NSMutableDictionary* methods;
  Class clazz;
  BOOL usesDartProtocolBase;
}

- (instancetype)initWithClassName:(const char*)name {
  return [self initWithClassName:name
                       superclass:(__bridge void*)[DOBJCDartProtocol class]];
}

- (instancetype)initWithClassName:(const char*)name superclass:(void*)superclassPtr {
  self = [super init];
  if (self != nil) {
    methods = [NSMutableDictionary new];
    Class superclass = (__bridge Class)superclassPtr;
    usesDartProtocolBase = superclass == [DOBJCDartProtocol class];
    clazz = objc_allocateClassPair(superclass, name, 0);

    if (!usesDartProtocolBase) {
      class_addMethod(
          clazz,
          @selector(getDOBJCDartProtocolMethodForSelector:),
          (IMP)DOBJCDartGeneratedObjectGetMethodForSelector,
          "@@::");
    }
  }
  return self;
}

- (void)implementMethod:(SEL)sel
              withBlock:(void*)block
         withTrampoline:(void*)trampoline
          withSignature:(char*)signature {
  if (!class_addMethod(clazz, sel, (IMP)trampoline, signature)) {
    NSString* reason = [NSString stringWithFormat:
        @"Failed to add method %@ to generated class", NSStringFromSelector(sel)];
    @throw [NSException exceptionWithName:NSInternalInconsistencyException
                                   reason:reason
                                 userInfo:nil];
  }

  NSValue* key = [NSValue valueWithPointer:sel];
  @synchronized(methods) {
    [methods setObject:(__bridge id)block forKey:key];
  }
}

- (void)addProtocol:(Protocol*)protocol {
  class_addProtocol(clazz, protocol);
}

- (void)registerClass {
  objc_registerClassPair(clazz);
}

- (NSObject*)buildObject:(Dart_Port)port {
  id inst = [clazz alloc];
  if (usesDartProtocolBase) {
    return [(DOBJCDartProtocol*)inst
        initDOBJCDartProtocolFromDartProtocolBuilder:self
                                     withDisposePort:port];
  }

  inst = [inst init];
  if (inst == nil) return nil;

  DOBJCDartGeneratedObjectContext* context =
      [[DOBJCDartGeneratedObjectContext alloc] initWithBuilder:self
                                                   disposePort:port];
  objc_setAssociatedObject(
      inst,
      &DOBJCDartGeneratedObjectContextKey,
      context,
      OBJC_ASSOCIATION_RETAIN_NONATOMIC);
  return inst;
}

- (DOBJCDartProtocol*)buildInstance:(Dart_Port)port {
  return (DOBJCDartProtocol*)[self buildObject:port];
}

- (void)dealloc {
  objc_disposeClassPair(clazz);
}

@end

@implementation DOBJCDartGeneratedObjectContext {
  DOBJCDartProtocolBuilder* builder;
  Dart_Port dispose_port;
}

- (instancetype)initWithBuilder:(DOBJCDartProtocolBuilder*)builder_
                    disposePort:(Dart_Port)port {
  self = [super init];
  if (self != nil) {
    builder = builder_;
    dispose_port = port;
  }
  return self;
}

- (id)getMethodForSelector:(SEL)sel {
  @synchronized(builder->methods) {
    return [builder->methods objectForKey:[NSValue valueWithPointer:sel]];
  }
}

- (void)dealloc {
  if (dispose_port != ILLEGAL_PORT) {
    Dart_PostInteger_DL(dispose_port, 0);
  }
}

@end

@implementation DOBJCDartProtocol

- (id)getDOBJCDartProtocolMethodForSelector:(SEL)sel {
  return DOBJCGetMethodForSelector(self, sel);
}

- (instancetype)initDOBJCDartProtocolFromDartProtocolBuilder:
    (DOBJCDartProtocolBuilder*)builder_
    withDisposePort:(Dart_Port)port {
  self = [super init];
  if (self != nil) {
    DOBJCDartGeneratedObjectContext* context =
        [[DOBJCDartGeneratedObjectContext alloc] initWithBuilder:builder_
                                                     disposePort:port];
    objc_setAssociatedObject(
        self,
        &DOBJCDartGeneratedObjectContextKey,
        context,
        OBJC_ASSOCIATION_RETAIN_NONATOMIC);
  }
  return self;
}

- (void)dealloc {}

@end
