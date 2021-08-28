// This file defines a class to represent a SPIR-V module.

import 'dart:collection';
import 'dart:typed_data';

import 'instruction.dart';
import 'instructions.dart';

final _magicNumber = 0x07230203;
final _version = 0x00010500;

/// Module builds a complete unit of SPIR-V from
/// an Instruction representing fragment color for a shader.
///
class Module extends Identifier {
  // fragment position
  static final position = OpFunctionParameter(vec2T);

  final _ids = <Instruction, int>{};
  final _constants = <Instruction>{};
  final _uniforms = <OpVariable>[];

  int _bound = 0;
  Instruction _color;

  @override
  int identify(Instruction inst) {
    if (_ids.containsKey(inst)) {
      return _ids[inst];
    }

    if (inst.constant != null) {
      final constant = _constants.singleWhere(
        (c) => c.constant == inst.constant,
        orElse: () => null,
      );
      if (constant != null) {
        return _ids[constant];
      }
      _constants.add(inst);
    }

    int id = ++_bound;
    _ids[inst] = id;
    return id;
  }

  // main must be assiged before calling [encode].
  set color(Instruction vec4) {
    assert(vec4.type == vec4T);
    _color = vec4;
  }

  List<double> packUniformValues() {
    int size = 0;
    for (final uniform in _uniforms) {
      size += uniform.variable.length;
    }
    int i = 0;
    List<double> values = List<double>(size);
    for (final uniform in _uniforms) {
      for (int ui = 0; ui < uniform.variable.length; ui++) {
        values[i] = uniform.variable[ui];
        i++;
      }
    }
    return values;
  }

  // Encode the module to binary SPIR-V.
  ByteBuffer encode() {
    _ids.clear();

    final main = ShaderFunction()..resolve(this);

    final instructions = <Instruction>[
      // capabilities
      OpCapability.matrix,
      OpCapability.shader,

      // extension instruction imports
      OpExtInstImport.glsl,

      // memory model
      OpMemoryModel.glsl,

      // decorations
      OpDecorate.export(
        name: 'main',
        target: main,
      ),
    ];

    // get main definition, and identify all dependent instructions.
    _color.resolve(this);

    // insert all instruction/id pairs into a sorted map
    final sortedMap = SplayTreeMap.fromIterables(
      _ids.values, // ids as keys
      _ids.keys, // instructions as values
    );

    // add type declarations
    instructions.addAll(sortedMap.values.where((i) => i.isType));

    // add variable declarations
    instructions.addAll(sortedMap.values.where((i) => i.isDeclaration));

    // collect uniforms
    _uniforms.addAll(sortedMap.values
        .where((i) => i is OpVariable)
        .map((i) => i as OpVariable));

    // add function declaration opening
    instructions.addAll([
      main,
      position,
      OpLabel(),
    ]);

    // add block
    instructions
        .addAll(sortedMap.values.where((i) => !instructions.contains(i)));

    // complete function declaration
    instructions.addAll([
      OpReturnValue(_color),
      OpFunctionEnd(),
    ]);

    final words = <int>[
      _magicNumber,
      _version,
      0, // generator's magic number
      0, // bound
      0, // reserved.
    ];

    for (final instruction in instructions) {
      words.addAll(instruction.encode(this));
    }

    words[3] = _bound + 1;

    return Int32List.fromList(words).buffer;
  }
}
