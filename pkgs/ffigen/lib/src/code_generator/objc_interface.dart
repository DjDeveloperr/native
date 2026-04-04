// Copyright (c) 2022, the Dart project authors. Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import '../code_generator.dart';
import '../context.dart';
import '../header_parser/sub_parsers/api_availability.dart';
import '../visitor/ast.dart';
import 'binding_string.dart';
import 'scope.dart';
import 'utils.dart';
import 'writer.dart';

class ObjCInterface extends BindingType with ObjCMethods, HasLocalScope {
  @override
  final Context context;
  ObjCInterface? superType;
  bool filled = false;

  final String lookupName;
  late final ObjCInternalGlobal classObject;
  late final ObjCInternalGlobal _isKindOfClass;
  late final ObjCMsgSendFunc _isKindOfClassMsgSend;
  final protocols = <ObjCProtocol>[];
  final categories = <ObjCCategory>[];
  final subtypes = <ObjCInterface>[];
  final ApiAvailability apiAvailability;

  // Filled by ListBindingsVisitation.
  bool generateAsStub = false;
  bool generateSubclassHelpers = false;

  ObjCInterface({
    super.usr,
    required String super.originalName,
    String? name,
    String? lookupName,
    super.dartDoc,
    required this.apiAvailability,
    required this.context,
  }) : lookupName = lookupName ?? originalName,
       super(
         name:
             context.objCBuiltInFunctions.getBuiltInInterfaceName(
               originalName,
             ) ??
             name ??
             originalName,
       ) {
    classObject = ObjCInternalGlobal(
      '_class_$originalName',
      () => '${ObjCBuiltInFunctions.getClass.gen(context)}("$lookupName")',
    );
    _isKindOfClass = context.objCBuiltInFunctions.getSelObject(
      'isKindOfClass:',
    );
    _isKindOfClassMsgSend = context.objCBuiltInFunctions.getMsgSendFunc(
      BooleanType(),
      [
        Parameter(
          name: 'clazz',
          type: PointerType(objCObjectType),
          objCConsumed: false,
        ),
      ],
    );
  }

  void addProtocol(ObjCProtocol? proto) {
    if (proto != null) protocols.add(proto);
  }

  @override
  bool get isObjCImport =>
      context.objCBuiltInFunctions.getBuiltInInterfaceName(originalName) !=
      null;

  bool get unavailable => apiAvailability.availability == Availability.none;

  bool _supportsSubclassHelper(ObjCMethod method) {
    if (method.isClassMethod) return false;
    if (method.apiAvailability.availability == Availability.none) return false;
    if (method.originalName == 'dealloc') return false;
    return switch (method.family) {
      ObjCMethodFamily.alloc ||
      ObjCMethodFamily.init ||
      ObjCMethodFamily.new_ ||
      ObjCMethodFamily.copy ||
      ObjCMethodFamily.mutableCopy => false,
      _ => true,
    };
  }

  String _subclassPropertyName(ObjCMethod method) =>
      stripGeneratedNameSuffix(method.symbol.name);

  String _subclassMethodName(ObjCMethod method) {
    final methodName = switch (method.kind) {
      ObjCMethodKind.propertyGetter ||
      ObjCMethodKind.propertySetter => _subclassPropertyName(method),
      ObjCMethodKind.method => method.symbol.name,
    };
    return switch (method.kind) {
      ObjCMethodKind.method => methodName,
      ObjCMethodKind.propertyGetter => methodName,
      ObjCMethodKind.propertySetter => methodName,
    };
  }

  String _subclassReturnType(ObjCMethod method, String targetType) {
    if (method.returnType is ObjCInstanceType ||
        method.returnType is ImportedObjCInstanceType) {
      return targetType;
    }
    final baseType = method.returnType.typealiasType;
    if (baseType is ObjCNullable &&
        (baseType.child is ObjCInstanceType ||
            baseType.child is ImportedObjCInstanceType)) {
      return '$targetType?';
    }
    return method.returnType.getDartType(context);
  }

  String _joinSubclassParamStr(List<Parameter> params) {
    if (params.isEmpty) return '';
    String paramToStr(Parameter p) =>
        '${p.type.getDartType(context)} ${p.name}';
    String paramToNamed(Parameter p) =>
        '${p.isNullable ? '' : 'required '}${paramToStr(p)}';
    if (params.length == 1) return paramToStr(params.first);
    final named = params.sublist(1).map(paramToNamed).join(',');
    return '${paramToStr(params.first)}, {$named}';
  }

