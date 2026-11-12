//===--- SpirvGraph.h - SPV_ARM_graph region --------------------*- C++ -*-===//
//
//                     The LLVM Compiler Infrastructure
//
// This file is distributed under the University of Illinois Open Source
// License. See LICENSE.TXT for details.
//
//===----------------------------------------------------------------------===//
//
// HLSL Change - SPV_ARM_graph. This file describes the one module-scope object
// SPV_ARM_graph adds to a module that is not an instruction of a function: the
// graph region
//
//   OpGraphEntryPointARM %graph "<name>" %in0 %out0
//   %graph = OpGraphARM %graphtype
//   %v0 = OpGraphInputARM %tensor %uint_0      // the graph inputs
//   %r0 = OpExtInst %tensor %set <op> %v0 ...   // the graph body
//   OpGraphSetOutputARM %r0 %uint_0            // the graph outputs
//   OpGraphEndARM
//
// which SPIR-V's logical layout puts in the last module section, after every
// function (SPIRV-Tools: kLayoutGraphDefinitions, see
// InstructionLayoutSection in validation_state.cpp). It therefore cannot be
// carried by any SpirvInstruction of a SpirvBasicBlock, and lives here as a
// module-level object instead; EmitVisitor::emitGraph writes it, and
// SpirvBuilder owns it (beginGraph/endGraph).
//
// The instruction order above is not a convention: SPIRV-Tools' graph region
// state machine accepts OpGraphInputARM only while the region is in its "begin"
// or "inputs" state, OpGraphSetOutputARM only from "begin"/"inputs"/"body"/
// "outputs", and OpGraphEndARM only from "outputs", so the five groups of
// instructions can appear in exactly that order and nothing else. The body
// instructions themselves may only be extended instructions (and
// OpCompositeExtract) - every other opcode is rejected with
// "Op... cannot appear in the graph definitions section" - which is why the
// body of a graph is a list of OpExtInst and nothing else.
//
//===----------------------------------------------------------------------===//

#ifndef LLVM_CLANG_SPIRV_SPIRVGRAPH_H
#define LLVM_CLANG_SPIRV_SPIRVGRAPH_H

#include "llvm/ADT/SmallVector.h"
#include <string>
#include <utility>

namespace clang {
namespace spirv {

class SpirvInstruction;
class SpirvType;
class SpirvVariable;

/// A graph input: the instruction that reads the input (an
/// OpGraphInputARM-shaped SpirvIntrinsicInstruction, which is never emitted as
/// part of a function) and the input index it reads.
class SpirvGraphInputARM {
public:
  SpirvGraphInputARM(SpirvInstruction *value_, uint32_t index_)
      : value(value_), index(index_) {}
  SpirvInstruction *getValue() const { return value; }
  /// The index into the graph's input list, which is also the operand order of
  /// OpTypeGraphARM. The builder requires the inputs to be declared in index
  /// order starting from 0, so this is also the position in the list.
  uint32_t getIndex() const { return index; }

private:
  SpirvInstruction *value;
  uint32_t index;
};

/// A graph output: the value written to an output and the output index.
class SpirvGraphOutputARM {
public:
  SpirvGraphOutputARM(SpirvInstruction *value_, uint32_t index_)
      : value(value_), index(index_) {}
  SpirvInstruction *getValue() const { return value; }
  uint32_t getIndex() const { return index; }

private:
  SpirvInstruction *value;
  uint32_t index;
};

/// The graph region of a module (SPV_ARM_graph, OpCapability GraphARM).
///
/// One module has at most one graph: OpGraphEntryPointARM names one graph, and
/// this landing declares one graph per shader. Every field is filled in while
/// the shader's entry point is emitted - the graph *type* last, because the
/// number of inputs and the input and output types are only known once the
/// whole declaration has been seen.
class SpirvGraphARM {
public:
  explicit SpirvGraphARM(llvm::StringRef name)
      : graphId(0), graphType(nullptr),
        entryPointName(name.begin(), name.end()) {}

  /// The <id> of OpGraphARM. Assigned by EmitVisitor, which owns result-id
  /// allocation.
  uint32_t getGraphId() const { return graphId; }
  void setGraphId(uint32_t id) { graphId = id; }

  /// The name OpGraphEntryPointARM gives the graph, which is the name of the
  /// shader entry point that declared it.
  llvm::StringRef getEntryPointName() const { return entryPointName; }

  /// OpTypeGraphARM: NumInputs <in types...> <out types...>. Built by
  /// SpirvBuilder::endGraph once every input and output type is known.
  const SpirvType *getGraphType() const { return graphType; }
  void setGraphType(const SpirvType *type) { graphType = type; }

  /// The UniformConstant interface variables OpGraphEntryPointARM names, in
  /// graph type order: one per input followed by one per output. SPIRV-Tools
  /// requires each of them to be an OpVariable in UniformConstant storage whose
  /// pointee type is the graph type's I/O type at the same position.
  void addInterface(SpirvVariable *var) { interfaces.push_back(var); }
  llvm::ArrayRef<SpirvVariable *> getInterfaces() const { return interfaces; }

  void addInput(SpirvInstruction *value, uint32_t index) {
    inputs.push_back(SpirvGraphInputARM(value, index));
  }
  llvm::ArrayRef<SpirvGraphInputARM> getInputs() const { return inputs; }

  /// Appends an operation to the graph body. Only extended instructions are
  /// accepted; see SpirvBuilder::createSpirvIntrInstExt.
  void addBodyInstruction(SpirvInstruction *inst) { body.push_back(inst); }
  llvm::ArrayRef<SpirvInstruction *> getBody() const { return body; }

  void addOutput(SpirvInstruction *value, uint32_t index) {
    outputs.push_back(SpirvGraphOutputARM(value, index));
  }
  llvm::ArrayRef<SpirvGraphOutputARM> getOutputs() const { return outputs; }

  /// The number of inputs the graph type declares, which is also the number of
  /// inputs OpGraphInputARM may read.
  uint32_t getNumInputs() const { return inputs.size(); }
  uint32_t getNumOutputs() const { return outputs.size(); }

private:
  uint32_t graphId;
  const SpirvType *graphType;
  std::string entryPointName;
  llvm::SmallVector<SpirvVariable *, 4> interfaces;
  llvm::SmallVector<SpirvGraphInputARM, 4> inputs;
  llvm::SmallVector<SpirvInstruction *, 8> body;
  llvm::SmallVector<SpirvGraphOutputARM, 2> outputs;
};

} // end namespace spirv
} // end namespace clang

#endif // LLVM_CLANG_SPIRV_SPIRVGRAPH_H
