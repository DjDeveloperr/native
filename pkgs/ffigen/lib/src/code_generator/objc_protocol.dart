// Copyright (c) 2024, the Dart project authors. Please see the AUTHORS file
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

class ObjCProtocol extends BindingType with ObjCMethods, HasLocalScope {
  @override
  final Context context;
  final superProtocols = <ObjCProtocol>[];
  final String lookupName;
  final ObjCInternalGlobal _protocolPointer;
  late final ObjCInternalGlobal _conformsTo;
  late final ObjCMsgSendFunc _conformsToMsgSend;
  final ApiAvailability apiAvailability;

  // Filled by ListBindingsVisitation.
  bool generateAsStub = false;

  ObjCProtocol({
    super.usr,
    required String super.originalName,
    String? name,
    String? lookupName,
    super.dartDoc,
    required this.apiAvailability,
    required this.context,
  }) : lookupName = lookupName ?? originalName,
       _protocolPointer = ObjCInternalGlobal(
         '_protocol_$originalName',
         () =>
             '${ObjCBuiltInFunctions.getProtocol.gen(context)}("$lookupName")',
       ),
       super(
         name:
             context.objCBuiltInFunctions.getBuiltInProtocolName(
               originalName,
             ) ??
             name ??
             originalName,
       ) {
    _conformsTo = context.objCBuiltInFunctions.getSelObject(
      'conformsToProtocol:',
    );
    _conformsToMsgSend = context.objCBuiltInFunctions
        .getMsgSendFunc(BooleanType(), [
          Parameter(
            name: 'protocol',
            type: PointerType(objCProtocolType),
            objCConsumed: false,
          ),
        ]);
  }

  @override
  bool get isObjCImport =>
      context.objCBuiltInFunctions.getBuiltInProtocolName(originalName) != null;

  bool get unavailable => apiAvailability.availability == Availability.none;

  bool _isAvailableInProtocolAdapter(ObjCMethod method) =>
      method.apiAvailability.availability != Availability.none;

  String _convertedReturnType(ObjCMethod method, String targetType) {
    if (method.returnType is ObjCInstanceType) return targetType;
    final baseType = method.returnType.typealiasType;
    if (baseType is ObjCNullable && baseType.child is ObjCInstanceType) {
      return '$targetType?';
    }
    return method.returnType.getDartType(context);
  }

  String _protocolPropertyName(ObjCMethod method) =>
      stripGeneratedNameSuffix(method.symbol.name);

  String _joinProtocolParamStr(List<Parameter> params) {
    if (params.isEmpty) return '';
    String paramToStr(Parameter p) =>
        '${p.type.getDartType(context)} ${p.name}';
    String paramToNamed(Parameter p) =>
        '${p.isNullable ? '' : 'required '}${paramToStr(p)}';
    if (params.length == 1) return paramToStr(params.first);
    final named = params.sublist(1).map(paramToNamed).join(',');
    return '${paramToStr(params.first)}, {$named}';
  }

  String _protocolInterfaceMethodName(ObjCMethod method) {
    final methodName = switch (method.kind) {
      ObjCMethodKind.propertyGetter ||
      ObjCMethodKind.propertySetter => _protocolPropertyName(method),
      ObjCMethodKind.method => method.symbol.name,
    };
    final upperName = methodName[0].toUpperCase() + methodName.substring(1);
    return switch (method.kind) {
      ObjCMethodKind.method => methodName,
      ObjCMethodKind.propertyGetter when method.isClassMethod =>
        'get$upperName',
      ObjCMethodKind.propertyGetter => methodName,
      ObjCMethodKind.propertySetter when method.isClassMethod =>
        'set$upperName',
      ObjCMethodKind.propertySetter => methodName,
    };
  }

