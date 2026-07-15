// Copyright (c) 2024, the Dart project authors. Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import '../code_generator.dart';

import 'ast.dart';

// Methods defined on NSObject that we don't want to copy to child objects,
// because they're unlikely to be used, and pollute the bindings. Note: Many of
// these are still accessible via inheritance from NSObject.
const _excludedNSObjectMethods = {
  'allocWithZone:',
  'autorelease',
  'class',
  'conformsToProtocol:',
  'copyWithZone:',
  'dealloc',
  'debugDescription',
  'description',
  'hash',
  'initialize',
  'instanceMethodForSelector:',
  'instanceMethodSignatureForSelector:',
  'instancesRespondToSelector:',
  'isSubclassOfClass:',
  'load',
  'mutableCopyWithZone:',
  'poseAsClass:',
  'release',
  'resolveClassMethod:',
  'resolveInstanceMethod:',
  'respondsToSelector:',
  'retain',
  'retainCount',
  'self',
  'setVersion:',
  'superclass',
  'version',
};

class CopyMethodsFromSuperTypesVisitation extends Visitation {
  @override
  void visitObjCInterface(ObjCInterface node) {
    node.visitChildren(visitor, typeGraphOnly: true);

    final isNSObject = ObjCBuiltInFunctions.isNSObject(node.originalName);

    // We need to copy certain methods from the super type:
    //  - Class methods, because Dart classes don't inherit static methods.
    //  - Methods that return instancetype, because the subclass's copy of the
    //    method needs to return the subclass, not the super class.
    //    Note: instancetype is only allowed as a return type, not an arg type.
    final superType = node.superType;
    if (superType != null) {
      for (final m in superType.methods) {
        if (isNSObject) {
          node.addMethod(m.copyForInheritance());
        } else if (m.isClassMethod &&
            !_excludedNSObjectMethods.contains(m.originalName)) {
          node.addMethod(m.copyForInheritance());
        } else if (ObjCBuiltInFunctions.isInstanceType(m.returnType)) {
          node.addMethod(m.copyForInheritance());
        }
      }
    }

    // Protocol extension methods are applicable to an interface extension type
    // that implements the protocol. Only copy the methods needed to resolve an
    // ambiguity between otherwise equally applicable extensions.
    _copyAmbiguousInheritedMethods(node);

    // Copy methods from all the categories that extend this interface, if those
    // methods return instancetype, because the Dart inheritance rules don't
    // match the ObjC rules regarding instancetype.
    // Also copy all methods from any anonymous categories.
    // NOTE: The methods are copied regardless of whether the category is
    // included by the config filters, since this method copying visit happens
    // before the filtering visit. This is technically a bug, but it's unlikely
    // to bother anyone, and the fix would be complicated. So we'll ignore it
    // for now.
    for (final category in node.categories) {
      for (final m in category.methods) {
        if (category.shouldCopyMethodToInterface(m)) {
          node.addMethod(m.copyForInheritance());
        }
      }
    }
  }

  void _copyMethodFromProtocols(
    Binding node,
    List<ObjCProtocol> protocols,
    void Function(ObjCMethod) addMethod,
  ) {
    // Copy all methods from all the protocols.
    for (final proto in protocols) {
      for (final m in proto.methods) {
        if (!_excludedNSObjectMethods.contains(m.originalName)) {
          addMethod(m.copyForInheritance());
        }
      }
    }
  }

  void _copyAmbiguousInheritedMethods(ObjCInterface node) {
    final providers = <_MethodProvider>[];
    final seenTypes = Set<BindingType>.identity();

    void addProvider(BindingType type, ObjCMethods methods) {
      if (seenTypes.add(type)) {
        providers.add(_MethodProvider(type, methods));
      }
    }

    void addProtocol(ObjCProtocol protocol) {
      addProvider(protocol, protocol);
      for (final superProtocol in protocol.superProtocols) {
        addProtocol(superProtocol);
      }
    }

    for (
      ObjCInterface? interface = node;
      interface != null;
      interface = interface.superType
    ) {
      addProvider(interface, interface);
      for (final protocol in interface.protocols) {
        addProtocol(protocol);
      }
    }

    // Dart extension methods make included protocol instance methods directly
    // available on conforming interfaces. Class methods are not inherited in
    // Dart, however, and a protocol emitted only as a stub has no extension
    // methods. Keep those methods on the interface itself.
    for (final provider in providers) {
      final protocol = provider.type;
      if (protocol is! ObjCProtocol) continue;
      for (final method in protocol.methods) {
        if (_excludedNSObjectMethods.contains(method.originalName)) continue;
        if (method.isClassMethod ||
            !_isGeneratedProtocolInstanceMethod(protocol, method)) {
          node.addMethod(method.copyForInheritance());
        }
      }
    }

    final candidatesByName = <String, List<_MethodCandidate>>{};
    for (final provider in providers) {
      for (final method in provider.methods.methods) {
        if (method.isClassMethod) continue;
        candidatesByName
            .putIfAbsent(method.symbol.oldName, () => [])
            .add(_MethodCandidate(provider.type, method));
      }
    }

    for (final candidates in candidatesByName.values) {
      final mostSpecific = candidates.where((candidate) {
        return !candidates.any(
          (other) =>
              !identical(candidate, other) &&
              _isStrictSubtype(other.type, candidate.type),
        );
      }).toList();
      final mostSpecificTypes = mostSpecific.map((e) => e.type).toSet();
      if (mostSpecificTypes.length < 2) continue;

      for (final candidate in mostSpecific) {
        node.addMethod(candidate.method.copyForInheritance());
      }
    }
  }

  bool _isStrictSubtype(BindingType left, BindingType right) =>
      left.isSubtypeOf(right) && !right.isSubtypeOf(left);

  bool _isGeneratedProtocolInstanceMethod(
    ObjCProtocol protocol,
    ObjCMethod method,
  ) {
    if (protocol.isObjCImport) return true;
    if (protocol.unavailable) return false;

    final protocols = visitor.context.config.objectiveC?.protocols;
    if (protocols == null) return false;
    final generatesProtocol =
        protocols.include(protocol) || protocols.includeTransitive;
    return generatesProtocol &&
        protocols.includeMember(protocol, method.originalName);
  }

  @override
  void visitObjCCategory(ObjCCategory node) {
    node.visitChildren(visitor, typeGraphOnly: true);

    // Copy all methods from all the category's protocols.
    _copyMethodFromProtocols(node, node.protocols, node.addMethod);
  }

  @override
  void visitObjCProtocol(ObjCProtocol node) {
    node.visitChildren(visitor, typeGraphOnly: true);

    for (final superProtocol in node.superProtocols) {
      if (ObjCBuiltInFunctions.isNSObject(superProtocol.originalName)) {
        // When writing a protocol that doesn't inherit from any other
        // protocols, it's typical to have it inherit from NSObject instead. But
        // NSObject has heaps of methods that users are very unlikely to want to
        // implement, so ignore it. If the user really wants to implement them
        // they can use the ObjCProtocolBuilder.
        continue;
      }

      // Protocol adapters have to implement inherited requirements too, so
      // keep these methods directly on the child protocol binding.
      for (final method in superProtocol.methods) {
        node.addMethod(method.copyForInheritance());
      }
    }
  }
}

class _MethodProvider {
  final BindingType type;
  final ObjCMethods methods;

  _MethodProvider(this.type, this.methods);
}

class _MethodCandidate {
  final BindingType type;
  final ObjCMethod method;

  _MethodCandidate(this.type, this.method);
}
