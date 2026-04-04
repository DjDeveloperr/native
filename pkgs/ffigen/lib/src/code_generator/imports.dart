// Copyright (c) 2022, the Dart project authors. Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import '../context.dart';
import '../visitor/ast.dart';

import 'type.dart';

/// A library import which will be written as an import in the generated file.
class LibraryImport extends AstNode {
  final String name;
  final String _importPath;
  final String? _importPathWhenImportedByPackageObjC;

  const LibraryImport(
    this.name,
    this._importPath, {
    String? importPathWhenImportedByPackageObjC,
  }) : _importPathWhenImportedByPackageObjC =
           importPathWhenImportedByPackageObjC;

  @override
  bool operator ==(Object other) {
    return other is LibraryImport && name == other.name;
  }

  @override
  int get hashCode => name.hashCode;

  // The import path, which may be different if this library is being imported
  // into package:objective_c's generated code.
  String importPath(bool generateForPackageObjectiveC) {
    if (!generateForPackageObjectiveC) return _importPath;
    return _importPathWhenImportedByPackageObjC ?? _importPath;
  }

  @override
  String toString() => '$name $_importPath';

  @override
  void visit(Visitation visitation) => visitation.visitLibraryImport(this);
}

/// An imported type which will be used in the generated code.
class ImportedType extends Type {
  final LibraryImport libraryImport;
  final String cType;
  final String dartType;
  final String nativeType;
  final String? defaultValue;
  final String? publicDartType;

  /// Whether the [dartType] is an import from the [libraryImport].
  final bool importedDartType;

  ImportedType(
    this.libraryImport,
    this.cType,
    this.dartType,
    this.nativeType, {
    this.defaultValue,
    this.importedDartType = false,
    this.publicDartType,
  });

  @override
  String getCType(Context context) =>
      '${context.libs.prefix(libraryImport)}.$cType';

  @override
  String getFfiDartType(Context context) {
    if (importedDartType) {
      return '${context.libs.prefix(libraryImport)}.$dartType';
    } else {
      return cType == dartType ? getCType(context) : dartType;
    }
  }

  @override
  String getNativeType({String varName = ''}) => '$nativeType $varName';

  @override
  bool get sameFfiDartAndCType => cType == dartType;

  @override
  String toString() => '${libraryImport.name}.$cType';

  @override
  String? getDefaultValue(Context context) => defaultValue;

  @override
  void visit(Visitation visitation) => visitation.visitImportedType(this);

  @override
  void visitChildren(Visitor visitor) {
    super.visitChildren(visitor);
    visitor.visit(libraryImport);
  }
}

class ImportedEnumType extends ImportedType {
  final String enumName;
  final String ffiCType;
  final String ffiDartType;

  ImportedEnumType(
    LibraryImport libraryImport, {
    required this.enumName,
    required this.ffiCType,
    required this.ffiDartType,
  }) : super(
         libraryImport,
         ffiCType,
         ffiDartType,
         _nativeTypeForImportedFfiCType(ffiCType),
       );

  @override
  String getCType(Context context) => ffiCType;

  @override
  String getFfiDartType(Context context) => ffiDartType;

  @override
  String getDartType(Context context) =>
      '${context.libs.prefix(libraryImport)}.$enumName';

  @override
  bool get sameDartAndFfiDartType => false;

  @override
  String convertDartTypeToFfiDartType(
    Context context,
    String value, {
    required bool objCRetain,
    required bool objCAutorelease,
  }) => '$value.value';

  @override
  String convertFfiDartTypeToDartType(
    Context context,
    String value, {
    required bool objCRetain,
    String? objCEnclosingClass,
  }) => '${context.libs.prefix(libraryImport)}.$enumName.fromValue($value)';

  @override
  String? getDefaultValue(Context context) => '0';

  @override
  String cacheKey() => 'ImportedEnum(${libraryImport.name}.$enumName)';
}

String _nativeTypeForImportedFfiCType(String ffiCType) => switch (ffiCType) {
  'ffi.Void' => 'void',
  'ffi.UnsignedChar' => 'unsigned char',
  'ffi.SignedChar' => 'signed char',
  'ffi.Char' => 'char',
  'ffi.UnsignedShort' => 'unsigned short',
  'ffi.Short' => 'short',
  'ffi.UnsignedInt' => 'unsigned',
  'ffi.Int' => 'int',
  'ffi.UnsignedLong' => 'unsigned long',
  'ffi.Long' => 'long',
  'ffi.UnsignedLongLong' => 'unsigned long long',
  'ffi.LongLong' => 'long long',
  'ffi.Float' => 'float',
  'ffi.Double' => 'double',
  'ffi.Size' => 'intptr_t',
  'ffi.WChar' => 'wchar_t',
  _ => ffiCType,
};

class ImportedTypealias extends ImportedType {
  final String cTypeName;
  final String ffiDartTypeName;
  final String dartTypeName;

  ImportedTypealias(
    LibraryImport libraryImport, {
    required this.cTypeName,
    required this.ffiDartTypeName,
    required this.dartTypeName,
  }) : super(libraryImport, cTypeName, ffiDartTypeName, cTypeName);

  @override
  String getCType(Context context) =>
      '${context.libs.prefix(libraryImport)}.$cTypeName';

  @override
  String getFfiDartType(Context context) =>
      '${context.libs.prefix(libraryImport)}.$ffiDartTypeName';

  @override
  String getDartType(Context context) =>
      '${context.libs.prefix(libraryImport)}.$dartTypeName';