  String _protocolInterfaceDeclaration(ObjCMethod method, String targetType) {
    final returnTypeStr = _convertedReturnType(method, targetType);
    final params = method.returnsNSErrorByOutParam
        ? method.params.toList().sublist(0, method.params.length - 1)
        : method.params.toList();
    final paramStr = _joinProtocolParamStr(params);
    final methodName = _protocolInterfaceMethodName(method);

    return switch (method.kind) {
      ObjCMethodKind.method => '$returnTypeStr $methodName($paramStr);',
      ObjCMethodKind.propertyGetter when method.isClassMethod =>
        '$returnTypeStr $methodName($paramStr);',
      ObjCMethodKind.propertyGetter => '$returnTypeStr get $methodName;',
      ObjCMethodKind.propertySetter when method.isClassMethod =>
        '$returnTypeStr $methodName($paramStr);',
      ObjCMethodKind.propertySetter => 'set $methodName($paramStr);',
    };
  }

  String _protocolInvocationArgumentList(ObjCMethod method) {
    final params = method.returnsNSErrorByOutParam
        ? method.params.toList().sublist(0, method.params.length - 1)
        : method.params.toList();
    if (params.isEmpty) return '';
    if (params.length == 1) return params.first.name;

    final positional = params.first.name;
    final named = params.skip(1).map((p) => '${p.name}: ${p.name}').join(', ');
    return '$positional, $named';
  }

  String _protocolImplementationInvocation(
    ObjCMethod method,
    String implementationVar,
  ) {
    final methodName = _protocolInterfaceMethodName(method);
    final args = _protocolInvocationArgumentList(method);

    return switch (method.kind) {
      ObjCMethodKind.method => '$implementationVar.$methodName($args)',
      ObjCMethodKind.propertyGetter when method.isClassMethod =>
        '$implementationVar.$methodName($args)',
      ObjCMethodKind.propertyGetter => '$implementationVar.$methodName',
      ObjCMethodKind.propertySetter when method.isClassMethod =>
        '$implementationVar.$methodName($args)',
      ObjCMethodKind.propertySetter => '$implementationVar.$methodName = $args',
    };
  }

  String _protocolAdapterClosure(ObjCMethod method, String implementationVar) {
    final closureParams = method.params
        .map((p) => '${p.type.getDartType(context)} ${p.name}')
        .join(', ');
    final invocation = _protocolImplementationInvocation(
      method,
      implementationVar,
    );

    if (method.returnType == voidType) {
      return '($closureParams) { $invocation; }';
    }
    return '($closureParams) => $invocation';
  }

  static String _trampolineAddress(Writer w, ObjCBlock block) {
    return block.protocolTrampolineAccessor(w.context);
  }

