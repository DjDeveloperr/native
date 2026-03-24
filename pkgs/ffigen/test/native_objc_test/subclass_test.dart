// Copyright (c) 2026, the Dart project authors. Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

@TestOn('mac-os')
library;

import 'dart:ffi';
import 'dart:io';

import 'package:objective_c/objective_c.dart';
import 'package:path/path.dart' as path;
import 'package:test/test.dart';

import '../test_utils.dart';
import 'subclass_bindings.dart';
import 'util.dart';

final class DartSubclass
    with SubclassBaseDefaults, SubclassBaseSubclass
    implements SubclassBaseOverrides {
  @override
  Set<String> get objcOverrideSelectors => {
    SubclassBaseOverrideSelectors.loadValue,
    SubclassBaseOverrideSelectors.value,
  };

  @override
  void loadValue(int value) {
    asSubclassBase.number = value * 3;
  }

  @override
  int value() => asSubclassBase.number + 7;
}

void main() {
  Object? loadedDylib;

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
    loadedDylib = loadDylibGlobally(dylib.absolute.path);
    generateBindingsForCoverage('subclass');
  });

  test('Class-based subclass helpers override selected methods only', () {
    expect(loadedDylib, isNotNull);
    final consumer = SubclassConsumer();
    final object = DartSubclass().asSubclassBase;

    consumer.callLoadValue(object, value: 4);

    expect(object.number, 12);
    expect(consumer.callValue(object), 19);
    expect(consumer.callLabel(object).toDartString(), 'objc:12');
  });
}
