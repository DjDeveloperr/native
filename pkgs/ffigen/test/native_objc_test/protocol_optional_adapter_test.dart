// Copyright (c) 2026, the Dart project authors. Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

// Objective C support is only available on mac.
@TestOn('mac-os')
library;

import 'dart:ffi';
import 'dart:io';

import 'package:objective_c/objective_c.dart';
import 'package:path/path.dart' as path;
import 'package:test/test.dart';

import '../test_utils.dart';
import 'protocol_bindings.dart';
import 'util.dart';

final class PartialProtocolSugar
    with MyProtocolDefaults, MyProtocolAdapter
    implements MyProtocolSpec {
  @override
  Set<ObjCProtocolMethod<dynamic>> get $implementedOptionalMethods => {
    MyProtocol$Builder.optionalMethod_,
  };

  @override
  NSString instanceMethod(NSString s, {required double withDouble}) {
    return 'PartialProtocolSugar: ${s.toDartString()}: $withDouble'
        .toNSString();
  }

  @override
  int optionalMethod(SomeStruct s) => s.y - s.x;
}

void main() {
  late DynamicLibrary library;

  setUpAll(() {
    final dylib = File(
      path.join(
        packagePathForTests,
        'test',
        'native_objc_test',
        'objc_test.dylib',
      ),
    );
    verifySetupFile(dylib);
    library = loadDylibGlobally(dylib.absolute.path);
  });

  test('class adapter registers only implemented optional methods', () {
    expect(library, isNotNull);
    final myProtocol = PartialProtocolSugar().asMyProtocol;

    expect(
      myProtocol.object$.respondsToSelector('optionalMethod:'.toSelector()),
      isTrue,
    );
    expect(
      myProtocol.object$.respondsToSelector('voidMethod:'.toSelector()),
      isFalse,
    );
  });
}