  @override
  BindingString toBindingString(Writer w) {
    final protocolClass = ObjCBuiltInFunctions.protocolClass.gen(context);
    final protocolBase = ObjCBuiltInFunctions.protocolBase.gen(context);
    final protocolMethod = ObjCBuiltInFunctions.protocolMethod.gen(context);
    final protocolListenableMethod = ObjCBuiltInFunctions
        .protocolListenableMethod
        .gen(context);
    final protocolBuilder = ObjCBuiltInFunctions.protocolBuilder.gen(context);
    final objectBase = ObjCBuiltInFunctions.objectBase.gen(context);
    final rawObjType = PointerType(objCObjectType).getCType(context);
    final getSignature = ObjCBuiltInFunctions.getProtocolMethodSignature.gen(
      context,
    );
    final specClass = '${name}Spec';
    final optionalClass = '${name}Optional';
    final defaultsMixin = '${name}Defaults';
    final adapterMixin = '${name}Adapter';

    final s = StringBuffer();
    s.write('\n');
    if (generateAsStub) {
      s.write('''
/// WARNING: $name is a stub. To generate bindings for this class, include
/// $originalName in your config's objc-protocols list.
///
''');
    }
    s.write(makeDartDoc(dartDoc));

    final sp = [
      protocolBase,
      ...superProtocols.map((p) => p.getDartType(context)),
    ];
    s.write('''
extension type $name._($protocolBase object\$) implements ${sp.join(', ')} {
  /// Constructs a [$name] that points to the same underlying object as [other].
  $name.as($objectBase other) : object\$ = other;

  /// Constructs a [$name] that wraps the given raw object pointer.
  $name.fromPointer($rawObjType other,
      {bool retain = false, bool release = false}) :
      object\$ = $protocolBase(other, retain: retain, release: release);
''');

    if (!generateAsStub) {
      final msgSendInvoke = _conformsToMsgSend.invoke(
        context,
        'obj.ref.pointer',
        _conformsTo.name,
        [_protocolPointer.name],
      );

      s.write('''

  /// Returns whether [obj] is an instance of [$name].
  static bool conformsTo($objectBase obj) {
    return $msgSendInvoke;
  }
''');
    }

    s.write('''
}

''');

    if (!generateAsStub) {
      s.write('''
extension $name\$Methods on $name {
${generateInstanceMethodBindings(w, this)}
}

''');
    }

    if (!generateAsStub) {
      final builder = '$name\$Builder';
      final targetType = getDartType(context);
      final requiredDeclarations = StringBuffer();
      final optionalDeclarations = StringBuffer();
      final adapterGetters = StringBuffer();
      final requiredMethods = methods
          .where((method) => !method.isOptional)
          .toList();
      final optionalMethods = methods
          .where((method) => method.isOptional)
          .toList();
      final availableRequiredMethods = requiredMethods
          .where(_isAvailableInProtocolAdapter)
          .toList();
      final availableOptionalMethods = optionalMethods
          .where(_isAvailableInProtocolAdapter)
          .toList();

      for (final method in availableRequiredMethods) {
        requiredDeclarations.write(makeDartDoc(method.dartDoc));
        requiredDeclarations.write(
          '  ${_protocolInterfaceDeclaration(method, targetType)}\n',
        );
      }
      for (final method in availableOptionalMethods) {
        optionalDeclarations.write(makeDartDoc(method.dartDoc));
        optionalDeclarations.write(
          '  ${_protocolInterfaceDeclaration(method, targetType)}\n',
        );
      }

      s.write('''
abstract interface class $specClass {
${requiredDeclarations.toString()}
}

abstract interface class $optionalClass {
${optionalDeclarations.toString()}
}

''');
      if (availableOptionalMethods.isNotEmpty) {
        s.write('''
mixin $defaultsMixin implements $optionalClass {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

''');
      }

      s.write('''
  interface class $builder {
  ''');

      final buildArgs = <String>[];
      final buildImplementations = StringBuffer();
      final buildListenerImplementations = StringBuffer();
      final buildBlockingImplementations = StringBuffer();
      final buildFromImplementations = StringBuffer();
      final buildFromListenerImplementations = StringBuffer();
      final buildFromBlockingImplementations = StringBuffer();
      final methodFields = StringBuffer();

      var anyListeners = false;
      final hasOptionalMethods = availableOptionalMethods.isNotEmpty;
      for (final method in methods) {
        final methodName = method.protocolMethodName!.name;
        final fieldName = methodName;
        final argName = methodName;
        final block = method.protocolBlock!;
        block.fillProtocolTrampoline();
        final blockUtils = block.helperClassRef(context);
        final methodClass = block.hasListener
            ? protocolListenableMethod
            : protocolMethod;

        // The function type omits the first arg of the block, which is unused.
        final func = FunctionType(
          returnType: block.returnType,
          parameters: [...block.params.skip(1)],
        );
        final funcType = func.getDartType(context, writeArgumentNames: false);

        if (method.isOptional) {
          buildArgs.add('$funcType? $argName');
        } else {
          buildArgs.add('required $funcType $argName');
        }

        final blockFirstArg = block.params[0].type.getDartType(context);
        final argsReceived = func.parameters
            .map((p) => '${p.type.getDartType(context)} ${p.name}')
            .join(', ');
        final argsPassed = func.parameters.map((p) => p.name).join(', ');
        final wrapper =
            '($blockFirstArg _, $argsReceived) => func($argsPassed)';

        var listenerBuilders = '';
        var maybeImplementAsListener = 'implement';
        var maybeImplementAsBlocking = 'implement';
        if (block.hasListener) {
          listenerBuilders =
              '''
    ($funcType func) => $blockUtils.listener($wrapper),
    ($funcType func) => $blockUtils.blocking($wrapper),
''';
          maybeImplementAsListener = 'implementAsListener';
          maybeImplementAsBlocking = 'implementAsBlocking';
          anyListeners = true;
        }

        buildImplementations.write('''
    $builder.$fieldName.implement(builder, $argName);''');
        buildListenerImplementations.write('''
    $builder.$fieldName.$maybeImplementAsListener(builder, $argName);''');
        buildBlockingImplementations.write('''
    $builder.$fieldName.$maybeImplementAsBlocking(builder, $argName);''');
        if (_isAvailableInProtocolAdapter(method)) {
          final implementationVar = method.isOptional
              ? 'optionalImplementation'
              : 'implementation';
          final adapterClosure = _protocolAdapterClosure(
            method,
            implementationVar,
          );
          final adapterExpr = method.isOptional
              ? '$builder.$fieldName.isAvailable && '
                    'optionalImplementation != null ? $adapterClosure : null'
              : adapterClosure;
          buildFromImplementations.write('''
      $argName: $adapterExpr,''');
          buildFromListenerImplementations.write('''
      $argName: $adapterExpr,''');
          buildFromBlockingImplementations.write('''
      $argName: $adapterExpr,''');
        }

        methodFields.write(makeDartDoc(method.dartDoc));
        methodFields.write('''static final $fieldName = $methodClass<$funcType>(
      ${_protocolPointer.name},
      ${method.selObject.name},
      ${_trampolineAddress(w, block)},
      $getSignature(
          ${_protocolPointer.name},
          ${method.selObject.name},
          isRequired: ${method.isRequired},
          isInstanceMethod: ${method.isInstanceMethod},
      ),
      ($funcType func) => $blockUtils.fromFunction($wrapper),
      $listenerBuilders
    );
''');
      }

      buildArgs.add('bool \$keepIsolateAlive = true');
      final args = '{${buildArgs.join(', ')}}';
      final builders =
          '''
  /// Returns the [$protocolClass] object for this protocol.
  static $protocolClass get \$protocol =>
      $protocolClass.fromPointer(${_protocolPointer.name}.cast());

  /// Builds an object that implements the $originalName protocol. To implement
  /// multiple protocols, use [addToBuilder] or [$protocolBuilder] directly.
  ///
  /// If `\$keepIsolateAlive` is true, this protocol will keep this isolate
  /// alive until it is garbage collected by both Dart and ObjC.
  static $name implement($args) {
    final builder = $protocolBuilder(debugName: '$originalName');
    $buildImplementations
    builder.addProtocol(\$protocol);
    return $name.as(builder.build(keepIsolateAlive: \$keepIsolateAlive));
  }

  /// Adds the implementation of the $originalName protocol to an existing
  /// [$protocolBuilder].
  ///
  /// Note: You cannot call this method after you have called `builder.build`.
  static void addToBuilder($protocolBuilder builder, $args) {
    $buildImplementations
    builder.addProtocol(\$protocol);
  }
''';

      final optionalImplementationDecl = hasOptionalMethods
          ? '''
    final $optionalClass? optionalImplementation =
        implementation is $optionalClass
            ? implementation as $optionalClass
            : null;
'''
          : '';

      var listenerBuilders = '';
      if (anyListeners) {
        listenerBuilders =
            '''
  /// Builds an object that implements the $originalName protocol. To implement
  /// multiple protocols, use [addToBuilder] or [$protocolBuilder] directly. All
  /// methods that can be implemented as listeners will be.
  ///
  /// If `\$keepIsolateAlive` is true, this protocol will keep this isolate
  /// alive until it is garbage collected by both Dart and ObjC.
  static $name implementAsListener($args) {
    final builder = $protocolBuilder(debugName: '$originalName');
    $buildListenerImplementations
    builder.addProtocol(\$protocol);
    return $name.as(builder.build(keepIsolateAlive: \$keepIsolateAlive));
  }

  /// Adds the implementation of the $originalName protocol to an existing
  /// [$protocolBuilder]. All methods that can be implemented as listeners will
  /// be.
  ///
  /// Note: You cannot call this method after you have called `builder.build`.
  static void addToBuilderAsListener($protocolBuilder builder, $args) {
    $buildListenerImplementations
    builder.addProtocol(\$protocol);
  }

  /// Builds an object that implements the $originalName protocol. To implement
  /// multiple protocols, use [addToBuilder] or [$protocolBuilder] directly. All
  /// methods that can be implemented as blocking listeners will be.
  ///
  /// If `\$keepIsolateAlive` is true, this protocol will keep this isolate
  /// alive until it is garbage collected by both Dart and ObjC.
  static $name implementAsBlocking($args) {
    final builder = $protocolBuilder(debugName: '$originalName');
    $buildBlockingImplementations
    builder.addProtocol(\$protocol);
    return $name.as(builder.build(keepIsolateAlive: \$keepIsolateAlive));
  }

  /// Adds the implementation of the $originalName protocol to an existing
  /// [$protocolBuilder]. All methods that can be implemented as blocking
  /// listeners will be.
  ///
  /// Note: You cannot call this method after you have called `builder.build`.
  static void addToBuilderAsBlocking($protocolBuilder builder, $args) {
    $buildBlockingImplementations
    builder.addProtocol(\$protocol);
  }

  /// Builds an object that implements the $originalName protocol using members
  /// from [implementation]. Methods that support listener implementations will
  /// use them.
  static $name implementFromAsListener(
    $specClass implementation, {
    bool \$keepIsolateAlive = true,
  }) {
$optionalImplementationDecl    return implementAsListener(
$buildFromListenerImplementations
      \$keepIsolateAlive: \$keepIsolateAlive,
    );
  }

  /// Adds an implementation of the $originalName protocol to an existing
  /// [$protocolBuilder] using members from [implementation]. Methods that
  /// support listener implementations will use them.
  static void addToBuilderFromAsListener(
    $protocolBuilder builder,
    $specClass implementation,
  ) {
$optionalImplementationDecl    addToBuilderAsListener(
      builder,
$buildFromListenerImplementations    );
  }

  /// Builds an object that implements the $originalName protocol using members
  /// from [implementation]. Methods that support blocking listener
  /// implementations will use them.
  static $name implementFromAsBlocking(
    $specClass implementation, {
    bool \$keepIsolateAlive = true,
  }) {
$optionalImplementationDecl    return implementAsBlocking(
$buildFromBlockingImplementations
      \$keepIsolateAlive: \$keepIsolateAlive,
    );
  }

  /// Adds an implementation of the $originalName protocol to an existing
  /// [$protocolBuilder] using members from [implementation]. Methods that
  /// support blocking listener implementations will use them.
  static void addToBuilderFromAsBlocking(
    $protocolBuilder builder,
    $specClass implementation,
  ) {
$optionalImplementationDecl    addToBuilderAsBlocking(
      builder,
$buildFromBlockingImplementations    );
  }
''';
      }

      final implementFromBuilders =
          '''
  /// Builds an object that implements the $originalName protocol using members
  /// from [implementation].
  ///
  /// Optional methods are only implemented when [implementation] also
  /// implements [$optionalClass].
  static $name implementFrom(
    $specClass implementation, {
    bool \$keepIsolateAlive = true,
  }) {
$optionalImplementationDecl    return implement(
$buildFromImplementations
      \$keepIsolateAlive: \$keepIsolateAlive,
    );
  }

  /// Adds an implementation of the $originalName protocol to an existing
  /// [$protocolBuilder] using members from [implementation].
  static void addToBuilderFrom(
    $protocolBuilder builder,
    $specClass implementation,
  ) {
$optionalImplementationDecl    addToBuilder(
      builder,
$buildFromImplementations    );
  }
''';

      s.write('''

  $builders
  $implementFromBuilders
  $listenerBuilders
  $methodFields
}
''');

      adapterGetters.write('''
mixin $adapterMixin {
  /// Lazily creates a native adapter for this Dart implementation.
  late final $name as$name = $builder.implementFrom(this as $specClass);
''');
      if (anyListeners) {
        adapterGetters.write('''

  /// Lazily creates a listener-backed native adapter for this Dart
  /// implementation.
  late final $name as${name}Listener =
      $builder.implementFromAsListener(this as $specClass);

  /// Lazily creates a blocking-listener-backed native adapter for this Dart
  /// implementation.
  late final $name as${name}Blocking =
      $builder.implementFromAsBlocking(this as $specClass);
''');
      }
      adapterGetters.write('''
}

''');
      s.write(adapterGetters.toString());
    }

    return BindingString(
      type: BindingStringType.objcProtocol,
      string: s.toString(),
    );
  }

