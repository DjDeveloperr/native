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
  test('copies only protocol methods needed for extension disambiguation', () {
    final library = parse(
      testContext(
        FfiGenerator(
          headers: Headers(
            entryPoints: [
              Uri.file(
                absPath(
                  'test/header_parser_tests/objc_protocol_method_dedup.h',
                ),
              ),
            ],
          ),
          objectiveC: const ObjectiveC(
            interfaces: Interfaces.includeAll,
            protocols: Protocols(
              include: Declarations.includeAll,
              generateFunctionHelpers: false,
              generateListenerHelpers: false,
            ),
          ),
          output: Output(
            dartFile: Uri.file('unused'),
            commentType: const CommentType.none(),
          ),
        ),
      ),
    );

    final output = library.generate();
    expect(output, isNot(contains('/// ProtocolConsumer')));
    expect(output, isNot(contains('/// collidingMethod')));
    expect(output, isNot(contains('implementAsListener')));
    expect(output, isNot(contains('implementAsBlocking')));
    expect(output, isNot(contains('static ChildProtocol implement({')));
    expect(output, isNot(contains('static void addToBuilder(')));
    expect(output, isNot(contains(r'$implementedOptionalMethods')));
    expect(output, contains('static ChildProtocol implementFrom('));
    expect(output, contains('static void addToBuilderFrom('));
    final consumerMethods = _extensionBody(
      output,
      'extension ProtocolConsumer\$Methods on ProtocolConsumer {',
    );
    expect(consumerMethods, contains('collidingMethod'));
    expect(consumerMethods, isNot(contains('uniqueMethod')));
    expect(consumerMethods, isNot(contains('inheritedMethod')));
    expect(consumerMethods, isNot(contains('childMethod')));

    final childMethods = _extensionBody(
      output,
      'extension ChildProtocol\$Methods on ChildProtocol {',
    );
    expect(childMethods, contains('inheritedMethod'));
    expect(childMethods, contains('childMethod'));
  });
}

String _extensionBody(String output, String declaration) {
  final start = output.indexOf(declaration);
  expect(start, isNonNegative);
  final end = output.indexOf('\n}\n\n', start);
  expect(end, isNonNegative);
  return output.substring(start, end);
}