  String _subclassInterfaceDeclaration(ObjCMethod method, String targetType) {
    final returnTypeStr = _subclassReturnType(method, targetType);
    final params = method.returnsNSErrorByOutParam
        ? method.params.toList().sublist(0, method.params.length - 1)
        : method.params.toList();
    final paramStr = _joinSubclassParamStr(params);
    final methodName = _subclassMethodName(method);

    return switch (method.kind) {
      ObjCMethodKind.method => '$returnTypeStr $methodName($paramStr);',
      ObjCMethodKind.propertyGetter => '$returnTypeStr get $methodName;',
      ObjCMethodKind.propertySetter => 'set $methodName($paramStr);',
    };
  }

  String _subclassInvocationArgumentList(ObjCMethod method) {
    final params = method.returnsNSErrorByOutParam
        ? method.params.toList().sublist(0, method.params.length - 1)
        : method.params.toList();
    if (params.isEmpty) return '';
    if (params.length == 1) return params.first.name;

    final positional = params.first.name;
    final named = params.skip(1).map((p) => '${p.name}: ${p.name}').join(', ');
    return '$positional, $named';
  }

  String _subclassImplementationInvocation(
    ObjCMethod method,
    String implementationVar,
  ) {
    final methodName = _subclassMethodName(method);
    final args = _subclassInvocationArgumentList(method);

    return switch (method.kind) {
      ObjCMethodKind.method => '$implementationVar.$methodName($args)',
      ObjCMethodKind.propertyGetter => '$implementationVar.$methodName',
      ObjCMethodKind.propertySetter => '$implementationVar.$methodName = $args',
    };
  }

  String _subclassAdapterClosure(ObjCMethod method, String implementationVar) {
    final invocation = _subclassImplementationInvocation(
      method,
      implementationVar,
    );
    final blockFirstArg = method.protocolBlock!.params.first.type.getDartType(
      context,
    );
    final closureParams = method.params
        .map((p) => '${p.type.getDartType(context)} ${p.name}')
        .join(', ');
    final argList = closureParams.isEmpty
        ? '$blockFirstArg _'
        : '$blockFirstArg _, $closureParams';

    if (method.returnType == voidType) {
      return '($argList) { $invocation; }';
    }
    return '($argList) => $invocation';
  }

  String _subclassSelectorField(ObjCMethod method) =>
      _selectorFieldName(method.originalName);

  String _selectorFieldName(String selector) {
    final parts = selector.split(':').where((part) => part.isNotEmpty).toList();
    if (parts.isEmpty) {
      return selector;
    }
    if (parts.length == 1) {
      return parts.single;
    }

    final head = parts.first;
    final tail = parts
        .skip(1)
        .map((part) => part[0].toUpperCase() + part.substring(1))
        .join();
    return '$head$tail';
  }

  static String _trampolineAddress(Writer w, ObjCBlock block) {
    return block.protocolTrampolineAccessor(w.context);
  }