  @override
  BindingString? toObjCBindingString(Writer w) => null;

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

  @override
  String? generateRetain(String value) =>
      '(__bridge id)(__bridge_retained void*)($value)';

  bool _isSuperProtocolOf(ObjCProtocol protocol) {
    if (protocol == this) return true;
    for (final superProtocol in protocol.superProtocols) {
      if (_isSuperProtocolOf(superProtocol)) return true;
    }
    return false;
  }

  @override
  bool isSupertypeOf(Type other) {
    other = other.typealiasType;
    if (other is ObjCProtocol) {
      return _isSuperProtocolOf(other);
    } else if (other is ObjCInterface) {
      for (ObjCInterface? t = other; t != null; t = t.superType) {
        for (final protocol in t.protocols) {
          if (_isSuperProtocolOf(protocol)) return true;
        }
      }
    }
    return false;
  }

  @override
  String toString() => originalName;

  @override
  void visit(Visitation visitation) => visitation.visitObjCProtocol(this);

  // Set typeGraphOnly to true to skip iterating methods and other children, and
  // just iterate the DAG of interfaces, categories, and protocols. This is
  // useful for visitors that need to ensure super types are visited first.
  @override
  void visitChildren(Visitor visitor, {bool typeGraphOnly = false}) {
    if (!typeGraphOnly) {
      super.visitChildren(visitor);
      visitor.visit(_protocolPointer);
      visitor.visit(_conformsTo);
      visitor.visit(_conformsToMsgSend);
      visitMethods(visitor);
      visitor.visit(ffiImport);
      visitor.visit(objcPkgImport);
    }
    visitor.visitAll(superProtocols);
  }

  @override
  String cacheKey() => 'ObjCProtocol($usr)';
}

class ImportedObjCProtocol extends ObjCProtocol {
  final LibraryImport libraryImport;

  ImportedObjCProtocol({
    required super.usr,
    required super.originalName,
    required super.context,
    required this.libraryImport,
    String? name,
    String? lookupName,
  }) : super(
         name: name,
         lookupName: lookupName,
         apiAvailability: ApiAvailability(externalVersions: null),
       );

  @override
  bool get isObjCImport => true;

  @override
  String getDartType(Context context) =>
      '${context.libs.prefix(libraryImport)}.${symbol.oldName}';

  @override
  void visitChildren(Visitor visitor, {bool typeGraphOnly = false}) {
    visitor.visit(libraryImport);
    visitor.visitAll(superProtocols);
  }
}
