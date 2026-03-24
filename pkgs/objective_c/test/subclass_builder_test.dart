// Copyright (c) 2026, the Dart project authors. Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

// Objective C support is only available on mac.
@TestOn('mac-os')
library;

import 'dart:ffi';

import 'package:ffi/ffi.dart';
import 'package:objective_c/objective_c.dart';
import 'package:objective_c/src/objective_c_bindings_generated.dart';
import 'package:test/test.dart';

void main() {
  group('ObjCSubclassBuilder', () {
    test('can subclass NSObject', () {
      final builder = ObjCSubclassBuilder(
        superclassName: 'NSObject',
        debugName: 'DartNSObjectSubclass',
      );
      final signature = '@@:'.toNativeUtf8();
      builder.implementMethod(
        registerName('description'),
        signature.cast(),
        ObjCBlock_NSString_ffiVoid.protocolTrampoline,
        ObjCBlock_NSString_ffiVoid.fromFunction(
          (Pointer<Void> _) => 'Dart NSObject subclass'.toNSString(),
        ),
      );
      calloc.free(signature);

      final object = NSObject.as(builder.build());
      expect(object.description.toDartString(), 'Dart NSObject subclass');
    });
  });
}