  String _generateSubclassHelpers(Writer w) {
    final subclassMethods = methods.where(_supportsSubclassHelper).toList();
    if (subclassMethods.isEmpty) return '';

    final subclassBuilder = ObjCBuiltInFunctions.subclassBuilder.gen(context);
    final getSignature = ObjCBuiltInFunctions.getInterfaceMethodSignature.gen(
      context,
    );
    final objCRuntimeError = ObjCBuiltInFunctions.objCRuntimeError.gen(context);
    final specClass = '${name}Overrides';
    final defaultsMixin = '${name}Defaults';
    final selectorsClass = '${name}OverrideSelectors';
    final builderClass = '${name}SubclassBuilder';
    final subclassMixin = '${name}Subclass';
    final targetType = getDartType(context);

    final declarations = StringBuffer();
    final selectorConstants = StringBuffer();
    final builderImplementations = StringBuffer();
    final selectorSetEntries = StringBuffer();

    for (final method in subclassMethods) {
      declarations.write(makeDartDoc(method.dartDoc));
      declarations.write(
        '  ${_subclassInterfaceDeclaration(method, targetType)}\n',
      );

      final selectorField = _subclassSelectorField(method);
      selectorConstants.write(makeDartDoc(method.dartDoc));
      selectorConstants.write(
        "  static const $selectorField = '${method.originalName}';\n",
      );
      selectorSetEntries.write('''
    $selectorsClass.$selectorField,''');

      final adapterClosure = _subclassAdapterClosure(method, 'implementation');
      final block = method.protocolBlock!;
      block.fillProtocolTrampoline();
      builderImplementations.write('''
    if (overrideSelectors.contains($selectorsClass.$selectorField)) {
      final signature = $getSignature(${classObject.name}, ${method.selObject.name});
      if (signature == null) {
        throw $objCRuntimeError(
          'Failed to load Objective-C method signature: $originalName.${method.originalName}',
        );
      }
      builder.implementMethod(
        ${method.selObject.name},
        signature,
        ${_trampolineAddress(w, block)},
        ${block.helperClassRef(context)}.fromFunction($adapterClosure),
      );
    }
''');
    }

    return '''
abstract interface class $specClass {
${declarations.toString()}
}

mixin $defaultsMixin implements $specClass {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

abstract final class $selectorsClass {
${selectorConstants.toString()}

  static Set<String> get all => {
$selectorSetEntries
  };
}

interface class $builderClass {
  /// Builds a Dart-backed subclass of $originalName using members from
  /// [implementation].
  static $name buildFrom(
    $specClass implementation, {
    required Set<String> overrideSelectors,
    bool \$keepIsolateAlive = true,
  }) {
    final builder = $subclassBuilder(
      superclassName: '$lookupName',
      debugName: '$originalName',
    );
    addToBuilderFrom(
      builder,
      implementation,
      overrideSelectors: overrideSelectors,
    );
    return $name.as(builder.build(keepIsolateAlive: \$keepIsolateAlive));
  }

  /// Adds Dart overrides for $originalName to an existing [$subclassBuilder].
  static void addToBuilderFrom(
    $subclassBuilder builder,
    $specClass implementation, {
    required Set<String> overrideSelectors,
  }) {
$builderImplementations  }
}

mixin $subclassMixin {
  /// The Objective-C selectors that this Dart class overrides.
  Set<String> get objcOverrideSelectors;

  /// Lazily creates a native subclass instance for this Dart implementation.
  late final $name as$name = $builderClass.buildFrom(
    this as $specClass,
    overrideSelectors: objcOverrideSelectors,
  );
}

''';
  }

  @override
  BindingString toBindingString(Writer w) {
    final context = w.context;
    final s = StringBuffer();
    s.write('\n');
    if (generateAsStub) {
      s.write('''
/// WARNING: $name is a stub. To generate bindings for this class, include
/// $originalName in your config's objc-interfaces list.
///
''');
    }
    s.write(makeDartDoc(dartDoc));

    final ctorBody = [
      apiAvailability.runtimeCheck(
        ObjCBuiltInFunctions.checkOsVersion.gen(context),
        originalName,
      ),
      if (!generateAsStub) 'assert(isA(object\$));',
    ].nonNulls.join('\n    ');

    final rawObjType = PointerType(objCObjectType).getCType(context);
    final wrapObjType = ObjCBuiltInFunctions.objectBase.gen(context);
    final protos = [
      wrapObjType,
      ...[superType, ...protocols].nonNulls.map((p) => p.getDartType(context)),
    ];

    s.write('''
extension type $name._($wrapObjType object\$) implements ${protos.join(',')} {
  /// Constructs a [$name] that points to the same underlying object as [other].
  $name.as($wrapObjType other) : object\$ = other {
    $ctorBody
  }

  /// Constructs a [$name] that wraps the given raw object pointer.
  $name.fromPointer($rawObjType other,
      {bool retain = false, bool release = false}) :
          object\$ = $wrapObjType(other, retain: retain, release: release) {
    $ctorBody
  }

${generateAsStub ? '' : _generateStaticMethods(w)}
}

''');

    if (!generateAsStub) {
      s.write('''
extension $name\$Methods on $name {
${generateInstanceMethodBindings(w, this)}
}

''');
      if (generateSubclassHelpers) {
        s.write(_generateSubclassHelpers(w));
      }
    }

    return BindingString(
      type: BindingStringType.objcInterface,
      string: s.toString(),
    );
  }