  @override
  bool get sameFfiDartAndCType => cTypeName == ffiDartTypeName;

  @override
  bool get sameDartAndFfiDartType => dartTypeName == ffiDartTypeName;

  @override
  String cacheKey() =>
      'ImportedTypealias(${libraryImport.name}.$cTypeName->$dartTypeName)';
}

class ImportedObjCInstanceType extends ImportedTypealias {
  ImportedObjCInstanceType(
    super.libraryImport, {
    required super.cTypeName,
    required super.ffiDartTypeName,
    required super.dartTypeName,
  });

  @override
  String convertDartTypeToFfiDartType(
    Context context,
    String value, {
    required bool objCRetain,
    required bool objCAutorelease,
  }) => objCRetain
      ? (objCAutorelease
            ? '$value.ref.retainAndAutorelease()'
            : '$value.ref.retainAndReturnPointer()')
      : (objCAutorelease ? '$value.ref.autorelease()' : '$value.ref.pointer');

  @override
  String convertFfiDartTypeToDartType(
    Context context,
    String value, {
    required bool objCRetain,
    String? objCEnclosingClass,
  }) {
    if (objCEnclosingClass != null) {
      return '$objCEnclosingClass.fromPointer('
          '$value, retain: $objCRetain, release: true)';
    }
    return 'objc.ObjCObject('
        '$value, retain: $objCRetain, release: true)';
  }

  @override
  String getNativeType({String varName = ''}) => 'id $varName';

  @override
  String cacheKey() => 'ImportedObjCInstanceType(${libraryImport.name})';
}

/// An unchecked type similar to [ImportedType] which exists in the generated
/// binding itself.
class SelfImportedType extends Type {
  final String cType;
  final String dartType;
  final String? defaultValue;

  SelfImportedType(this.cType, this.dartType, [this.defaultValue]);

  @override
  String getCType(Context context) => cType;

  @override
  String getFfiDartType(Context context) => dartType;

  @override
  bool get sameFfiDartAndCType => cType == dartType;

  @override
  String toString() => cType;
}

const ffiImport = LibraryImport('ffi', 'dart:ffi');
const ffiPkgImport = LibraryImport('pkg_ffi', 'package:ffi/ffi.dart');
const objcPkgImport = LibraryImport(
  'objc',
  'package:objective_c/objective_c.dart',
  importPathWhenImportedByPackageObjC: '../objective_c.dart',
);
const selfImport = LibraryImport('self', '');
final builtInLibraries = {
  for (final l in [ffiImport, ffiPkgImport, objcPkgImport, selfImport])
    l.name: l,
};

final voidType = ImportedType(ffiImport, 'Void', 'void', 'void');

final unsignedCharType = ImportedType(
  ffiImport,
  'UnsignedChar',
  'int',
  'unsigned char',
  defaultValue: '0',
);
final signedCharType = ImportedType(
  ffiImport,
  'SignedChar',
  'int',
  'char',
  defaultValue: '0',
);
final charType = ImportedType(
  ffiImport,
  'Char',
  'int',
  'char',
  defaultValue: '0',
);
final unsignedShortType = ImportedType(
  ffiImport,
  'UnsignedShort',
  'int',
  'unsigned short',
  defaultValue: '0',
);
final shortType = ImportedType(
  ffiImport,
  'Short',
  'int',
  'short',
  defaultValue: '0',
);
final unsignedIntType = ImportedType(
  ffiImport,
  'UnsignedInt',
  'int',
  'unsigned',
  defaultValue: '0',
);
final intType = ImportedType(ffiImport, 'Int', 'int', 'int', defaultValue: '0');
final unsignedLongType = ImportedType(
  ffiImport,
  'UnsignedLong',
  'int',
  'unsigned long',
  defaultValue: '0',
);
final longType = ImportedType(
  ffiImport,
  'Long',
  'int',
  'long',
  defaultValue: '0',
);
final unsignedLongLongType = ImportedType(
  ffiImport,
  'UnsignedLongLong',
  'int',
  'unsigned long long',
  defaultValue: '0',
);
final longLongType = ImportedType(
  ffiImport,
  'LongLong',
  'int',
  'long long',
  defaultValue: '0',
);

final floatType = ImportedType(
  ffiImport,
  'Float',
  'double',
  'float',
  defaultValue: '0.0',
);
final doubleType = ImportedType(
  ffiImport,
  'Double',
  'double',
  'double',
  defaultValue: '0.0',
);

final sizeType = ImportedType(
  ffiImport,
  'Size',
  'int',
  'size_t',
  defaultValue: '0',
);
final wCharType = ImportedType(
  ffiImport,
  'WChar',
  'int',
  'wchar_t',
  defaultValue: '0',
);

final objCObjectType = ImportedType(
  objcPkgImport,
  'ObjCObjectImpl',
  'ObjCObjectImpl',
  'void',
);
final objCSelType = ImportedType(
  objcPkgImport,
  'ObjCSelector',
  'ObjCSelector',
  'struct objc_selector',
);
final objCBlockType = ImportedType(
  objcPkgImport,
  'ObjCBlockImpl',
  'ObjCBlockImpl',
  'id',
);
final objCProtocolType = ImportedType(
  objcPkgImport,
  'ObjCProtocolImpl',
  'ObjCProtocolImpl',
  'void',
);
final objCContextType = ImportedType(
  objcPkgImport,
  'DOBJC_Context',
  'DOBJC_Context',
  'DOBJC_Context',
);
