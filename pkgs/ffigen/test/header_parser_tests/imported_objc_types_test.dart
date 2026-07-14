// Copyright (c) 2026, the Dart project authors. Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

@TestOn('mac-os')
library;

import 'package:ffigen/ffigen.dart';
import 'package:ffigen/src/header_parser.dart';
import 'package:test/test.dart';

import '../test_utils.dart';

void main() {
  test('Objective-C declarations can extend imported symbol-file types', () {
    const sharedImport = LibraryImport('shared', 'package:shared/shared.dart');
    ImportedType imported(String name) =>
        ImportedType(sharedImport, name, name, name, importedDartType: true);

    final library = parse(
      testContext(
        FfiGenerator(
          headers: Headers(
            entryPoints: [
              Uri.file(
                absPath('test/header_parser_tests/imported_objc_types.h'),
              ),
            ],
          ),
          enums: Enums.includeAll,
          objectiveC: const ObjectiveC(
            interfaces: Interfaces.includeAll,
            protocols: Protocols.includeAll,
            categories: Categories.includeAll,
          ),
          output: Output(dartFile: Uri.file('unused')),
          // ignore: deprecated_member_use_from_same_package
          importedTypesByUsr: {
            'c:objc(cs)SharedBase': imported('SharedBase'),
            'c:objc(pl)SharedProtocol': imported('SharedProtocol'),
            'c:objc(cy)SharedBase@UpstreamExtras': imported('UpstreamExtras'),
            'c:@E@SharedMode': imported('SharedMode'),
          },
          // ignore: deprecated_member_use_from_same_package
          libraryImports: const [sharedImport],
        ),
      ),
    );

    final output = library.generate();
    expect(output, contains("import 'package:shared/shared.dart' as shared;"));
    expect(output, isNot(contains('extension type SharedBase.')));
    expect(output, isNot(contains('extension type SharedProtocol.')));
    expect(output, isNot(contains('enum SharedMode')));
    expect(output, isNot(contains('extension UpstreamExtras')));
    expect(output, contains('implements objc.ObjCObject,shared.SharedBase'));
    expect(output, contains('extension LocalExtras on shared.SharedBase'));
    expect(output, contains('shared.SharedMode localMode()'));
    expect(output, contains('shared.SharedMode get mode'));
  });

  test('Objective-C stubs are not exported as shared symbols', () {
    final header = Uri.file(
      absPath('test/header_parser_tests/objc_stub_user.h'),
    );
    final library = parse(
      testContext(
        FfiGenerator(
          headers: Headers(
            entryPoints: [header],
            include: (candidate) => candidate == header,
          ),
          objectiveC: ObjectiveC(
            interfaces: Interfaces(
              include: (declaration) =>
                  declaration.originalName == 'LocalUser' ||
                  declaration.originalName == 'ForwardOnly',
            ),
            protocols: const Protocols(include: Declarations.excludeAll),
          ),
          output: Output(dartFile: Uri.file('unused')),
        ),
      ),
    );

    final output = library.generate();
    expect(output, contains('WARNING: ExternalBase is a stub'));
    expect(output, contains('WARNING: ExternalProtocol is a stub'));
    expect(output, isNot(contains('WARNING: ForwardOnly is a stub')));

    final symbols = library.writer.generateSymbolOutputYamlMap(
      'package:local/local.dart',
    );
    final files = symbols['files'] as Map<String, dynamic>;
    final file = files['package:local/local.dart'] as Map<String, dynamic>;
    final exported = file['symbols'] as Map<String, dynamic>;
    expect(exported, contains('c:objc(cs)LocalUser'));
    expect(exported, isNot(contains('c:objc(cs)ExternalBase')));
    expect(exported, isNot(contains('c:objc(cs)ForwardOnly')));
    expect(exported, isNot(contains('c:objc(pl)ExternalProtocol')));
  });
}