  String _generateStaticMethods(Writer w) {
    final context = w.context;
    final wrapObjType = ObjCBuiltInFunctions.objectBase.gen(context);
    final s = StringBuffer();
    final isKindOfClass = _isKindOfClassMsgSend.invoke(
      context,
      'obj.ref.pointer',
      _isKindOfClass.name,
      [classObject.name],
    );

    s.write('''
  /// Returns whether [obj] is an instance of [$name].
  static bool isA($wrapObjType? obj) => obj == null 
      ? false 
      : $isKindOfClass;
''');

    s.write(generateStaticMethodBindings(w, this));

    final newMethod = methods
        .where(
          (ObjCMethod m) =>
              m.isClassMethod &&
              m.family == ObjCMethodFamily.new_ &&
              m.params.isEmpty &&
              m.originalName == 'new',
        )
        .firstOrNull;
    if (newMethod != null && originalName != 'NSString') {
      s.write('''
  /// Returns a new instance of $name constructed with the default `new` method.
  $name() : this.as(${newMethod.name}());
''');
    }

    return s.toString();
  }

  @override
  String getCType(Context context) =>
      PointerType(objCObjectType).getCType(context);

  @override
  String getDartType(Context context) =>
      isObjCImport ? '${context.libs.prefix(objcPkgImport)}.$name' : name;

  @override
  String getNativeType({String varName = ''}) => 'id $varName';

  @override
  String getObjCBlockSignatureType(Context context) => getDartType(context);

  @override
  bool get sameFfiDartAndCType => true;

  @override
  bool get sameDartAndCType => false;

  @override
  bool get sameDartAndFfiDartType => false;

  @override
  String convertDartTypeToFfiDartType(
    Context context,
    String value, {
    required bool objCRetain,
    required bool objCAutorelease,
  }) => ObjCInterface.generateGetId(value, objCRetain, objCAutorelease);

  static String generateGetId(
    String value,
    bool objCRetain,
    bool objCAutorelease,
  ) => objCRetain
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
  }) => ObjCInterface.generateConstructor(
    getDartType(context),
    value,
    objCRetain,
  );

  static String generateConstructor(
    String className,
    String value,
    bool objCRetain,
  ) {
    final ownershipFlags = 'retain: $objCRetain, release: true';
    return '$className.fromPointer($value, $ownershipFlags)';
  }

  @override
  String? generateRetain(String value) =>
      '(__bridge id)(__bridge_retained void*)($value)';

  @override
  void visit(Visitation visitation) => visitation.visitObjCInterface(this);

  // Set typeGraphOnly to true to skip iterating methods and other children, and
  // just iterate the DAG of interfaces, categories, and protocols. This is
  // useful for visitors that need to ensure super types are visited first.
  @override
  void visitChildren(Visitor visitor, {bool typeGraphOnly = false}) {
    if (!typeGraphOnly) {
      super.visitChildren(visitor);
      visitor.visit(classObject);
      visitor.visit(_isKindOfClass);
      visitor.visit(_isKindOfClassMsgSend);
      visitMethods(visitor);
      visitor.visit(objcPkgImport);

      // In the type DAG, categories link to their parent interface, not the
      // other way around. So don't iterate these categories as part of the DAG.
      visitor.visitAll(categories);
    }

    visitor.visit(superType);
    visitor.visitAll(protocols);

    // Note: Don't visit subtypes here, because they shouldn't affect transitive
    // inclusion. Including an interface shouldn't auto-include all its
    // subtypes, even as stubs.
  }

  @override
  bool isSupertypeOf(Type other) {
    other = other.typealiasType;
    if (other is ObjCInterface) {
      for (ObjCInterface? t = other; t != null; t = t.superType) {
        if (t == this) return true;
      }
    }
    return false;
  }

  @override
  String cacheKey() => 'ObjCInterface($usr)';
}

class ImportedObjCInterface extends ObjCInterface {
  final LibraryImport libraryImport;

  ImportedObjCInterface({
    required super.usr,
    required super.originalName,
    required super.context,
    required this.libraryImport,
    super.name,
    super.lookupName,
  }) : super(apiAvailability: ApiAvailability(externalVersions: null));

  @override
  bool get isObjCImport => true;

  @override
  String getDartType(Context context) =>
      '${context.libs.prefix(libraryImport)}.${symbol.oldName}';

  @override
  void visitChildren(Visitor visitor, {bool typeGraphOnly = false}) {
    visitor.visit(libraryImport);
    visitor.visit(superType);
    visitor.visitAll(protocols);
  }
}
