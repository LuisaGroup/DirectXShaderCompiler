=====================================
HLSL to SPIR-V Feature Mapping Manual
=====================================

.. contents::
   :local:
   :depth: 3

Introduction
============

This document describes the mappings from HLSL features to SPIR-V for Vulkan
adopted by the SPIR-V codegen. For how to build, use, or contribute to the
SPIR-V codegen and its internals, please see the
`wiki <https://github.com/Microsoft/DirectXShaderCompiler/wiki/SPIR%E2%80%90V-CodeGen>`_
page.

`SPIR-V <https://www.khronos.org/registry/spir-v/>`_ is a binary intermediate
language for representing graphical-shader stages and compute kernels for
multiple Khronos APIs, such as Vulkan, OpenGL, and OpenCL. At the moment we
only intend to support the Vulkan flavor of SPIR-V.

DirectXShaderCompiler is the reference compiler for HLSL. Adding SPIR-V codegen
in DirectXShaderCompiler will enable the usage of HLSL as a frontend language
for Vulkan shader programming. Sharing the same code base also means we can
track the evolution of HLSL more closely and always deliver the best of HLSL to
developers. Moreover, developers will also have a unified compiler toolchain for
targeting both DirectX and Vulkan. We believe this effort will benefit the
general graphics ecosystem.

Note that this document is expected to be an ongoing effort and grow as we
implement more and more HLSL features.

Overview
========

Although they share the same basic concepts, DirectX and Vulkan are still
different graphics APIs with semantic gaps. HLSL is the native shading language
for DirectX, so certain HLSL features do not have corresponding mappings in
Vulkan, and certain Vulkan specific information does not have native ways to
express in HLSL source code. This section describes the general translation
paradigms and how we close some of the major semantic gaps.

Note that the term "semantic" is overloaded. In HLSL, it can mean the string
attached to shader input or output. For such cases, we refer it as "HLSL
semantic" or "semantic string". For other cases, we just use the normal
"semantic" term.

Shader entry function
---------------------

HLSL entry functions can read data from the previous shader stage and write
data to the next shader stage via function parameters and return value. On the
contrary, Vulkan requires all SPIR-V entry functions taking no parameters and
returning void. All data passing between stages should use global variables
in the ``Input`` and ``Output`` storage class.

To handle this difference, we emit a wrapper function as the SPIR-V entry
function around the HLSL source code entry function. The wrapper function is
responsible to read data from SPIR-V ``Input`` global variables and prepare
them to the types required in the source code entry function signature, call
the source code entry function, and then decompose the contents in return value
(and ``out``/``inout`` parameters) to the types required by the SPIR-V
``Output`` global variables, and then write out. For details about the wrapper
function, please refer to the `entry function wrapper`_ section.

Shader stage IO interface matching
----------------------------------

HLSL leverages semantic strings to link variables and pass data between shader
stages. Great flexibility is allowed as for how to use the semantic strings.
They can appear on function parameters, function returns, and struct members.
In Vulkan, linking variables and passing data between shader stages is done via
numeric ``Location`` decorations on SPIR-V global variables in the ``Input`` and
``Output`` storage class.

To help handling such differences, we provide `Vulkan specific attributes`_ to
let the developer to express precisely their intents. The compiler will also try
its best to deduce the mapping from semantic strings to SPIR-V ``Location``
numbers when such explicit Vulkan specific attributes are absent. Please see the
`HLSL semantic and Vulkan Location`_ section for more details about the mapping
and ``Location`` assignment.

What makes the story complicated is Vulkan's strict requirements on interface
matching. Basically, a variable in the previous stage is considered a match to
a variable in the next stage if and only if they are decorated with the same
``Location`` number and with the exact same type, except for the outermost
arrayness in hull/domain/geometry shader, which can be ignored regarding
interface matching. This is causing problems together with the flexibility of
HLSL semantic strings.

Some HLSL system-value (SV) semantic strings will be mapped into SPIR-V
variables with builtin decorations, some are not. HLSL non-SV semantic strings
should all be mapped to SPIR-V variables without builtin decorations (but with
``Location`` decorations).

With these complications, if we are grouping multiple semantic strings in a
struct in the HLSL source code, that struct should be flattened and each of
its members should be mapped separately. For example, for the following:

.. code:: hlsl

  struct T {
    float2 clip0 : SV_ClipDistance0;
    float3 cull0 : SV_CullDistance0;
    float4 foo   : FOO;
  };

  struct S {
    float4 pos   : SV_Position;
    float2 clip1 : SV_ClipDistance1;
    float3 cull1 : SV_CullDistance1;
    float4 bar   : BAR;
    T      t;
  };

If we have an ``S`` input parameter in pixel shader, we should flatten it
recursively to generate five SPIR-V ``Input`` variables. Three of them are
decorated by the ``Position``, ``ClipDistance``, ``CullDistance`` builtin,
and two of them are decorated by the ``Location`` decoration. (Note that
``clip0`` and ``clip1`` are concatenated, also ``cull0`` and ``cull1``.
The ``ClipDistance`` and ``CullDistance`` builtins are special and explained
in the `ClipDistance & CullDistance`_ section.)

Flattening is infective because of Vulkan interface matching rules. If we
flatten a struct in the output of a previous stage, which may create multiple
variables decorated with different ``Location`` numbers, we also need to
flatten it in the input of the next stage. otherwise we may have ``Location``
mismatch even if we share the same definition of the struct. Because
hull/domain/geometry shader is optional, we can have different chains of shader
stages, which means we need to flatten all shader stage interfaces. For
hull/domain/geometry shader, their inputs/outputs have an additional arrayness.
So if we are seeing an array of structs in these shaders, we need to flatten
them into arrays of its fields.

Vulkan specific features
------------------------

We try to implement Vulkan specific features using the most intuitive and
non-intrusive ways in HLSL, which means we will prefer native language
constructs when possible. If that is inadequate, we then consider attaching
`Vulkan specific attributes`_ to them, or introducing new syntax.

Descriptors
~~~~~~~~~~~

The compiler provides multiple mechanisms to specify which Vulkan descriptor
a particular resource binds to.

In the source code, you can use the ``[[vk::binding(X[, Y])]]`` and
``[[vk::counter_binding(X)]]`` attribute. The native ``:register()`` attribute
is also respected.

On the command-line, you can use the ``-fvk-{b|s|t|u}-shift`` or
``-fvk-bind-register`` option.

If you can modify the source code, the ``[[vk::binding(X[, Y])]]`` and
``[[vk::counter_binding(X)]]`` attribute gives you find-grained control over
descriptor assignment.

If you cannot modify the source code, you can use command-line options to change
how ``:register()`` attribute is handled by the compiler. ``-fvk-bind-register``
lets you to specify the descriptor for the source at a certain register.
``-fvk-{b|s|t|u}-shift`` lets you to apply shifts to all register numbers
of a certain register type. They cannot be used together, though.

When the ``[[vk::combinedImageSampler]]`` attribute is applied, only the
``-fvk-t-shift`` value will be used to apply shifts to combined texture and
sampler resource bindings and any ``-fvk-s-shift`` value will be ignored.

Without attribute and command-line option, ``:register(xX, spaceY)`` will be
mapped to binding ``X`` in descriptor set ``Y``. Note that register type ``x``
is ignored, so this may cause overlap.

The more specific a mechanism is, the higher precedence it has, and command-line
option has higher precedence over source code attribute.

For more details, see `HLSL register and Vulkan binding`_, `Vulkan specific
attributes`_, and `Vulkan-specific options`_.

Subpass inputs
~~~~~~~~~~~~~~

Within a Vulkan `rendering pass <https://www.khronos.org/registry/vulkan/specs/1.1-extensions/html/vkspec.html#renderpass>`_,
a subpass can write results to an output target that can then be read by the
next subpass as an input subpass. The "Subpass Input" feature regards the
ability to read an output target.

Subpasses are read through two new builtin resource types, available only in
pixel shader:

.. code:: hlsl

  class SubpassInput<T> {
    T SubpassLoad();
  };

  class SubpassInputMS<T> {
    T SubpassLoad(int sampleIndex);
  };

In the above, ``T`` is a scalar or vector type. If omitted, it will defaults to
``float4``.

Subpass inputs are implicitly addressed by the pixel's (x, y, layer) coordinate.
These objects support reading the subpass input through the methods as shown
in the above.

A subpass input is selected by using a new attribute ``vk::input_attachment_index``.
For example:

.. code:: hlsl

  [[vk::input_attachment_index(i)]] SubpassInput input;

A ``vk::input_attachment_index`` of ``i`` selects the ith entry in the input
pass list. A subpass input without a ``vk::input_attachment_index`` will be
associated with the depth/stencil attachment. (See Vulkan API spec for more
information.)

Push constants
~~~~~~~~~~~~~~

Vulkan push constant blocks are represented using normal global variables of
struct types in HLSL. The variables (not the underlying struct types) should be
annotated with the ``[[vk::push_constant]]`` attribute.

Please note as per the requirements of Vulkan, "there must be no more than one
push constant block statically used per shader entry point." The one exception is
``SPV_NV_push_constant_bank``, where the blocks are spread over hardware banks
and the rule becomes per bank; see `Push constant banks`_ below.

Specialization constants
~~~~~~~~~~~~~~~~~~~~~~~~

To use Vulkan specialization constants, annotate global constants with the
``[[vk::constant_id(X)]]`` attribute. For example,

.. code:: hlsl

  [[vk::constant_id(1)]] const bool  specConstBool  = true;
  [[vk::constant_id(2)]] const int   specConstInt   = 42;
  [[vk::constant_id(3)]] const float specConstFloat = 1.5;

Shader Record Buffer
~~~~~~~~~~~~~~~~~~~~

SPV_NV_ray_tracing exposes user managed buffer in shader binding table by
using storage class ShaderRecordBufferNV. ConstantBuffer or cbuffer blocks
can now be mapped to this storage class under HLSL by using
``[[vk::shader_record_nv]]`` annotation. It is applicable only on ConstantBuffer
and cbuffer declarations.

Please note as per the requirements of VK_NV_ray_tracing, "there must be no
more than one shader_record_nv block statically used per shader entry point
otherwise results are undefined."

The official Khronos ray tracing extension also comes with a SPIR-V storage class
that has the same functionality. The ``[[vk::shader_record_ext]]`` annotation can
be used when targeting the SPV_KHR_ray_tracing extension.

Builtin variables
~~~~~~~~~~~~~~~~~

Some of the Vulkan builtin variables have no equivalents in native HLSL
language. To support them, ``[[vk::builtin("<builtin>")]]`` is introduced.
Right now the following ``<builtin>`` are supported:

* ``PointSize``: The GLSL equivalent is ``gl_PointSize``.
* ``HelperInvocation``: For Vulkan 1.3 or above, we use its GLSL equivalent
  ``gl_HelperInvocation`` and decorate it with ``HelperInvocation`` builtin
  since Vulkan 1.3 or above supports ``Volatile`` decoration for builtin
  variables. For Vulkan 1.2 or earlier, we do not create a builtin variable for
  ``HelperInvocation``. Instead, we create a variable with ``Private`` storage
  class and set its value as the result of `OpIsHelperInvocationEXT <https://htmlpreview.github.io/?https://github.com/KhronosGroup/SPIRV-Registry/blob/master/extensions/EXT/SPV_EXT_demote_to_helper_invocation.html#OpIsHelperInvocationEXT>`_
  instruction.
* ``BaseVertex``: The GLSL equivalent is ``gl_BaseVertexARB``.
  Need ``SPV_KHR_shader_draw_parameters`` extension.
* ``BaseInstance``: The GLSL equivalent is ``gl_BaseInstanceARB``.
  Need ``SPV_KHR_shader_draw_parameters`` extension.
* ``DrawIndex``: The GLSL equivalent is ``gl_DrawIDARB``.
  Need ``SPV_KHR_shader_draw_parameters`` extension.
* ``DeviceIndex``: The GLSL equivalent is ``gl_DeviceIndex``.
  Need ``SPV_KHR_device_group`` extension.
* ``ViewportMaskNV``: The GLSL equivalent is ``gl_ViewportMask``.

Please see Vulkan spec. `15.9. Built-In Variables <https://registry.khronos.org/vulkan/specs/latest/html/vkspec.html#interfaces-builtin-variables>`_
for detailed explanation of these builtins.

Helper Lane Support
~~~~~~~~~~~~~~~~~~~

Shader Model 6.7 introduces the `[WaveOpsIncludeHelperLanes]` attribute. When this
attribute is applied to a shader entry point, the SPIR-V backend will:

1. Add the ``SPV_KHR_maximal_reconvergence`` and ``SPV_KHR_quad_control``
   extensions to the module.
2. Add the ``QuadControlKHR`` capability.
3. Add the ``MaximallyReconvergesKHR`` and ``RequireFullQuadsKHR`` execution modes
   to the entry point.

This ensures that helper lanes are included in wave operations, which is the
behavior required by the HLSL specification.

Fused multiply-add
~~~~~~~~~~~~~~~~~~

The ``SPV_KHR_fma`` extension provides ``OpFmaKHR``, a core instruction that
computes ``a * b + c`` with a single rounding that the implementation must not
split. It is gated by the Vulkan ``VK_KHR_shader_fma`` device extension, whose
``VkPhysicalDeviceShaderFmaFeaturesKHR`` structure carries one feature bit per
operand width (``shaderFmaFloat16``, ``shaderFmaFloat32``, ``shaderFmaFloat64``).

SPIR-V CodeGen uses ``OpFmaKHR`` for a fused multiply-add on 32-bit float
(``float``, ``float2``, ``float3``, ``float4``) when the extension is enabled
with ``-fspv-extension=SPV_KHR_fma``; the module then contains the ``FMAKHR``
capability and the ``SPV_KHR_fma`` extension. HLSL spells a fused multiply-add
``mad()``; ``fma()`` is a ``double``-only intrinsic (it maps to ``dx.op.fma``),
and DXC does not use ``OpFmaKHR`` for ``double`` or for 16-bit float
(``half``/``min16float``) yet, so those keep the ``GLSL.std.450`` ``Fma``
extended instruction.

The extension is **not** enabled by default, because replacing the extended
instruction with ``OpFmaKHR`` is a visible change of the module: a driver without
``VK_KHR_shader_fma`` rejects it. Without
``-fspv-extension=SPV_KHR_fma`` the generated module is unchanged, and ordinary
``a * b + c`` arithmetic is never contracted into ``OpFmaKHR``. Note that a host
must also enable the matching ``shaderFmaFloat32`` feature; the compiler cannot
check that.

Split barriers
~~~~~~~~~~~~~~

The ``SPV_EXT_split_barrier`` extension splits a control barrier into an arrive
and a wait. ``GroupMemoryBarrierWithGroupSync()`` synchronizes every invocation
at one point: no invocation continues until all of them have arrived. A split
barrier lets an invocation announce that it has arrived, execute work that does
not depend on the rest of the group, and only then wait for it. It is gated by
the Vulkan ``VK_EXT_shader_split_barrier`` device extension, whose
``VkPhysicalDeviceShaderSplitBarrierFeaturesEXT`` structure carries the
``shaderSplitBarrier`` feature bit.

The entry points live in ``<vk/ext/split_barrier.h>``:

.. code:: hlsl

  #include <vk/ext/split_barrier.h>

  vk::SplitBarrierArrive();   // OpControlBarrierArriveEXT
  ...independent work...
  vk::SplitBarrierWait();     // OpControlBarrierWaitEXT

``OpControlBarrierArriveEXT`` and ``OpControlBarrierWaitEXT`` take the same
three operands as ``OpControlBarrier``: execution scope, memory scope and memory
semantics. DXC emits the scopes ``GroupMemoryBarrierWithGroupSync()`` uses
(execution scope ``Workgroup``, memory scope ``Workgroup``, ``WorkgroupMemory``
memory class), so a split barrier covers exactly the memory the classic
workgroup barrier covers. Only the memory order differs, because the extension
makes the arrive a ``Release`` and the wait an ``Acquire``: an arrive orders
nothing on its own, and workgroup memory written by another invocation is only
guaranteed to be visible after the wait. In particular the arrive is not a
memory barrier, and DXC never pairs it with a hidden ``OpMemoryBarrier``.

The extension is **not** enabled by default. A module using it declares the
``SplitBarrierEXT`` capability and the ``SPV_EXT_split_barrier`` extension, which
a driver without ``VK_EXT_shader_split_barrier`` rejects, so the entry points are
only accepted with ``-fspv-extension=SPV_EXT_split_barrier``. Without that flag
both of them are compile errors instead of a silent lowering to
``OpControlBarrier``, and a module that does not use them is unchanged. The pair
is also restricted to compute stages, which is where the ``SplitBarrierEXT``
capability is legal.

Limitations:

* **Pairing is not enforced.** The instructions carry no token operand, so the
  module cannot show which arrive a wait belongs to and DXC does not attempt a
  structural analysis. The shader author must ensure that every invocation of
  the group executes one arrive and one wait, that the wait is dominated by the
  arrive, and that both use the same scopes. An unmatched arrive, a wait without
  an arrive, or a wait executed twice compiles and is undefined behavior; no
  diagnostic is produced for any of them.
* The host must enable the ``shaderSplitBarrier`` feature bit. The extension also
  reserves shared memory for the barriers: subtract
  ``VkPhysicalDeviceShaderSplitBarrierPropertiesEXT::splitBarrierReservedSharedMemory``
  from ``maxComputeSharedMemorySize`` when sizing groupshared arrays. The
  compiler cannot check either of these.

Multiple wait queues
~~~~~~~~~~~~~~~~~~~~

The ``SPV_QCOM_multiple_wait_queues`` extension lets a shader ask an
implementation to keep several memory fills in flight for one loop instead of
unrolling it. It is gated by the Vulkan ``VK_QCOM_shader_multiple_wait_queues``
device extension, whose
``VkPhysicalDeviceShaderMultipleWaitQueuesFeaturesQCOM`` structure carries the
``shaderMultipleWaitQueues`` feature bit, and whose
``VkPhysicalDeviceShaderMultipleWaitQueuesPropertiesQCOM`` structure reports the
``maxShaderWaitQueues`` limit.

In HLSL the hint is a loop annotation, available on ``for``, ``while`` and ``do``
statements:

.. code:: hlsl

  [[vk::multiple_wait_queues]]
  for (uint i = 0; i < count; ++i) {
    acc += A[i] * B[i];          // OpLoopMerge ... MultipleWaitQueuesQCOM 0
  }

  [[vk::multiple_wait_queues(2)]]
  while (remaining > 0) { ... }  // OpLoopMerge ... MultipleWaitQueuesQCOM 2

The whole mechanism is one bit of the loop control of the annotated loop's
``OpLoopMerge``, plus the extension's capability in the module header:

.. code:: spirv

  OpCapability MultipleWaitQueuesQCOM            ; 4539
  OpExtension "SPV_QCOM_multiple_wait_queues"
  OpLoopMerge %merge %continue MultipleWaitQueuesQCOM 2

``MultipleWaitQueuesQCOM`` is loop control bit ``0x10000000``. It is not the
whole encoding: the enumerant has one literal operand, so the instruction carries
the maximum number of wait queues the compiler may use, and ``0`` means "all
available". ``[[vk::multiple_wait_queues]]`` without an argument emits ``0``; the
optional argument is that literal, so ``[[vk::multiple_wait_queues(2)]]`` emits
``2``. A negative argument is rejected by a warning and encoded as ``0``.

The bit is OR-ed with whatever loop control the loop already needs, so the
annotation composes with the existing loop attributes:
``[[vk::multiple_wait_queues]] [unroll]`` is encoded as
``Unroll|MultipleWaitQueuesQCOM`` and ``[[vk::multiple_wait_queues]] [loop]`` as
``DontUnroll|MultipleWaitQueuesQCOM``. The C++11 attribute list has to precede the
HLSL one, because the HLSL parser reads ``[[...]]`` attributes before ``[...]``
attributes; ``[unroll] [[vk::multiple_wait_queues]]`` is a parse error. The
annotation is dropped together with the loop if post-processing unrolls it, so the
bit is a property of the loop, not module-wide state.

The annotation is only accepted with
``-fspv-extension=SPV_QCOM_multiple_wait_queues``. A module using it declares the
``MultipleWaitQueuesQCOM`` capability and the ``SPV_QCOM_multiple_wait_queues``
extension, which a driver without ``VK_QCOM_shader_multiple_wait_queues`` rejects,
so the extension is **not** enabled by default: without the flag every annotated
loop is a compile error instead of a silently unannotated loop, and a module that
does not use the annotation is unchanged. Misuse is diagnosed as an error as well:
the attribute on anything that is not a ``for``/``while``/``do`` statement, and two
copies of it on one statement.

Limitations:

* **It is a hint.** The module records what the shader asked for; whether more than
  one wait queue is used, and whether that helps, is decided by the driver and by
  the device. A shader must not depend on the hint for correctness, results are
  identical either way, and no test can prove that a driver acts on it - DXC's
  tests assert the encoding only.
* **It implies no memory ordering.** Reads and writes that another invocation
  publishes still need the appropriate barrier; the annotation does not synchronize
  anything, and DXC does not insert a barrier around an annotated loop.
* The host must enable the ``shaderMultipleWaitQueues`` feature and must not ask for
  more queues than ``maxShaderWaitQueues`` reports. The compiler cannot check
  either of these; an argument above the device limit is at best ignored.

Long vectors
~~~~~~~~~~~~
The ``SPV_EXT_long_vector`` extension lifts the 1..4 component limit on
``OpTypeVector``. With the ``LongVectorEXT`` (5425) capability a vector may have an
arbitrary positive number of components, and the instructions that already accept
vector types accept those vectors as well - the arithmetic instructions,
``OpLoad`` / ``OpStore``, ``OpCompositeConstruct`` / ``Extract`` / ``Insert`` and
``OpVectorShuffle`` - but only in a fixed set of storage classes: Function,
Private, UniformConstant, Uniform, Workgroup, StorageBuffer,
PhysicalStorageBuffer, PushConstant, ShaderRecordBufferKHR, CrossWorkgroup and
Generic. It is gated by the Vulkan ``VK_EXT_shader_long_vector`` device extension,
whose feature struct carries the ``longVector`` feature bit and whose properties
struct reports the device's component-count limit, which a shader has to stay
within. The extension is the compilation target for GLSL's ``GL_EXT_long_vector``
and for the HLSL long vector proposal.

HLSL has no type of its own for a long vector: the front end rejects
``vector<T, N>`` for ``N > 4`` with "invalid value, valid range is between 1 and 4
inclusive", and the DXIL long vector feature is a different target. DXC names the
type through an inline SPIR-V type in ``<vk/ext/long_vector.h>``:

.. code:: hlsl

  #include <vk/ext/long_vector.h>

  vk::ext::LongVector<float, 8>  v8;      // OpTypeVector %float 8
  vk::ext::LongVector<float, 16> v16;     // OpTypeVector %float 16

  v8 = vk::ext::Concat(lo, hi);           // OpCompositeConstruct
  v8 = vk::ext::Set<5>(v8, x);            // OpCompositeInsert
  float y = vk::ext::Get<7>(v8);          // OpCompositeExtract

``vk::ext::Concat`` concatenates its constituents in order and has overloads for
two and four ordinary 4-component vectors as well as for two 8-component long
vectors, so 8- and 16-component values can be built out of what HLSL can express.
``Get<index>`` and ``Set<index>`` take the component index as a template argument,
which keeps it a compile-time constant for the ``LiteralInteger`` operand of
``OpCompositeExtract`` / ``OpCompositeInsert``; the low-level ``Concat`` /
``Extract`` / ``Insert`` declarations take it as an ``[[vk::ext_literal]]``
parameter. The operand order of ``OpCompositeInsert`` is the instruction's - the
new component ("Object") first, the vector it is inserted into ("Composite")
second - and ``Set<index>(value, component)`` wraps that in the order an HLSL
author expects.

This is a type plus element access, not an arithmetic system. HLSL's operators,
swizzles and implicit conversions are defined on ordinary vectors and do not apply
to a long vector, so a value is built from, and decomposed into, ``float2`` /
``float3`` / ``float4`` values and the arithmetic happens on those.

A module containing a long vector declares ``OpCapability LongVectorEXT`` and
``OpExtension "SPV_EXT_long_vector"``. Both are added by SPIR-V CodeGen from the
type itself (the ``SpirvIntrinsicType`` case of
``CapabilityVisitor::addCapabilityForType``), not by ``[[vk::ext_capability]]`` /
``[[vk::ext_extension]]`` on the header's declarations, which is what lets
``-fspv-extension`` both select and refuse the extension. The extension is **not**
enabled by default: a driver that does not expose ``VK_EXT_shader_long_vector``
rejects a module that declares the capability, so without
``-fspv-extension=SPV_EXT_long_vector`` every use is a compile error instead of a
module the host never asked for. The target environment must also emit SPIR-V 1.3
or later - ``SPV_EXT_long_vector`` is specified as modifications to SPIR-V 1.3 - so
``-fspv-target-env=vulkan1.1`` (or ``vulkan1.1spirv1.4``, ``vulkan1.2``,
``vulkan1.3``, ``universal1.5``) is required; the default, ``vulkan1.0``, emits
SPIR-V 1.0. The environment check compares the SPIR-V version the environment
emits (``FeatureManager::isTargetEnvSpirv1p3OrAbove``) rather than the
``spv_target_env`` enumerators, because every Vulkan environment sorts above every
universal one.

The extension also removes the "at least two constituents" rule of
``OpCompositeConstruct`` and allows ``OpTypeVector`` with a single component.
Neither changes DXC's pre-existing code generation: ``Concat`` emits the
four-constituent form for a 16-component vector, and a one-component vector is
still spelled as the scalar itself.

Restrictions, each diagnosed rather than miscompiled:

* A component count of four or less is an ordinary vector and is rejected with a
  diagnostic that points at the native HLSL vector types. Those already have a
  dedicated encoding (``SpirvType::VectorType``); a second, indistinguishable
  ``OpTypeVector %float 4`` with the capability attached to it is not what the
  author wants.
* A component count that is not a compile-time constant is rejected by the front
  end. A count taken from a specialization constant is a *different* instruction,
  ``OpTypeVectorIdEXT`` (5288), whose *Component Count* is an ``<id>`` of a 32-bit
  integer constant instruction instead of a ``LiteralInteger``. This header does not
  provide it: the type would have to be keyed on a specialization constant id in
  ``SpirvContext``'s structural uniquing, and spec-constant-sized vectors are
  additionally restricted in explicitly laid out storage classes. ``OpTypeVectorIdEXT``
  is instead the cooperative vector type of
  ``VK_NV_cooperative_vector`` - see `Cooperative vectors`_ below.
* A long vector in stage input or output is an error. ``SPV_EXT_long_vector`` lists
  the storage classes long vectors may be allocated in and Input/Output are not
  among them; SPIRV-Tools rejects such a module with "Long vector types with more
  than 4 components (or types containing them) not supported in storage class
  Input".
* A long vector cannot be the column type of a matrix; the extension keeps
  ``OpTypeVector`` at 2, 3 or 4 components there.

Limitations:

* **No buffer layout.** A long vector in Function, Private or Workgroup storage
  works - a local variable, a private global, or a ``groupshared`` variable. A long
  vector as a *member* of a struct in ``Uniform`` / ``StorageBuffer`` storage does
  not: DXC computes member offsets from the AST record shape rather than from the
  long vector's SPIR-V type, so the module declares an overlapping member and
  SPIRV-Tools rejects it. Laying long vectors out per storage class is a separate
  piece of work; until then keep long vectors in Function/Private/Workgroup storage
  and move values in and out through ordinary vectors.
* The compiler cannot check the device's component-count limit or the ``longVector``
  feature bit, and no test can prove how a driver executes a long vector. A shader
  that uses more components than the device reports still compiles and validates;
  creating the pipeline then fails.
* No arithmetic, comparison or swizzle surface is provided for long vectors. A
  component-wise operation is written on the ordinary vectors a value is built
  from and decomposed into.

See ``examples/spirv-extensions/ext-long-vector.hlsl`` for a self-contained example
and ``tools/clang/test/CodeGenSPIRV/vk.long-vector*.hlsl`` for the tests that pin
the capability, the type encoding, the composite instructions, the
optimizer-survival path and the diagnostics.

Cooperative vectors
~~~~~~~~~~~~~~~~~~~

The ``SPV_NV_cooperative_vector`` extension adds an opaque vector whose length and
component type are part of its SPIR-V type, plus a fixed instruction set for it:
a matrix-vector product, an accumulating matrix-vector product, two training
accumulators, and a load and a store that move values between memory and the
opaque type. The point is machine-learning inference: the weight matrix stays in
memory and is streamed, while the implementation decides how wide the vector
registers are, instead of the shader fixing a register layout per component. It is
gated by the Vulkan ``VK_NV_cooperative_vector`` device extension, which exposes
the inferencing and the training halves as separate feature bits.

The type is ``OpTypeVectorIdEXT`` (5288; the grammar also aliases it as
``OpTypeCooperativeVectorNV``), whose *Component Type* is an ``<id>`` of a scalar
type and whose *Component Count* is an ``<id>`` of a 32-bit integer constant
instruction - the instruction ``SPV_EXT_long_vector`` uses for a vector with a
specialization-constant component count, which ``<vk/ext/long_vector.h>``
deliberately does not provide. Only ``CooperativeVectorNV`` (5394) and
``LongVectorEXT`` (5425) permit it, so a module that contains one declares one of
the two capabilities:

.. code:: spirv

  %cv4 = OpTypeVectorIdEXT %float %uint_4  ; a cooperative vector of 4 floats

HLSL has no such type, so DXC names it through an inline SPIR-V type in
``<vk/nv/cooperative_vector.h>``, and the six instructions are
``[[vk::ext_instruction]]`` declarations with one parameter per SPIR-V operand:

.. code:: hlsl

  #include <vk/nv/cooperative_vector.h>

  using float4cv = vk::nv::CooperativeVector<float, 4>;

  groupshared float g_matrix[32]; // 8 rows x 4 columns
  groupshared float g_input[4];
  groupshared float g_output[8];

  float4cv v = vk::nv::Load<float, 4>(g_input, 0);         // OpCooperativeVectorLoadNV
  vk::nv::CooperativeVector<float, 8> r = vk::nv::MatrixMul<float, 8, 4>(
      v, vk::CooperativeVectorComponentTypeFloat32NV,
      g_matrix, /*matrixOffset*/ 0,
      vk::CooperativeVectorComponentTypeFloat32NV,
      /*M*/ 8, /*K*/ 4, vk::CooperativeVectorMatrixLayoutRowMajorNV,
      /*transpose*/ false, /*matrixStride*/ 16);           // OpCooperativeVectorMatrixMulNV
  vk::nv::Store<float, 8>(g_output, 0, r);                 // OpCooperativeVectorStoreNV

The six entry points are ``Load``, ``Store``, ``MatrixMul``, ``MatrixMulAdd``
(OpCooperativeVectorMatrixMulAddNV, 5292), ``OuterProductAccumulate``
(OpCooperativeVectorOuterProductAccumulateNV, 5290) and ``ReduceSumAccumulate``
(OpCooperativeVectorReduceSumAccumulateNV, 5291). The last two are the training
half and are the only ones that return ``void``: the accumulator array in memory
is their destination. Each of the three memory-taking entry points has two
overloads, one with and one without the optional ``MatrixStride`` operand, because
``RowMajorNV`` / ``ColumnMajorNV`` describe the stride and the two ``*OptimalNV``
layouts leave it to the device.

The bias of ``MatrixMulAdd`` is a pointer, an offset and an interpretation, the
same shape as the matrix, and not a cooperative vector value; that is the
instruction's operand list, not a choice made here. The operand order of every
entry point is the instruction's, so the header comment of each declaration spells
out the operand list it implements.

Capabilities are selected per instruction, not once for the extension:
``CooperativeVectorNV`` (5394) for the type and for ``Load``, ``Store``,
``MatrixMul`` and ``MatrixMulAdd``, and ``CooperativeVectorTrainingNV`` (5435) for
``OuterProductAccumulate`` and ``ReduceSumAccumulate``. A module that uses a
training instruction declares both; a module that only infers declares only the
first, which is what keeps it acceptable on a device that does not implement the
training half. Both are added by SPIR-V CodeGen from the type
(``CapabilityVisitor::addCapabilityForType``) and from the instruction
(``CapabilityVisitor::visitInstruction``), not by ``[[vk::ext_capability]]`` /
``[[vk::ext_extension]]`` on the header's declarations, which is what lets
``-fspv-extension`` both select and refuse the extension.

The extension is **not** enabled by default: a driver that does not expose
``VK_NV_cooperative_vector`` rejects a module that declares the capability, so
without ``-fspv-extension=SPV_NV_cooperative_vector`` every use is a compile error
instead of a module the host never asked for. There is **no target-environment
gate**: the vendored grammar gives ``OpTypeVectorIdEXT`` and all six instructions no
SPIR-V version requirement (``"version": "None"``), so a module produced from this
header also validates at the default environment, ``vulkan1.0``. That is unlike
``SPV_EXT_long_vector``, which is specified as modifications to SPIR-V 1.3.

Pointer operands and workgroup staging:

* SPIRV-Tools requires the pointer of every one of these instructions to point at
  an ``OpTypeArray`` or ``OpTypeRuntimeArray`` in the Workgroup, StorageBuffer or
  PhysicalStorageBuffer storage class. In HLSL the shape that produces exactly that
  is a ``groupshared`` array passed whole, so the matrix, the bias, the source and
  the destination of a value are workgroup arrays. Data that arrives in a buffer has
  to be staged through workgroup memory first.
* A ``groupshared`` *cooperative vector* is an error: ``SPV_NV_cooperative_vector``
  allows the type in Function and Private storage and as a function parameter only,
  and SPIRV-Tools rejects the module otherwise. Stage the data, not the vector.

Every operand the extension requires to name a constant instruction -
``InputInterpretation``, ``MatrixInterpretation``, ``BiasInterpretation``, ``M``,
``K``, ``MemoryLayout`` and ``Transpose`` - has to be passed as a compile-time
constant, because a declaration-only entry point has one parameter per SPIR-V
operand and cannot bake values in. SPIR-V CodeGen reports a value it cannot fold
into an ``OpConstant`` ("... must be compile-time constants") instead of producing
a module that SPIRV-Tools rejects, and there is no instruction that converts a
memory layout at run time, so a layout cannot be computed in the shader at all. The
interpretation and layout parameters take the enumerators of ``<vk/spirv.h>``
(``vk::CooperativeVectorComponentType``, ``vk::CooperativeVectorMatrixLayout``),
which is also the header that materializes those enumerators as module-scope
variables - a cost ``<vk/khr/cooperative_matrix.h>`` already pays.

Other restrictions, each diagnosed rather than miscompiled:

* The component type must be a 32-bit integer or a 16/32-bit float; ``double``,
  ``bool``, 8- and 16-bit integers are rejected by the front end (a default
  template argument of the entry points) and by ``CapabilityVisitor``.
* A pointer operand that addresses a single component instead of an array is
  rejected by the front end, because it would lower to a pointer SPIRV-Tools
  rejects.
* MatrixStride has to match the layout overload; passing a stride to an
  ``*OptimalNV`` layout or leaving it out for ``RowMajorNV`` / ``ColumnMajorNV`` is
  a deliberate choice in the source that the compiler cannot second-guess.

Limitations:

* **No component access.** There is no instruction that reads or writes a single
  component of a cooperative vector, so a shader moves values through memory with
  ``Load`` / ``Store`` and combines them with the matrix and reduce instructions.
  There is no arithmetic, comparison or swizzle surface, and ``vk::nv::`` provides
  none.
* **One pointer form.** A buffer read produces a pointer to the buffer block, not to
  the array the instruction needs, so buffer-resident matrices have to be staged
  through ``groupshared`` memory. Passing a private or function-local array
  produces the right shape with the wrong storage class; the compiler cannot see
  the storage class of an ``[[vk::ext_reference]]`` argument, and SPIRV-Tools
  rejects the module.
* **No CooperativeMatrixOperands.** The trailing optional operand of
  ``OpCooperativeVectorMatrixMulNV`` / ``...MatrixMulAddNV`` - the literal mask that
  carries the ``Matrix*SignedComponentsKHR`` hints - is not modelled, so a shader
  cannot request them and inferencing on signed 8-bit data uses the device's default
  interpretation. The two instructions are otherwise emitted with the full operand
  list.
* **What the host must query**, and the compiler cannot check: the
  ``VK_NV_COOPERATIVE_VECTOR_EXTENSION_NAME`` device extension;
  ``cooperativeVectorSupportedStages`` and the component type / layout pairs a
  stage reports; ``maxCooperativeVectorComponents`` and
  ``maxCooperativeVectorMatrixComponents``, which a shader can exceed while still
  compiling and validating; the training feature bits
  (``cooperativeVectorTrainingFloat16Accumulation``,
  ``cooperativeVectorTrainingFloat32Accumulation``) for the two training
  instructions. All of these live in the
  ``VkPhysicalDeviceCooperativeVectorPropertiesNV`` structure that
  ``vkGetPhysicalDeviceCooperativeVectorPropertiesNV`` fills in.
* No driver in CI implements the extension, so SPIRV-Tools validation is the only
  signal: the instructions are pinned as encodings, not executed.

``VK_NV_cooperative_vector`` is not a replacement for the HLSL cooperative vector
type that DXC removed in favour of LinAlg: it is a SPIR-V-only surface that adds no
DXIL opcode, no validator support and no HLSL type, and it is available only when
the extension is requested.

See ``examples/spirv-extensions/nv-cooperative-vector.hlsl`` for a self-contained
matrix-vector example and ``tools/clang/test/CodeGenSPIRV/nv.cooperative-vector*.hlsl``
for the tests that pin the capability per family, the six instruction encodings, the
optimizer-survival path and the diagnostics.

NV cooperative matrix decode vector
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

The ``SPV_NV_cooperative_matrix_decode_vector`` extension adds one bit and one
operand to the tensor memory access of ``SPV_NV_cooperative_matrix2``. That
extension lets a cooperative matrix be loaded from, and stored to, *tensor* memory
through ``OpCooperativeMatrixLoadTensorNV`` (5367) and
``OpCooperativeMatrixStoreTensorNV`` (5368), whose last operand is a
``TensorAddressingOperands`` bit mask followed by one operand per set bit. The
mask has three bits:

.. code:: spirv

  TensorAddressingOperands = None | TensorView | DecodeFunc | DecodeVectorFunc
                             (0)    (0x0001)     (0x0002)     (0x0004)

``DecodeFunc`` names a function that decodes one element of the block per call;
``DecodeVectorFunc``, the new bit, names a function that decodes a *vector* of
block-adjacent elements per call, so one callback invocation fills several matrix
elements at once. The extension is gated by the Vulkan
``VK_NV_cooperative_matrix_decode_vector`` device extension.

.. code:: spirv

  OpCapability TensorAddressingNV                ; 5439, SPV_NV_tensor_addressing
  OpCapability CooperativeMatrixTensorAddressingNV ; 5433, SPV_NV_cooperative_matrix2
  OpCapability CooperativeMatrixBlockLoadsNV     ; 5434
  OpCapability CooperativeMatrixDecodeVectorNV   ; 5447, needs 5434
  OpExtension "SPV_NV_tensor_addressing"
  OpExtension "SPV_NV_cooperative_matrix2"
  OpExtension "SPV_NV_cooperative_matrix_decode_vector"

  %layout = OpTypeTensorLayoutNV %uint_2 %uint_2    ; rank 2, clamp to edge
  %tl     = OpCreateTensorLayoutNV %layout
  %m      = OpCooperativeMatrixLoadTensorNV %mat %data %object %tl None
            DecodeFunc|DecodeVectorFunc %decode_scalar %decode_vector

The dependency chain is the part a module can get wrong without noticing: 5447
requires ``CooperativeMatrixBlockLoadsNV`` (5434) as well as the two tensor
addressing capabilities, and ``DecodeVectorFunc`` requires ``DecodeFunc`` to be
present as well ("DecodeVectorFunc requires DecodeFunc to also be specified"), so
a valid module always names *two* functions and four capabilities.

The HLSL surface is in ``<vk/nv/cooperative_matrix_decode_vector.h>``:

.. code:: hlsl

  #include <vk/nv/cooperative_matrix_decode_vector.h>

  using Mat = vk::khr::CooperativeMatrixA<float, vk::ScopeWorkgroup, 16, 16>;
  using Layout = vk::nv::TensorLayout<2, vk::nv::TensorClampModeClampToEdge>;
  groupshared float g_tensor[256];
  groupshared float g_matrix[256];

  Layout layout = vk::nv::CreateTensorLayout<2, vk::nv::TensorClampModeClampToEdge>();
  Mat source;
  Mat m = vk::nv::__builtin_spv_CooperativeMatrixLoadTensorNV<4>(
      g_tensor, source, layout);
  m.Store<vk::CooperativeMatrixLayoutRowMajorKHR>(
      vk::GetGroupSharedAddress(g_matrix[0]), 64);

``vk::nv::TensorLayout<dim, clampMode>`` is ``OpTypeTensorLayoutNV`` (5370).
Both of its operands are ``<id>``\ s of 32-bit integer constants - the grammar
snapshot in ``external/SPIRV-Headers`` spells ``Dim`` and ``ClampMode`` as
``IdRef``, and SPIRV-Tools dereferences both ("OpTypeTensorLayoutNV Dim <id> ...
is not a 32-bit integer") - so both are written as
``vk::integral_constant<uint, N>`` and not as literals, which is why they are
template arguments and not function parameters. ``Dim`` has to be between 1 and 5
and ``ClampMode`` one of the five ``TensorClampMode`` enumerators, both diagnosed
rather than emitted. ``vk::nv::CreateTensorLayout`` is a plain
``[[vk::ext_instruction(5372)]]`` wrapper for ``OpCreateTensorLayoutNV``.

The load itself is a compiler builtin rather than a header function, for the same
reason ``__builtin_spv_CooperativeMatrixReduceEXT`` in
``<vk/khr/cooperative_matrix.h>`` is one: the ``DecodeFunc`` and
``DecodeVectorFunc`` operands are the ``<id>``\ s of *functions*, and SPIR-V has
no operand form that names an HLSL function. CodeGen synthesizes the pair with the
signature SPIRV-Tools requires of them
(``external/SPIRV-Tools``, ``ValidateCooperativeMatrixLoadStoreTensorNV``):

* the return type is the matrix component type for ``DecodeFunc`` and a 2-, 4- or
  8-component vector of it for ``DecodeVectorFunc``,
* the first parameter is a pointer in the ``PhysicalStorageBuffer`` storage class,
* the second and third parameters are arrays of 32-bit integers whose length is the
  ``Dim`` of the tensor layout.

The first template argument of the entry point is the decode-vector length (2 or
4 here; 8 would need ``LongVectorEXT``). The synthesized bodies return
``OpUndef``, so what is defined is the *encoding* of the load - a shader cannot
supply the decode itself yet, exactly as it cannot supply the combine function of
``OpCooperativeMatrixReduceEXT``.

Because the decode functions' first parameter is a ``PhysicalStorageBuffer``
pointer, a module built from this header always declares
``OpCapability PhysicalStorageBufferAddresses`` and promotes its addressing model
to ``PhysicalStorageBuffer64``; with the Vulkan memory model that
``OpTypeCooperativeMatrixKHR`` already requires, the module's memory model is
``OpMemoryModel PhysicalStorageBuffer64 Vulkan``, not ``Logical Vulkan``. A
cooperative matrix type in turn requires SPIR-V 1.6, so the target environment is
``-fspv-target-env=vulkan1.3``, as for every cooperative matrix feature.

The extension is **not** enabled by default: without
``-fspv-extension=SPV_NV_cooperative_matrix_decode_vector`` every use is a
compile error ("SPIR-V extension 'SPV_NV_cooperative_matrix_decode_vector'
required for cooperative matrix decode vector block loads but not permitted to
use"), because a driver without ``VK_NV_cooperative_matrix_decode_vector`` rejects
a module declaring ``CooperativeMatrixDecodeVectorNV``.

Restrictions, all diagnosed rather than miscompiled:

* The three prerequisite extensions are *not* optional for the instruction -
  ``SPV_NV_cooperative_matrix2`` defines ``OpCooperativeMatrixLoadTensorNV`` and
  ``SPV_NV_tensor_addressing`` defines the tensor layout type - so CodeGen always
  declares them. An explicit ``-fspv-extension`` list replaces the extensions that
  are on by default, so such a list has to name all four.
* The pointer the block is read through has to point at the array, in the
  Workgroup, StorageBuffer or PhysicalStorageBuffer storage class. A ``groupshared``
  array passed whole is the shape that produces it; an element of the array, or a
  buffer handle, is rejected. A function-local array has the right shape with the
  wrong storage class, which the front end cannot see through
  ``[[vk::ext_reference]]``; buffer-resident data has to be staged through
  ``groupshared`` memory first.
* The decode-vector length is 2 or 4. 8 is legal in SPIR-V but needs
  ``OpCapability LongVectorEXT``, which this header does not request.
* ``bfloat16_t`` components are not accepted: the decode-vector function would need
  an ``OpTypeVector`` of ``bfloat16_t``, which requires ``BFloat16TypeKHR``.
* Only the tensor form of the load is provided. ``OpCooperativeMatrixLoadTensorNV``
  without tensor addressing operands, and the store, are separate surface;
  SPIRV-Tools rejects ``DecodeFunc``/``DecodeVectorFunc`` on
  ``OpCooperativeMatrixStoreTensorNV`` anyway.

What this cannot prove: no driver in CI implements the extension, so SPIRV-Tools
validation is the only signal and the feature is pinned as an encoding, never
executed. The host side is out of the compiler's reach: it has to enable
``VK_NV_cooperative_matrix_decode_vector`` together with
``VK_NV_cooperative_matrix2``, ``VK_NV_tensor_addressing`` and
``VK_KHR_cooperative_matrix``, check that
``vkGetPhysicalDeviceCooperativeMatrix2PropertiesNV`` reports tensor addressing,
block loads and the decode-vector feature for the stage, that the cooperative
matrix properties cover the M/N/type/scope combination, that the device accepts the
tensor rank and clamp mode the shader asks for, and that buffer device address
support is enabled for the ``PhysicalStorageBuffer`` pointer the decode functions
take. A shader that exceeds any of those limits still compiles and fails pipeline
creation.

See ``examples/spirv-extensions/nv-cooperative-matrix-decode-vector.hlsl`` for a
self-contained block-load example and
``tools/clang/test/CodeGenSPIRV/nv.decode-vector*.hlsl`` for the tests that pin
the capability set, the tensor layout, the two function signatures and their
operand positions, the optimizer-survival path and the diagnostics.

Push constant banks
~~~~~~~~~~~~~~~~~~~

The ``SPV_NV_push_constant_bank`` extension lets a shader place its push constant
blocks in different hardware *banks* and at an explicit byte offset inside its
bank. NVIDIA hardware has several banks of push constant / push data memory,
while a descriptor set exposes a single set of push data; spreading push
constants over several banks is what lets a descriptor-heap application reach
more root-descriptor data without a descriptor set per shader. It is gated by the
Vulkan ``VK_NV_push_constant_bank`` device extension, whose
``VkPhysicalDevicePushConstantBankFeaturesNV`` structure carries the
``pushConstantBank`` feature bit.

The extension adds no instruction, only two decorations, both of which apply to
the push constant *variable*:

.. code:: spirv

  OpCapability PushConstantBanksNV ; 5423
  OpExtension "SPV_NV_push_constant_bank"
  OpDecorate %pcs BankNV 1         ; 5397, the bank the block lives in
  OpDecorate %pcs MemberOffsetNV 64 ; 5358, base byte offset inside that bank

``MemberOffsetNV`` is *not* a member decoration, despite its name: the registry
text says "Apply to a variable with PushConstant storage class to specify a base
offset (in bytes) that is added to all member offsets within the block", and both
decorations are plain ``OpDecorate`` on the ``OpVariable``. It does not replace
the ``OpMemberDecorate ... Offset`` decorations, which keep describing the
layout inside the block. A block without ``BankNV`` is in bank 0, and a block
without ``MemberOffsetNV`` starts at byte 0 of its bank, so a shader that uses
neither decoration is encoded exactly as before.

In HLSL the two attributes go on the ``[[vk::push_constant]]`` block:

.. code:: hlsl

  [[vk::push_constant]]
  [[vk::push_constant_bank(1)]]
  [[vk::push_constant_bank_offset(64)]]
  PerDraw perDraw; // bank 1, members start at byte 64 of bank 1

.. code:: hlsl

  // Two blocks in two banks, which plain SPIR-V forbids.
  [[vk::push_constant]] PerFrame perFrame;      // bank 0, offset 0
  [[vk::push_constant]]
  [[vk::push_constant_bank(1)]] PerDraw perDraw;

A module that declares more than one ``PushConstant`` variable per entry point is
valid only with the ``PushConstantBanksNV`` capability, so the uniqueness rule
becomes **at most one push constant block per bank** rather than at most one
block: two blocks may coexist if and only if their banks differ. A block without
``[[vk::push_constant_bank]]`` counts as bank 0, so it still collides with an
explicit bank 0 block. Two blocks in the same bank, the attributes without
``[[vk::push_constant]]``, one attribute twice on the same declaration, a
negative bank index or offset, and the attributes without
``-fspv-extension=SPV_NV_push_constant_bank`` are all errors - see
``tools/clang/test/CodeGenSPIRV/vk.push-constant-bank.*.hlsl``.

The extension is **not** enabled by default: a module that uses the decorations
declares the ``PushConstantBanksNV`` capability and the
``SPV_NV_push_constant_bank`` extension, which a driver without
``VK_NV_push_constant_bank`` rejects. Without
``-fspv-extension=SPV_NV_push_constant_bank`` the attributes are therefore
rejected instead of silently dropped, and a module that does not use them is
unchanged.

Limitations:

* **Bank count and bank size are host facts.** How many banks the device has is
  reported per stage by
  ``VkPhysicalDevicePushConstantBankPropertiesNV::maxGraphicsPushConstantBanks``
  and ``maxComputePushConstantBanks`` (and the ``...PushDataBanks`` variants when
  push data is mapped through ``SPV_EXT_descriptor_heap``); the size of each bank
  is the ordinary ``VkPhysicalDeviceLimits::maxPushConstantsSize``. The compiler
  cannot check either of them, so a shader that asks for bank 3 compiles and
  validates, and is only wrong on a device with fewer banks. Keep the bank
  numbers of the shader and of the host mapping in one place in the application.
* **The host must agree with the decoration.** Placement is decided by
  ``VkPushConstantBankInfoNV`` - chained to ``VkPushConstantsInfo`` and submitted
  with ``vkCmdPushConstants2``, or chained to
  ``VkDescriptorSetAndBindingMappingEXT`` / ``VkPushDataInfoEXT`` under a
  descriptor heap. The offset given to the API is the byte offset inside the bank
  and therefore already includes the ``MemberOffsetNV`` base offset. Nothing in
  the module can be checked against the host mapping at compile time.
* Offsets stay subject to the ordinary push constant layout rules, so
  ``MemberOffsetNV`` has to respect the alignment of the block's first member;
  DXC does not round it and does not diagnose a misaligned base offset.

Mixed-float dot product
~~~~~~~~~~~~~~~~~~~~~~~

The ``SPV_VALVE_mixed_float_dot_product`` extension adds core instructions that
multiply corresponding elements of two short vectors of 16-bit floats and add the
sum into a wider accumulator with a single rounding. HLSL's ``dot2add`` has exactly
that shape:

.. code:: hlsl

  // float dot2add( half2 a, half2 b, float acc );
  //   a.x * b.x + a.y * b.y + acc

Without the extension, SPIR-V CodeGen has to rebuild the operation from scalar
instructions: the products are rounded to 16-bit float by ``OpFMul``, widened with
``OpFConvert``, and the lanes and the accumulator are added with ``OpFAdd``, so the
result is rounded several times and is not the same number as a single-rounding
dot product. With ``-fspv-extension=SPV_VALVE_mixed_float_dot_product`` the whole
thing becomes one instruction, and the double rounding disappears:

.. code:: spirv

  OpCapability DotProductFloat16AccFloat32VALVE ; 6912
  OpExtension "SPV_VALVE_mixed_float_dot_product"
  %res = OpFDot2MixAcc32VALVE %float %a %b %acc

The capability is per (input encoding, accumulator) pair, and DXC only emits the
pair HLSL can express - IEEE-754 FP16 inputs with an FP32 accumulator,
``DotProductFloat16AccFloat32VALVE``:

* ``OpFDot2MixAcc16VALVE`` (FP16 inputs, FP16 accumulator,
  ``DotProductFloat16AccFloat16VALVE``) has no HLSL call site: the single
  ``dot2add`` overload always accumulates in ``float``.
* ``OpFDot2MixAcc32VALVE`` with bfloat16 inputs (``DotProductBFloat16AccVALVE``,
  which depends on the ``BFloat16TypeKHR`` capability of ``SPV_KHR_bfloat16``) is
  unreachable too: ``dot2add`` takes ``float16_t<2>`` and ``bfloat16_t2`` is not
  implicitly convertible to it, so a ``bfloat16_t2`` overload of ``dot2add`` -
  which DXIL does not have either - would be needed first. An explicit ``half2``
  conversion is not a substitute: bfloat16 and fp16 have different mantissa widths
  and exponent ranges, so the conversion changes the result.
* ``OpFDot4MixAcc32VALVE`` (``DotProductFloat8AccFloat32VALVE``, grammar dependency
  ``Float8EXT``) needs 4-component vectors of 8-bit floats, i.e. the
  ``SPV_EXT_float8`` type system (``OpTypeFloat 8`` with a Float8E4M3/Float8E5M2
  encoding), which this backend does not implement yet.

The extension is **not** enabled by default: VALVE extensions are vendor-specific,
the capability is only implemented by drivers that expose
``VK_VALVE_shader_mixed_float_dot_product``, and a module that carries it is
rejected by every other driver. Without
``-fspv-extension=SPV_VALVE_mixed_float_dot_product`` the generated module is
unchanged, down to the unfused ``OpFMul`` / ``OpFConvert`` / ``OpFAdd`` sequence
(``tools/clang/test/CodeGenSPIRV/vk.valve-dot2add.off.hlsl`` pins it). The fused
form also requires 16-bit ``float16_t``, i.e. ``-enable-16bit-types``: without it
``half``/``float16_t`` is an alias for 32-bit ``float`` in SPIR-V CodeGen, so the
operands are not FP16 vectors and the VALVE instruction is not used. (In that
configuration ``dot2add`` is unusable anyway - the pre-existing unfused lowering
converts a 32-bit vector to itself and the module fails validation - which is a
limitation of ``dot2add`` and unrelated to this extension.) Note that the host must
also enable the device extension and its feature bit; the compiler cannot check
that, and no CTS or driver in CI implements the extension, so the only validity
signal is SPIRV-Tools.

Opacity micromaps
~~~~~~~~~~~~~~~~~
The ``SPV_KHR_opacity_micromap`` extension lets ray query traversal evaluate
opacity micromaps: per-micro-triangle opacity state stored in the acceleration
structure, which makes a triangle opaque or transparent at a resolution finer
than the triangle itself instead of treating it as a single opacity value. It
is gated by the Vulkan ``VK_KHR_opacity_micromap`` device extension, whose
``VkPhysicalDeviceOpacityMicromapFeaturesEXT`` structure carries the
``micromap`` feature bit (and ``micromapCaptureReplay`` for tools).

HLSL spells the opt-in as a ray flag while SPIR-V spells it as a module-level
execution mode, so the two are not a translation of each other:

* ``RAYQUERY_FLAG_ALLOW_OPACITY_MICROMAPS`` is the second template argument of
  ``RayQuery``, ``RayQuery<RayFlags, RayQueryFlags>``. It has no SPIR-V ray flag
  at all and does not reach the module otherwise.
* ``RAY_FLAG_FORCE_OMM_2_STATE`` is the ``RAY_FLAG_*`` spelling. It is passed
  through as part of the ray-flags operand of ``OpRayQueryInitializeKHR`` /
  ``OpTraceRayKHR``, where the same 0x400 bit is
  ``ForceOpacityMicromap2StateKHR``.
* ``RAYTRACING_PIPELINE_FLAG_ALLOW_OPACITY_MICROMAPS`` is the host-side
  ``VK_PIPELINE_CREATE_RAY_TRACING_OPACITY_MICROMAP_BIT_KHR`` pipeline
  creation flag; a pipeline-only workload needs no shader change for it.

With ``-fspv-extension=SPV_KHR_opacity_micromap``, DXC derives the execution
mode from either ray flag:

.. code:: hlsl

  RayQuery<RAY_FLAG_NONE, RAYQUERY_FLAG_ALLOW_OPACITY_MICROMAPS> q;
  q.TraceRayInline(accel, RAY_FLAG_FORCE_OMM_2_STATE, 0xFF, ray);

.. code:: spirv

  OpCapability RayTracingOpacityMicromapExecutionModeKHR ; 6032
  ; 5381, only when RAY_FLAG_FORCE_OMM_2_STATE reaches a ray-flags operand:
  OpCapability RayTracingOpacityMicromapKHR
  OpExtension "SPV_KHR_opacity_micromap"
  OpEntryPoint RayGenerationKHR %main "main" ...
  OpExecutionModeId %main OpacityMicromapIdKHR %opacityMicromapEnable ; 6031
  OpDecorate %opacityMicromapEnable SpecId 0
  %bool = OpTypeBool
  %opacityMicromapEnable = OpSpecConstantTrue %bool

``OpacityMicromapIdKHR`` takes an id operand, so it is emitted with
``OpExecutionModeId``; the literal-operand ``OpExecutionMode`` form is not
valid for it and SPIRV-Tools rejects it. The operand is a boolean
specialization constant - the extension specifies "the id of a constant
instruction of ``OpTypeBool`` which may be a specialization constant" - and not
an id that selects a micromap array. It is emitted as ``OpSpecConstantTrue``
and is never folded to ``OpConstantTrue``, so the host can still specialize it:
the default is true, which means a pipeline that opts in with
``VK_PIPELINE_CREATE_RAY_TRACING_OPACITY_MICROMAP_BIT_KHR`` and enables the
``micromap`` feature gets opacity micromaps without specializing anything, and
a host that wants them off specializes the constant to ``VK_FALSE``.
``-fvk-opacity-micromap-spec-id=N`` picks the ``SpecId`` (default 0) so that it
does not collide with the ``SpecId`` of a ``[[vk::constant_id(N)]]`` constant
in the same shader. The constant is only emitted when the extension is enabled
*and* an entry point requests opacity micromaps.

The mode is emitted once per entry point, and only for the entry points that
request it: an entry point whose ray queries do not set the flag keeps its
previous output. Per the extension, the execution mode only affects ray query
traversal. A ``TraceRay()``-only shader declares it as well, because the ray
flag is where DXC learns about the opt-in, but for such a shader the mode is
inert and the pipeline creation flag is what enables opacity micromaps.

The extension is **not** enabled by default: a module that carries
``RayTracingOpacityMicromapExecutionModeKHR`` is rejected by a driver without
``VK_KHR_opacity_micromap``, and the module interface grows a specialization
constant. Without ``-fspv-extension=SPV_KHR_opacity_micromap`` - and without
the ``-fspv-extension=KHR`` wildcard, which enables every KHR extension - the
generated module is byte-identical to before this support was added and the ray
flags keep their flag-only code generation; DXC reports a warning
(``opacity micromap ray flag ignored``) instead of dropping the opt-in
silently. Two consequences of that pass-through are worth knowing:

* ``RAYQUERY_FLAG_ALLOW_OPACITY_MICROMAPS`` has no SPIR-V ray flag, so bit 0 of
  the ``RayQuery`` ray flags would be encoded as ``OpaqueKHR`` if it reached
  the ray-flags operand. The ``RayQueryFlags`` template argument does not reach
  the operand, so the supported spelling is unaffected; the execution mode, not
  the flag, is what enables opacity micromaps.
* A shader that passes ``RAY_FLAG_FORCE_OMM_2_STATE`` without the extension
  produces a ray-flags operand with the ``ForceOpacityMicromap2StateKHR`` bit
  but no ``RayTracingOpacityMicromapKHR`` capability, which SPIRV-Tools
  rejects: for that flag the extension is required, not optional.
* Only compile-time constant ray flags can be recognized. The
  ``RayQueryFlags`` template argument always is one; a ``RayFlags`` argument
  that is a variable or any other runtime expression is passed through
  unchanged and cannot trigger the execution mode, so pass a constant such as
  ``RAY_FLAG_FORCE_OMM_2_STATE``.

Only the ``SPV_KHR_opacity_micromap`` spelling is emitted. The
pre-ratification ``SPV_EXT_opacity_micromap`` names the same capabilities but
has no execution mode - the part that needs compiler support - and the
extension text requires the KHR spelling in a module that uses
``OpacityMicromapIdKHR``.

See ``examples/spirv-extensions/khr-opacity-micromap.hlsl`` for a
self-contained example and
``tools/clang/test/CodeGenSPIRV/vk.opacity-micromap*.hlsl`` for the tests that
pin the capability and the extension, the ``OpExecutionModeId`` encoding with
its specialization constant, the ``SpecId`` override, the per-entry-point
attachment, the unchanged output when the flag or the extension is absent, and
the survival of the mode through spirv-opt.

Cluster acceleration structures
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

``VK_NV_cluster_acceleration_structure`` groups the triangles of a mesh into
clusters and gives every cluster an identity that a shader can read back from an
intersection. A renderer uses that identity to pick the material, the level of
detail or the shading bin of the triangle that was hit: the ID is shared by all
the triangles of one cluster, so the lookup stays small and cache friendly, while
the primitive index is unique per triangle. Building the clusters is a host
operation; the only shader-visible part of the extension is the cluster ID of an
intersection.

The accessors live in ``<vk/nv/cluster_as.h>``:

.. code:: hlsl

  #include <vk/nv/cluster_as.h>

  // committed intersection
  clusterId = vk::nv::RayQueryGetCommittedIntersectionClusterId(query);
  // candidate intersection, inside the Proceed() loop
  clusterId = vk::nv::RayQueryGetCandidateIntersectionClusterId(query);
  // raw form: the selector is spelled out
  clusterId = vk::nv::RayQueryGetIntersectionClusterId(
      query, vk::nv::IntersectionCommitted);

and lowers to ``OpRayQueryGetIntersectionClusterIdNV`` (5345):

.. code:: spirv

  OpCapability RayTracingClusterAccelerationStructureNV ; 5437
  OpExtension "SPV_NV_cluster_acceleration_structure"
  ...
  %clusterId = OpRayQueryGetIntersectionClusterIdNV %uint %query %uint_1

The operands are the ray query object and the intersection - the same shape as
``OpRayQueryGetIntersectionInstanceIdKHR`` - and the result is a 32-bit unsigned
integer. The intersection operand is 0 for the candidate intersection and 1 for the
committed one, and it **must be a constant**: SPIRV-Tools rejects a module whose
intersection operand is not a constant 32-bit integer ("expected Intersection ID to
be a constant 32-bit int scalar"). That is why the header exports the two selector
values (``vk::nv::IntersectionCandidate``, ``vk::nv::IntersectionCommitted``) and
the two wrappers instead of taking a ``bool``, and why the raw form takes the
selector as a separate argument.

**The accessors are not ``RayQuery`` methods.** Every ``RayQuery`` method is
declared once and has to work for both backends, and DXR has no cluster
acceleration structures: a cluster-ID method would need a DXIL lowering that cannot
exist. Splitting the surface into a header-only free function keeps the shared
method table, Sema and the DXIL backend untouched. It also means there is no DXIL
path at all: a DXIL compile ignores the ``vk::`` attributes on the declaration
(``-Wignored-attributes``) and leaves an accessor with no definition, which is an
error in a non-library profile and an unresolved external in a library build.

The extension is **not** enabled by default. A module that reads a cluster ID
declares the ``RayTracingClusterAccelerationStructureNV`` capability and
``OpExtension "SPV_NV_cluster_acceleration_structure"``, which a driver without
``VK_NV_cluster_acceleration_structure`` rejects, so the accessors are only
accepted with ``-fspv-extension=SPV_NV_cluster_acceleration_structure``. Without
that flag every call is a compile error instead of a module that declares an
extension the host never asked for, and a module that does not read a cluster ID is
unchanged - including one that includes the header. The capability and the
extension are emitted together from the instruction through the ordinary extension
registration path, so ``-fspv-extension`` can both select and refuse this one; they
are deliberately *not* written with ``[[vk::ext_capability]]`` /
``[[vk::ext_extension]]`` on the header declaration, because those attributes write
the extension string without consulting the extension manager and no allow-list
could reject them.

Limitations:

* **A cluster ID is only defined for clustered geometry.** The instruction is
  always encodable, but for an acceleration structure built from ordinary
  triangles the value it returns is undefined. The compiler cannot tell the two
  apart, so the shader author has to know how the acceleration structure was
  built.
* The host must enable
  ``VkPhysicalDeviceClusterAccelerationStructureFeaturesNV::clusterAccelerationStructure``,
  build the cluster level (``vkGetClusterAccelerationStructureBuildSizesNV`` and
  ``vkCmdBuildClusterAccelerationStructureIndirectNV``) and reference it from the
  ray traced scene. The compiler cannot check any of that.
* Ray queries already require Vulkan 1.2 / ``SPV_KHR_ray_query``; this extension
  adds no additional target-environment requirement.
* ``-fspv-extension`` is an allow-list, so a shader that passes it has to keep
  naming ``SPV_KHR_ray_query`` as well:
  ``-fspv-extension=SPV_KHR_ray_query -fspv-extension=SPV_NV_cluster_acceleration_structure``.
  Naming only the cluster extension is not an error at the extension level, but the
  ray query itself then stops being permitted and the module fails to validate.

See ``examples/spirv-extensions/nv-cluster-acceleration-structure.hlsl`` for a
self-contained example and
``tools/clang/test/CodeGenSPIRV/vk.nv-cluster-as*.hlsl`` for the tests that pin the
capability, the extension, the instruction with both intersection selectors, the
unchanged off path, the survival of the accessor through spirv-opt and the
diagnostic for a missing ``-fspv-extension``.

Linear swept spheres
~~~~~~~~~~~~~~~~~~~~

``VK_NV_ray_tracing_linear_swept_spheres`` adds two analytic geometry kinds to
ray tracing - spheres (particles, froxels, point clouds) and linear swept spheres
(hair, fur, curve primitives) - which are intersected analytically instead of
being tessellated into triangles. A ray query reports such a hit as a position and
a radius (a swept sphere additionally has a hit value that says where along the
segment the ray hit) instead of as a triangle or an AABB. Building such an
acceleration structure is a host operation; the shader-visible part of the
extension is the geometry of an intersection.

The accessors live in ``<vk/nv/linear_swept_spheres.h>``:

.. code:: hlsl

  #include <vk/nv/linear_swept_spheres.h>

  // committed intersection
  float3 center = vk::nv::RayQueryGetCommittedIntersectionSpherePosition(query);
  float  radius = vk::nv::RayQueryGetCommittedIntersectionSphereRadius(query);
  bool   sphere = vk::nv::RayQueryIsCommittedSphereHit(query);

  // candidate intersection, inside the Proceed() loop
  float value = vk::nv::RayQueryGetCandidateIntersectionLSSHitValue(query);
  bool  swept = vk::nv::RayQueryIsCandidateLSSHit(query);

  // raw form: the selector is spelled out
  center = vk::nv::RayQueryGetIntersectionSpherePosition(
      query, vk::nv::SphereIntersectionCommitted);

and lower to

.. code:: spirv

  OpCapability RayTracingSpheresGeometryNV            ; 5418
  OpExtension "SPV_NV_linear_swept_spheres"
  ...
  %center = OpRayQueryGetIntersectionSpherePositionNV %v3float %query %uint_1
  %radius = OpRayQueryGetIntersectionSphereRadiusNV   %float   %query %uint_1
  %sphere = OpRayQueryIsSphereHitNV                   %bool    %query %uint_1

The operands are the ray query object and the intersection - the same shape as
``OpRayQueryGetIntersectionInstanceIdKHR`` - and the result types are fixed by the
extension: a 32-bit float 3-component vector for a position, a 32-bit float for a
radius or a hit value (``OpRayQueryGetIntersectionLSSHitValueNV``, 5431) and a
bool for the two predicates (``OpRayQueryIsSphereHitNV``, 5438, and
``OpRayQueryIsLSSHitNV``, 5439). SPIRV-Tools enforces them ("expected Result Type
to be 32-bit float 3-component vector type", ...), so a module with the wrong
result type is invalid rather than merely surprising. The intersection operand is
0 for the candidate intersection and 1 for the committed one, and it is a constant
32-bit integer; the header therefore exports the two selector values
(``vk::nv::SphereIntersectionCandidate``, ``vk::nv::SphereIntersectionCommitted``)
and the candidate/committed wrappers instead of taking a ``bool``. The names are
spelled differently from ``vk::nv::IntersectionCandidate`` /
``IntersectionCommitted`` in ``<vk/nv/cluster_as.h>`` on purpose: the two headers
share the ``vk::nv`` namespace, so identical names would be a redefinition in a
shader that includes both.

Unlike the triangle/AABB getters, the vendored SPIRV-Tools does not verify the
constant requirement for these opcodes (its ``ValidateIntersectionId`` check is
only wired into the ``SPV_KHR_ray_query`` getters), so the selector is a
specification requirement that the header API shape enforces by offering the
wrappers rather than a diagnostic that the compiler or the validator emits.

**Two capabilities, selected per instruction.** The extension defines
``RayTracingSpheresGeometryNV`` (5418) for the sphere accessors and
``RayTracingLinearSweptSpheresGeometryNV`` (5419) for the linear-swept-sphere
ones, because
``VkPhysicalDeviceRayTracingLinearSweptSpheresFeaturesNV::spheres`` and
``::linearSweptSpheres`` are independent device features. The capability is
therefore chosen from the instruction that is emitted, not from the extension: a
shader that only reads sphere parameters declares only
``RayTracingSpheresGeometryNV`` and stays loadable on a device that does not
enable ``linearSweptSpheres``. Only one of the two is declared per module unless
the shader reads both kinds;
``tools/clang/test/CodeGenSPIRV/vk.nv-swept-spheres.hlsl`` and
``vk.nv-swept-spheres-lss.hlsl`` assert the two directions separately and each
one asserts the absence of the other capability.

**The accessors are not ``RayQuery`` methods.** Every ``RayQuery`` method is
declared once and has to work for both backends, and DXR has no sphere geometry: a
sphere accessor would need a DXIL lowering that cannot exist. Splitting the
surface into a header-only free function keeps the shared method table, Sema and
the DXIL backend untouched. It also means there is no DXIL path at all: a DXIL
compile ignores the ``vk::`` attributes on the declaration
(``-Wignored-attributes``) and leaves an accessor with no definition, which is an
error in a non-library profile and an unresolved external in a library build.

**Branch on the predicate, not on the intersection type.** DXR has no sphere
intersection type, so ``RayQuery::GetCandidateType()`` (and the committed status)
keep reporting the triangle/AABB answer for sphere geometry - the reported type is
implementation-defined. ``OpRayQueryIsSphereHitNV`` / ``OpRayQueryIsLSSHitNV`` is
the extension's own answer, is false for every other geometry kind, and is the
portable way to decide whether the other accessors mean anything.

The extension is **not** enabled by default. A module that reads sphere geometry
declares a ``RayTracing*SpheresGeometryNV`` capability and
``OpExtension "SPV_NV_linear_swept_spheres"``, which a driver without
``VK_NV_ray_tracing_linear_swept_spheres`` rejects, so the accessors are only
accepted with ``-fspv-extension=SPV_NV_linear_swept_spheres``. Without that flag
every call is a compile error instead of a module that declares an extension the
host never asked for, and a module that does not touch sphere geometry is
unchanged - including one that includes the header. The capability and the
extension are emitted together from the instruction through the ordinary extension
registration path, so ``-fspv-extension`` can both select and refuse this one; they
are deliberately *not* written with ``[[vk::ext_capability]]`` /
``[[vk::ext_extension]]`` on the header declarations, because those attributes
write the capability and the extension string without consulting the extension
manager and no allow-list could reject them.

Limitations:

* **The values are only defined for sphere geometry.** The instructions are
  always encodable, but for an acceleration structure built from triangles or
  AABBs the position and the radius are undefined and the predicate is false. The
  compiler cannot tell the two apart, so the shader author has to know how the
  acceleration structure was built.
* The host must enable
  ``VkPhysicalDeviceRayTracingLinearSweptSpheresFeaturesNV::spheres`` (or
  ``::linearSweptSpheres`` for swept geometry) and build the acceleration
  structure with ``VK_GEOMETRY_TYPE_SPHERES_NV`` geometry descriptions
  (``VkAccelerationStructureGeometrySpheresDataNV`` /
  ``VkAccelerationStructureGeometryLinearSweptSpheresDataNV``). The compiler
  cannot check any of that.
* Ray queries already require Vulkan 1.2 / ``SPV_KHR_ray_query``; this extension
  adds no additional target-environment requirement. ``-fspv-extension`` is an
  allow-list, so a shader that passes it has to keep naming ``SPV_KHR_ray_query``
  as well:
  ``-fspv-extension=SPV_KHR_ray_query -fspv-extension=SPV_NV_linear_swept_spheres``.
  Naming only the sphere extension is not an error at the extension level, but the
  ray query itself then stops being permitted and the module fails to validate.
* ``OpRayQueryGetIntersectionLSSPositionsNV`` (5429, a 2-element array of float3)
  and ``OpRayQueryGetIntersectionLSSRadiiNV`` (5430, a 2-element array of float)
  are not exposed yet. An accessor has to be a function template to work with any
  ``RayQuery<flags>``, and this front end rejects array return types in a function
  template (``Sema::CheckFunctionReturnType`` does not carry the HLSL
  array-return exception that the declarator path has), so the two
  linear-swept-sphere accessors whose result is an array cannot be declared from
  the header. The sphere accessors and the scalar linear-swept-sphere accessors
  are unaffected.
* The hit object half of the extension (``OpHitObjectGetSpherePositionNV``, 5432,
  and the rest) is not exposed: it needs ``SPV_EXT_shader_invocation_reorder``
  support in the backend first.

See ``examples/spirv-extensions/nv-linear-swept-spheres.hlsl`` for a
self-contained example and
``tools/clang/test/CodeGenSPIRV/vk.nv-swept-spheres*.hlsl`` for the tests that pin
the two capabilities and the extension, the three sphere instructions with their
result types and both intersection selectors, the linear-swept-sphere half, the
unchanged off path, the survival of the accessors through spirv-opt and the
diagnostic for a missing ``-fspv-extension``.

Dynamic image offsets and signed remainder
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

``VK_KHR_maintenance8`` is a Vulkan maintenance extension - one feature bit,
``VkPhysicalDeviceMaintenance8FeaturesKHR::maintenance8``, covering a collection
of small corrections. Two of its items are visible to a SPIR-V module, and DXC
already emits the encoding they describe:

* **Dynamic image offsets.** The optional ``offset`` argument of the texture
  sampling and gather methods is a compile-time constant in most HLSL, and DXC
  then emits the ``ConstOffset`` image operand. When it is *not* a constant, DXC
  emits ``Offset`` instead: ``ConstOffset`` requires a literal, so a computed
  offset has no other encoding. Before maintenance8 the Vulkan SPIR-V environment
  permitted ``Offset`` only on the gather operations, so the sampling forms were
  restricted to constant offsets; maintenance8 extends it to the sampling, fetch
  and read/write operations. The ``Offset`` and ``ConstOffset`` enumerants are
  ``0x0010`` and ``0x0008``, and the mask is a single word, so which one is
  present is the whole question. Both enumerants require the
  ``ImageGatherExtended`` capability, which DXC declares when it emits them.
  ``.Load()`` is the exception on the HLSL side: it rejects a non-constant offset
  with ``Offsets to texture access operations must be immediate values`` before
  any SPIR-V is produced, so ``OpImageFetch`` never carries a dynamic ``Offset``.

* **Signed remainder.** HLSL ``%`` on signed integers is truncating remainder, so
  the sign of a non-zero result follows the dividend. DXC therefore translates it
  to ``OpSRem``, never to ``OpSMod``, which takes the sign from the divisor; the
  same applies at 64-bit width and to ``/`` (``OpSDiv``). Before maintenance8 the
  Vulkan environment said the result of ``OpSRem`` and ``OpSMod`` is undefined if
  either operand is negative; maintenance8 adopts the SPIR-V definition, which is
  the one HLSL relies on.

Neither item is module surface, so **nothing is emitted for maintenance8**: the
extension adds no instruction, no capability, no ``OpExtension`` string and no new
target environment. There is no ``SPV_KHR_maintenance8`` in the Khronos SPIR-V
registry, and ``-fspv-extension=SPV_KHR_maintenance8`` is consequently an
``unknown SPIR-V extension`` error rather than a switch; there is no
``vulkan1.4`` in the ``-fspv-target-env`` list either, and the relaxation is
available to a Vulkan 1.1/1.2/1.3 device that enables the extension, so it is a
property of the device rather than of the target environment. What the rule
governs is validation, and DXC validates with the relaxation in effect
(``SetAllowOffsetTextureOperand`` in ``SpirvEmitter::spirvToolsValidate``):
without it, spirv-val applied the pre-maintenance8 rule and rejected the very
module DXC had just generated from legal HLSL with
``[VUID-RuntimeSpirv-Offset-10213] Image Operand Offset can only be used with
OpImage*Gather operations``.

In HLSL nothing has to change - no intrinsic, no attribute, no define - because
the encoding was always the maintenance8-correct one. What the shader author has
to arrange is the host side: Vulkan 1.4, or Vulkan 1.1+ with
``VK_KHR_maintenance8`` enabled at ``vkCreateDevice``, and the ``maintenance8``
feature bit set. Without it, a pipeline whose shader uses ``Offset`` on a sampling
instruction is rejected, and remainder results for negative operands are
undefined. The compiler cannot check either condition, since it does not know
which device will run the shader.

See ``examples/spirv-extensions/khr-maintenance8.hlsl`` for a self-contained
example and ``tools/clang/test/CodeGenSPIRV/maintenance8.*.hlsl`` for the tests
that pin the encoding of both items.

Narrow integer bitwise operations
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

``VK_KHR_maintenance9`` is likewise a Vulkan maintenance extension - one feature
bit, ``VkPhysicalDeviceMaintenance9FeaturesKHR::maintenance9`` - and the item
that concerns DXC is a single relaxation of the Vulkan SPIR-V *environment*:
the rule (``VUID-RuntimeSpirv-None-10824``, "Expected 32-bit int type for Base
operand") that required the Base operand of exactly five instructions to be a
32-bit integer. Those five instructions are ``OpBitReverse``, ``OpBitCount``,
``OpBitFieldInsert``, ``OpBitFieldSExtract`` and ``OpBitFieldUExtract``. With
the feature enabled any integer width is allowed, so 8-, 16- and 64-bit operands
become legal. No other bitwise instruction is affected: ``OpBitwiseAnd``/``Or``/
``Xor``/``Not`` and the shift instructions were never width-restricted, and DXC
already emits them at the operand's natural width.

Like maintenance8, the relaxation is not module surface: there is no
``SPV_KHR_maintenance9`` in the Khronos SPIR-V registry, so
``-fspv-extension=SPV_KHR_maintenance9`` is an ``unknown SPIR-V extension``
error, and nothing is added to the module header - no ``OpExtension``, no
``OpCapability``. Unlike maintenance8, though, the emitted *instruction stream*
changes, because the widths the rule rejected can now be used directly. DXC
therefore does not assume the feature: ``-fspv-enable-maintenance9`` opts in.

``-fspv-enable-maintenance9`` (default off, so a module compiled without it is
byte-for-byte what it was before) selects the native encodings:

.. code:: hlsl

    // Emitted only with -fspv-enable-maintenance9.
    uint16_t r16 = reversebits(v16);  // OpBitReverse %ushort %v16
    uint64_t r64 = reversebits(v64);  // OpBitReverse %ulong  %v64
    uint c16 = countbits(v16);        // OpBitCount %uint %v16
    uint c64 = countbits(v64);        // OpBitCount %uint %v64

Without the flag the same expressions produce the pre-maintenance9 emulations,
which are still valid for every device and are the only portable form:

.. code:: hlsl

    // reversebits on 16-bit: widen, reverse, shift right by 16, truncate.
    %a = OpUConvert %uint   %v16
    %b = OpBitReverse %uint %a
    %c = OpShiftRightLogical %uint %b %uint_16
    %d = OpUConvert %ushort %c

    // reversebits on 64-bit: reverse both 32-bit halves and recombine (9
    // instructions instead of 1).
    // countbits on 16-bit: widen, then count (2 instructions instead of 1).
    // countbits on 64-bit: count both halves and add (6 instead of 1).

This is deliberately not tied to ``-fspv-target-env``: the relaxation depends on
a device feature, not on the SPIR-V version, so a Vulkan 1.1/1.2/1.3 device that
enables the extension may use it, and DXC's ``-fspv-target-env`` list stops at
``vulkan1.3`` anyway. There is consequently no target environment at which DXC
could infer the relaxation by itself.

What stays emulated, and why:

* **8-bit** widths are unlocked by the extension - the validator accepts
  ``OpBitReverse %uchar`` and friends once the feature is declared, and inline
  SPIR-V can use them with ``-fspv-enable-maintenance9``. HLSL's ``reversebits``
  and ``countbits`` cannot reach them, though: the Sema overload set for these
  intrinsics (``any_int``) covers 16-, 32- and 64-bit integers only, so an
  ``int8_t``/``uint8_t`` argument is promoted to ``int`` before the intrinsic
  and the operation is performed on 32 bits. To use the 8-bit forms from HLSL,
  declare the instruction with ``[[vk::ext_instruction]]`` (see
  ``tools/clang/test/CodeGenSPIRV/maintenance9.bitwise.int8.hlsl``).
* ``firstbitlow``/``firstbithigh`` keep their 32-bit restriction. That limit
  comes from ``GLSL.std.450`` (``FindILsb``/``FindSMsb``/``FindUMsb`` have no
  16-bit form), not from the Vulkan rule maintenance9 relaxes, so the extension
  does not help.
* ``OpBitFieldInsert``/``OpBitFieldSExtract``/``OpBitFieldUExtract`` are emitted
  directly at 32 bits and emulated otherwise, but the emulation is not on any
  path maintenance9 unblocks: ``bfi``/``ubfe``/``ibfe`` are not HLSL intrinsics
  for SPIR-V, and HLSL struct bitfields always pack into a 32-bit member, so the
  emulated bitfield paths are not reached from HLSL today.

Two things the compiler cannot check. First, DXC always validates the module it
just produced, and it does so under the rule it emitted for:
``SpirvEmitter::spirvToolsValidate`` calls
``SetAllowVulkan32BitBitwise(spirvOptions.enableMaintenance9)``, so a module
compiled with the flag is validated as a maintenance9 module and one compiled
without it is validated as before - a mismatch is impossible, but the flag
itself is an unverifiable promise. Second, the host side: the application must
enable ``VK_KHR_maintenance9`` at ``vkCreateDevice`` and set
``VkPhysicalDeviceMaintenance9FeaturesKHR::maintenance9`` to ``VK_TRUE``.
Without it a pipeline whose shader contains a non-32-bit Base operand is
rejected at pipeline creation.

See ``examples/spirv-extensions/khr-maintenance9.hlsl`` for a self-contained
example and ``tools/clang/test/CodeGenSPIRV/maintenance9.*.hlsl`` for the tests
that pin both the flagged and the unflagged encodings.

BFloat16
~~~~~~~~

``SPV_KHR_bfloat16`` adds ``bfloat16_t``, a 16-bit floating point type with the
``BFloat16KHR`` encoding: IEEE 754 binary32's 8-bit exponent with the significand
truncated to 7 stored bits. It has ``float``'s range and roughly three significant
decimal digits, which is what a machine-learning storage type wants.
``bfloat16_t`` is primarily a storage and conversion type - the extension defines
no arithmetic, comparison or bitwise operation for it - and only the two optional
compute modes described below operate on it directly.

``bfloat16_t`` is a real HLSL builtin type, so ``bfloat16_t2`` through
``bfloat16_t4``, ``bfloat16_t2x2``, and structs and arrays containing it all work.
It is available only when compiling with ``-spirv`` (the DXIL target rejects it),
it requires HLSL 2018 or later, and it does not require
``-enable-16bit-types``: the type is always 16 bits wide. It lowers to an
``OpTypeFloat 16`` that carries the ``BFloat16KHR`` encoding operand, and the
module declares ``OpCapability BFloat16TypeKHR`` (5116) together with
``OpExtension "SPV_KHR_bfloat16"``:

::

    OpCapability BFloat16TypeKHR
    OpExtension "SPV_KHR_bfloat16"
    %bfloat16 = OpTypeFloat 16 BFloat16KHR

``bfloat16_t`` is *not* ``float16_t``. The ``Float16`` capability and the
16-bit stage I/O capabilities (``StorageInputOutput16``) are never requested on
its behalf, and no implicit conversion exists between ``bfloat16_t`` and
``float16_t`` in either direction. When ``-enable-16bit-types`` is given,
``bfloat16_t`` keeps its own identity rather than aliasing ``float16_t``, and it
does not change what ``half`` or ``min16float`` lower to.

The only implicit conversion involving ``bfloat16_t`` is widening to
``float``/``float64``, for scalars, vectors and matrices alike, which lowers to
``OpFConvert``:

.. code:: hlsl

    bfloat16_t b = 1.5;
    float f = b;                // OpFConvert %float
    bfloat16_t2 v = bfloat16_t2(b, b);
    float2 vf = v;              // OpFConvert %v2float

Every other conversion needs an explicit constructor: implicit narrowing from
``float``, conversions to and from the integer types, conversions to and from
``float16_t``, and conversions to and from ``bool`` are compile errors. Mixed
operands follow the same rule: ``bfloat16_t`` combined with ``float16_t`` is a
type mismatch, and since no arithmetic is defined for the type an expression such
as ``b * 2.0`` has to be written ``float(b) * 2.0``.

``VK_KHR_shader_bfloat16`` does not allow the ``BFloat16KHR`` encoding in the
``Input`` and ``Output`` storage classes, so ``bfloat16_t`` - including vectors,
matrices and structs containing it - cannot appear in a shader stage interface.
DXC rejects it there instead of emitting a module the validator would refuse:

::

    error: bfloat16_t is not supported in shader stage input/output: SPV_KHR_bfloat16
    does not allow the BFloat16KHR type in Input/Output storage classes

Pass values between stages as ``float`` and convert inside the shader.

``BFloat16DotProductKHR``
+++++++++++++++++++++++++

``dot()`` on ``bfloat16_t`` vector operands is the extension's bfloat16 dot
product. It lowers to ``OpDot`` with a ``BFloat16KHR`` component type, and the
module adds ``OpCapability BFloat16DotProductKHR`` (5117) on top of
``BFloat16TypeKHR``:

.. code:: hlsl

    bfloat16_t3 a = bfloat16_t3(1.0, 2.0, 3.0);
    bfloat16_t3 b = bfloat16_t3(4.0, 5.0, 6.0);
    bfloat16_t d = dot(a, b); // %d = OpDot %bfloat16 %a %b

Note that this is ``OpDot``, not ``OpSDot``/``OpUDot``: the latter two belong to
``SPV_KHR_integer_dot_product`` and require an integer result type, so a
bfloat16 component cannot be encoded with them. A ``float`` destination still
compiles and widens the result (``float f = dot(a, b)`` emits ``OpDot %bfloat16``
followed by ``OpFConvert %float``), but the result is rounded to bfloat16, so
write ``dot(float3(a), float3(b))`` if the full float precision of a converted
dot product is wanted. Mixing ``bfloat16_t`` with any other component type in one
``dot()`` call is an error rather than a silent widening. A scalar
``dot(bfloat16_t, bfloat16_t)`` is rejected as well, because the extension defines
``BFloat16DotProductKHR`` only for vectors.

``BFloat16CooperativeMatrixKHR``
++++++++++++++++++++++++++++++++

``vk::khr::CooperativeMatrix<bfloat16_t, scope, rows, columns, use>`` from
``<vk/khr/cooperative_matrix.h>`` is a cooperative matrix whose
``OpTypeCooperativeMatrixKHR`` takes an ``OpTypeFloat 16 BFloat16KHR`` component
type. Such a module declares ``OpCapability BFloat16CooperativeMatrixKHR`` (5118)
in addition to the ``CooperativeMatrixKHR`` and ``BFloat16TypeKHR`` capabilities
that are already required, and both the ``SPV_KHR_cooperative_matrix`` and
``SPV_KHR_bfloat16`` extensions:

::

    OpCapability BFloat16TypeKHR
    OpCapability BFloat16CooperativeMatrixKHR
    OpCapability CooperativeMatrixKHR
    OpExtension "SPV_KHR_bfloat16"
    OpExtension "SPV_KHR_cooperative_matrix"
    %bfloat16 = OpTypeFloat 16 BFloat16KHR
    %spirvIntrinsicType = OpTypeCooperativeMatrixKHR %bfloat16 %uint_3 %uint_16 %uint_8 %uint_0

Only the operations the extension allows can be applied to it: multiply-add
(``cooperativeMatrixMultiplyAdd``), load, store, ``Splat``, ``Get``/``Set`` and
``GetLength``. The element-wise arithmetic and comparison operators of
``vk::khr::CooperativeMatrix`` are integer/float only, so convert through
``float`` for those.

``VK_KHR_shader_bfloat16`` is a device extension whose
``VkPhysicalDeviceShaderBfloat16FeaturesKHR`` struct carries one feature bit per
capability: ``shaderBFloat16Type``, ``shaderBFloat16DotProduct`` and
``shaderBFloat16CooperativeMatrix``. ``shaderBFloat16Type`` must be supported,
``shaderBFloat16CooperativeMatrix`` requires ``VK_KHR_cooperative_matrix``, and
at least one of ``shaderBFloat16DotProduct`` and
``shaderBFloat16CooperativeMatrix`` must be supported. The relevant bits have to
be enabled at ``vkCreateDevice`` for the capability to be legal, and a
cooperative matrix's supported component types and shapes have to be queried with
``vkGetPhysicalDeviceCooperativeMatrixPropertiesKHR``. The compiler cannot check
any of that.

See ``examples/spirv-extensions/khr-bfloat16.hlsl`` for a self-contained example
and ``tools/clang/test/CodeGenSPIRV/bfloat16.*.hlsl`` for the tests that pin the
encodings and the diagnostics.

Float8
~~~~~~
``SPV_EXT_float8`` adds the two OCP 8-bit floating point formats as real HLSL
builtin types:

``float8_e4m3_t``
  1 sign bit, 4 exponent bits (bias 7), 3 mantissa bits. Normal range
  ``2^-6`` (0.015625) to 448, subnormals down to ``2^-9``. There is no infinity:
  the only NaN patterns are 0x7F and 0xFF, and a value above 448 saturates to
  448. About three significant decimal digits.

``float8_e5m2_t``
  1 sign bit, 5 exponent bits (bias 15), 2 mantissa bits. Normal range ``2^-14``
  to 57344, subnormals down to ``2^-16``, with infinities and NaNs like IEEE.
  The exponent range of ``half`` with two significant decimal digits.

E4M3 is the format for weights and activations whose scale is bounded; E5M2 keeps
half's range for gradients. Both are SPIR-V only, both require HLSL 2018 or later,
and neither needs ``-enable-16bit-types``: the types are always 8 bits wide.
``float8_e4m3_t2`` through ``float8_e4m3_t4``, ``float8_e4m3_t2x2``,
``float8_e5m2_t2`` .. ``float8_e5m2_t4``, and structs and arrays containing them
all work.

The type lowers to ``OpTypeFloat 8`` with the ``Float8E4M3EXT`` (4214) or
``Float8E5M2EXT`` (4215) encoding operand, declares ``OpCapability Float8EXT``
(4212) and emits ``OpExtension "SPV_EXT_float8"`` once per module:

.. code-block:: text

    OpCapability Float8EXT
    OpExtension "SPV_EXT_float8"
    %float8_e4m3 = OpTypeFloat 8 Float8E4M3EXT
    %float8_e5m2 = OpTypeFloat 8 Float8E5M2EXT

``Float8CooperativeMatrixEXT`` (4213) is not implemented, so it is never emitted.
Using a float8 type as a cooperative matrix component type is rejected: the
``vk::khr::CooperativeMatrix`` header probes its component type with an
arithmetic expression, and SPV_EXT_float8 defines no arithmetic, so the
instantiation reports the "operator is not supported for float8_e4m3_t or
float8_e5m2_t" error at the header's probe. Cooperative-matrix float8 needs its
own capability emission and a saturating multiply-accumulate model; treat it as a
separate landing.

``float8_e4m3_t`` and ``float8_e5m2_t`` are *not* 8-bit integers and *not*
``half``. No ``Int8`` and no 8-bit storage capability is requested on their
behalf, and no ``Float16`` capability is requested either. The two formats are
distinct types with distinct encodings: they never convert into each other
implicitly, so mixing E4M3 and E5M2 in one expression is a type mismatch instead
of a silent rounding.

The extension defines no arithmetic, comparison or bitwise operation on the
formats. They are storage and conversion types: a value can be loaded, stored,
composited, selected, kept in a constant, and converted with ``OpFConvert`` - and
that is all. Any other operation on a float8 value is rejected by the front end:

.. code-block:: text

    error: operator is not supported for float8_e4m3_t or float8_e5m2_t;
    SPV_EXT_float8 defines no arithmetic, comparison or bitwise operations -
    convert the operand to float or double explicitly

The conversion model is widening only. A float8 value converts implicitly to
``float`` and ``float64`` (scalars, vectors and matrices), and numeric literals
convert into a float8 type implicitly. Every other conversion requires an
explicit constructor:

* narrowing from ``float``/``double``/``half``,
* to or from integer types,
* to or from ``bfloat16_t`` or ``float16_t``,
* between ``float8_e4m3_t`` and ``float8_e5m2_t``,
* implicit narrowing is a plain initialization error: ``float8_e4m3_t x = f;``
  reports ``error: cannot initialize a variable of type 'float8_e4m3_t' with an
  lvalue of type 'float'``.

No conversion to or from ``bool`` exists, implicitly or explicitly.

A literal mixed into an arithmetic expression with a float8 operand takes the
float8 kind, so ``a + 1.0`` is rejected like any other float8 arithmetic and
has to be written ``float(a) + 1.0``. ``a + f`` with a ``float`` operand widens
and is accepted.

Because a float8 value is 8 bits wide and a wider float is not, an implicit
widening still emits ``OpFConvert``:

.. code-block:: hlsl

    float8_e4m3_t w = float8_e4m3_t(1.5);   // explicit narrowing, OpFConvert
    float f = w;                            // implicit widening,   OpFConvert
    float8_e5m2_t g = float8_e5m2_t(w);     // format change,       OpFConvert

Values that are out of range saturate to the largest finite value of the format
(448 for E4M3, 57344 for E5M2) or become infinity where the format has one
(E5M2), following the OCP definition of the encodings. Constant initializers are
rounded by the same rules, so ``float8_e4m3_t(1000.0)`` is the constant 448., and
because that is the documented result rather than a mistake the usual
``-Wconst-expr-overflow`` warning is not produced for a float8 destination.

Storage follows the 8-bit size: an element occupies one byte with a one-byte
alignment, so ``StructuredBuffer<float8_e4m3_t>`` has an ``ArrayStride`` of 1 and
a struct packs its float8 members at the natural offsets.

``VK_EXT_shader_float8`` does not allow the ``Float8E4M3EXT`` and
``Float8E5M2EXT`` encodings in the ``Input`` and ``Output`` storage classes, so a
float8 type - including vectors, matrices and structs containing it - cannot be a
shader stage input or output:

.. code-block:: text

    error: float8_e4m3_t and float8_e5m2_t are not supported in shader stage
    input/output: SPV_EXT_float8 does not allow the Float8E4M3EXT or
    Float8E5M2EXT type in Input/Output storage classes

Pass the value between stages as ``float``.

``-fspv-extension=`` is an allow-list: with an explicit list that omits
``SPV_EXT_float8``, using either type fails with

.. code-block:: text

    error: SPIR-V extension 'SPV_EXT_float8' required for
    float8_e4m3_t/float8_e5m2_t type but not permitted to use

(see ``float8.extension.error.hlsl``).

``VK_EXT_shader_float8`` is a device extension. The application must enable it at
``vkCreateDevice`` and set
``VkPhysicalDeviceShaderFloat8FeaturesEXT::shaderFloat8`` to ``VK_TRUE``; the
feature has to be queried with ``vkGetPhysicalDeviceFeatures2``. A driver without
the feature rejects a module that declares ``Float8EXT``, and the compiler cannot
check the host half.

See ``examples/spirv-extensions/ext-shader-float8.hlsl`` for a self-contained
example and ``tools/clang/test/CodeGenSPIRV/float8.*.hlsl`` for the tests that pin
both encodings, the conversions, the storage layout, the two diagnostics and the
optimizer-survival path.

Non-uniform push constant indexing
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
``VK_KHR_maintenance12`` is a Vulkan maintenance extension - one device
extension, revision 1 (2026-03-25) - and its first item is "non-uniform indexing
of values within a variable with a ``PushConstant`` storage class". Before it, a
push constant subscript had to be dynamically uniform even in a shader that was
already free to index a descriptor array non-uniformly.

The permission is not module surface and adds nothing to the module header: no
instruction, no capability, no ``OpExtension`` string. The SPIR-V side already
has the one thing it needs - the ``NonUniform`` decoration (5300) on the access
chain whose ``Array Index`` is divergent, plus the ``ShaderNonUniform``
capability (5301) that legalises the decoration, both defined by
``SPV_EXT_descriptor_indexing`` in modules that do not use SPIR-V 1.5 or later.
There is no ``SPV_KHR_maintenance12`` in the Khronos SPIR-V registry (checked
against the vendored grammar, ``external/SPIRV-Headers`` v2026.08.0, whose only
"maintenance" names are ``SPV_EXT_cooperative_matrix_maintenance1``), so
``-fspv-extension=SPV_KHR_maintenance12`` is an ``unknown SPIR-V extension``
error rather than a switch, and there is no new target environment either: the
relaxation belongs to a device that enables the extension, so it is a property of
the device rather than of ``-fspv-target-env``.

DXC needs no switch and has none. The decoration machinery a push constant needs
is the same one descriptor indexing already uses, and it is generic:
``NonUniformResourceIndex()`` lowers to an ``OpCopyObject`` marked ``NonUniform``
(``SpirvEmitter::processIntrinsicNonUniformResourceIndex``) and
``NonUniformVisitor::visit(SpirvAccessChain)`` propagates the marking to every
access chain built from it - whatever storage class the chain is in, at whatever
member depth - and on to the load and the instructions that consume it. There is
deliberately no push-constant-specific code in ``NonUniformVisitor``: the marking
rule is per value, not per variable, and a second copy of it would drift. What
matters for the feature is only that the decoration lands on the *access chain*
and not merely on the loaded value, which is what
``tools/clang/test/CodeGenSPIRV/maintenance12.*.hlsl`` pins in both directions:

.. code:: hlsl

  [[vk::push_constant]] PushData pc;

  // Divergent index: decorated. Lowered to
  //   %copy  = OpCopyObject %uint %masked
  //   %chain = OpAccessChain %_ptr_PushConstant_mat4v4float %pc %int_1 %copy %int_0
  //   OpDecorate %copy NonUniform
  //   OpDecorate %chain NonUniform
  // plus OpCapability ShaderNonUniform.
  float4x4 m = pc.materials[NonUniformResourceIndex(tid.x)].transform;

  // Uniform index: nothing is decorated, and the module keeps no
  // ShaderNonUniform capability and no SPV_EXT_descriptor_indexing extension.
  float4 t = pc.materials[0].tint;

HLSL has no uniformity inference, and DXC does not guess: an index that is
divergent in fact but never wrapped in ``NonUniformResourceIndex()`` produces no
decoration, and the module then claims the index is dynamically uniform. That is
the one thing the shader author has to get right, and the marking has to be
written at the indexing site - a value parked in a ``Function``-storage variable
carries the marking with it only after the optimizer promotes the variable to an
SSA value, which is why the ``-fcgl`` module of such a shader can look unmarked.
``NonUniformResourceIndex()`` is not restricted to resource handles: its Sema
check accepts a plain ``uint``, so a push constant subscript is in range.

Two things the compiler cannot check. First, whether the device permits it: the
application must enable ``VK_KHR_maintenance12`` at ``vkCreateDevice`` and enable
the feature bits it exposes for the items in use
(``VkPhysicalDeviceMaintenance12FeaturesKHR``, queried with
``vkGetPhysicalDeviceFeatures2`` and chained into ``VkDeviceCreateInfo::pNext``).
Without it the driver is entitled to assume the subscript is dynamically uniform
and the shader's behaviour is undefined. Second, the module itself: the shipped
SPIRV-Tools has no target-environment rule about ``NonUniform`` on a
``PushConstant`` access chain - there is no validator option for it, unlike the
maintenance8 and maintenance9 relaxations - so every ``-fspv-target-env`` DXC
accepts validates a module carrying the decoration, and the compiler has no state
on which to raise a diagnostic. Silent acceptance is therefore intentional here and is not a
correctness hole in the compiler: the module is valid SPIR-V, and whether the
values may be divergent is a host/device question.

See ``examples/spirv-extensions/khr-maintenance12.hlsl`` for a self-contained
example and ``tools/clang/test/CodeGenSPIRV/maintenance12.*.hlsl`` for the tests
that pin the decoration, its absence for uniform indices, the nested
struct-of-arrays shape, and its survival through spirv-opt.

Image gather modes
~~~~~~~~~~~~~~~~~~

``VK_QCOM_image_processing3`` adds ``OpImageGatherQCOM``: a texture gather whose
footprint is chosen by a *mode* operand instead of being fixed to the 2x2 quad
that ``OpImageGather`` (what ``Texture2D::Gather*`` lowers to) always reads. The
Adreno GPUs the extension was written for implement the four footprints as
dedicated instructions, so an upscaling or sharpening kernel that needs exactly
those taps gets one hardware gather instead of four taps or a gather reprogrammed
with ``ConstOffsets``:

* ``Gather4x1QCOM`` (0) - four horizontally adjacent texels: vectorised loads with
  linear cache locality, or a 4-tap horizontal kernel.
* ``GatherDQCOM`` (1) - the four cardinal neighbours around the coordinate (a
  diamond). With a point sample of the centre texel this is the 5-tap kernel of
  contrast adaptive sharpening.
* ``GatherH2QCOM`` (2) - two 2x1 pairs, one row above and one row below the
  coordinate.
* ``GatherV2QCOM`` (3) - two 1x2 pairs, one column left and one column right. With
  ``GatherH2QCOM`` and an ordinary 2x2 gather this builds the 12 taps of a
  separable upscaling filter.

The entry points live in ``<vk/qcom/image_processing3.h>``:

.. code:: hlsl

  #include <vk/qcom/image_processing3.h>

  vk::SampledTexture2D<float4> Input : register(t0);

  // one instruction, four texels: OpImageGatherQCOM %v4float %input %uv
  //                                  %int_0 %int_1   (component 0, mode 1)
  float4 neighbours = vk::qcom::ImageGatherD(Input, uv);

  // the fourth channel of four horizontally adjacent texels: the template
  // argument is the component, so this is %int_3 %int_0
  float4 alpha = vk::qcom::ImageGather4x1<3>(Input, uv);

  // arrayed image: three coordinate components, the third is the array layer
  float4 row = vk::qcom::ImageGatherH2Array(InputArray, float3(uv, layer));

The instruction is ``OpImageGatherQCOM`` (4545) with the operands ``(IdResultType,
IdResult, Sampled Image, Coordinate, Component, Mode [, Image Operands])``. The
result is a four-component vector of the image's sampled type, *Sampled Image*
must be an ``OpTypeSampledImage`` whose ``OpTypeImage`` has a ``Dim`` of 2D and
``MS = 0``, the coordinate is a floating-point vector, *Component* selects the
channel gathered from all four texels and *Mode* the footprint. Component and Mode
are ids but must be 32-bit integer **constants**: SPIRV-Tools rejects a
non-constant component in a Vulkan environment, and the mode is what selects the
capability. That is why the header takes the component as a template argument and
bakes the mode into one declaration per mode instead of exposing either as an
ordinary parameter, and why the two trailing parameters of each declaration (whose
defaults carry those constants into the instruction) are not part of the surface.
Passing a runtime value as the component is possible but defeats that guarantee:
the module is then invalid for Vulkan and SPIRV-Tools rejects it ("Expected
Component Operand to be a const object for Vulkan environment"), which is the only
diagnostic DXC gives for it.

**Two capabilities, selected per call shape.** ``ImageGatherLinearQCOM`` (4543)
covers ``Gather4x1QCOM`` and ``ImageGatherExtendedModesQCOM`` (4544) covers
``GatherDQCOM``, ``GatherH2QCOM`` and ``GatherV2QCOM``; both are introduced by the
same extension and a module declares only the ones its modes need:

.. code:: hlsl

  // ImageGatherLinearQCOM (4543) + OpExtension "SPV_QCOM_image_processing3"
  float4 row = vk::qcom::ImageGather4x1(Input, uv);

  // ImageGatherExtendedModesQCOM (4544) + the same OpExtension
  float4 diamond = vk::qcom::ImageGatherD(Input, uv);

The capability is picked in ``CapabilityVisitor`` from the *Mode* operand of the
instruction, not once for the extension, because the two Vulkan feature bits that
back them are independent: a shader that only uses the linear mode has to stay
acceptable on a device that does not enable the extended modes, and one capability
must never imply the other. A mode that cannot be resolved to a constant (a
specialization constant, say) declares both, which is a legal superset; SPIRV-Tools
only checks the pairing for a non-specialization constant. The extension itself is
emitted through the ordinary registration path as well, from the instruction
(``FeatureManager``/``CapabilityVisitor``) rather than through
``[[vk::ext_capability]]``/``[[vk::ext_extension]]`` on the header declarations,
which write the capability and the extension string unconditionally and would let a
shader bypass the allow-list.

The extension is **not** enabled by default. A module that gathers with one of the
modes declares the capability and ``OpExtension "SPV_QCOM_image_processing3"``,
which a driver without ``VK_QCOM_image_processing3`` rejects, so the entry points
are only accepted with ``-fspv-extension=SPV_QCOM_image_processing3``. Without that
flag every call is a compile error (``SPIR-V extension
'SPV_QCOM_image_processing3' required for OpImageGatherQCOM but not permitted to
use``) instead of a module that declares an extension the host never asked for, and
a shader that does not gather with one of the modes - including one that includes
the header - is unchanged.

Like the rest of the family, the extension requires **SPIR-V 1.4**, so the module
needs ``-fspv-target-env=vulkan1.1spirv1.4`` or a newer target environment. DXC
does not enforce that: the vendored SPIRV-Tools does not check the SPIR-V version an
extension requires, and a module below 1.4 that carries the extension is a
validation and driver question rather than a compile error here.

Limitations:

* **These are gathers, not filters.** No weights are applied, no derivatives are
  taken and the level of detail is the base level, exactly as for
  ``OpImageGather``. A kernel still does its own multiply-accumulate on the four
  returned texels.
* **The lane order depends on the mode**, and the four modes order their texels
  differently (the extension's instruction table draws the footprint of each),
  so the kernel has to read the lanes in the order its mode produces. The compiler
  cannot check that, and there is no execution coverage for this extension in the
  test suite.
* The image must already be a combined image sampler: ``vk::SampledTexture2D`` or
  ``vk::SampledTexture2DArray`` (an ``OpTypeSampledImage``). A ``Texture2D`` plus a
  separate ``SamplerState`` is not accepted, because whether an image and a sampler
  may be combined is a host decision and DXC would otherwise open-code
  ``OpSampledImage`` behind the shader author's back. Only ``Dim`` 2D images are
  covered, arrayed or not.
* The gather restrictions of the extension apply and are not diagnosed: no cube map
  views, no depth comparison (``OpImageDrefGather``), no ``ConstOffsets`` and no
  sparse residency. A mismatched image view is a validation or runtime problem, not
  a compile-time one.
* The host must enable the feature of the capability the mode declares -
  ``VkPhysicalDeviceImageProcessing3FeaturesQCOM::imageGatherLinear`` for
  ``Gather4x1QCOM``, ``::imageGatherExtendedModes`` for
  ``GatherDQCOM``/``H2``/``V2`` - on top of ``VK_QCOM_image_processing`` and create
  the combined image sampler as an image processing sampler
  (``VK_SAMPLER_CREATE_IMAGE_PROCESSING_BIT_QCOM``). The compiler cannot check any
  of that.
* This is a SPIR-V only surface: there is no DXIL instruction for a gather with a
  mode operand, and the ``vk::SampledTexture*`` types the entry points take only
  exist in a SPIR-V compile, so including the header in a DXIL compile fails on the
  type name (``no type named 'SampledTexture2D' in namespace 'vk'``).

See ``examples/spirv-extensions/qcom-image-processing3.hlsl`` for a self-contained
example (contrast adaptive sharpening with ``GatherDQCOM`` and a 4-tap horizontal
kernel with ``Gather4x1QCOM``) and
``tools/clang/test/CodeGenSPIRV/qcom.image-processing3*.hlsl`` for the tests that
pin the capability of each mode, the extension, the instruction with its result
type and operand order, the unchanged off path, the survival of the gathers through
spirv-opt, and the diagnostic for a missing ``-fspv-extension``.

Unsized array as the last uniform buffer member
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

``VK_EXT_shader_uniform_buffer_unsized_array`` allows the *last* member of a
uniform buffer block to be an unsized array. The effective length of the array is
then inferred at runtime from the size of the buffer object bound to the block,
instead of being baked into the module, so one shader serves any data set size.
The Vulkan extension is gated by
``VkPhysicalDeviceShaderUniformBufferUnsizedArrayFeaturesEXT`` /
``shaderUniformBufferUnsizedArray``.

Unlike the rest of this chapter, the extension is not new module surface: it
relaxes a rule of the Vulkan SPIR-V *environment* and reuses
``OpTypeRuntimeArray``, which is already the type for "array whose length is not
in the module". A conforming module therefore contains exactly

.. code:: spirv

    OpDecorate %runtimearr_float ArrayStride 16
    OpMemberDecorate %type_ConstantBuffer_Data 0 Offset 0
    OpMemberDecorate %type_ConstantBuffer_Data 1 Offset 16
    OpDecorate %type_ConstantBuffer_Data Block
    %runtimearr_float = OpTypeRuntimeArray %float
    %type_ConstantBuffer_Data = OpTypeStruct %float %runtimearr_float
    %_ptr_Uniform_type_ConstantBuffer_Data = OpTypePointer Uniform %type_ConstantBuffer_Data

and nothing else. In particular there is **no**
``SPV_EXT_shader_uniform_buffer_unsized_array`` (the Khronos SPIR-V registry has
no such extension), so no ``OpExtension`` is emitted and
``-fspv-extension`` cannot select the feature; and no capability is added, so the
capability block of the module is the one any other module gets.
``SPV_KHR_untyped_pointers``, which the Vulkan extension lists as a dependency of
its *implementation*, is not needed by this interface and is not emitted either.

HLSL spells the construct as a trailing ``T x[]`` member of a struct used as the
element type of a ``ConstantBuffer``:

.. code:: hlsl

    struct DataBlock {
      float scale;
      float values[];   // unsized, must be the last member
    };
    ConstantBuffer<DataBlock> data;

Because the relaxation is a property of the *device* and not a SPIR-V version or
an extension string, DXC gates it behind an opt-in flag rather than behind
``-fspv-target-env`` or ``-fspv-extension``:
``-fspv-enable-uniform-buffer-unsized-array`` (default off, so a module compiled
without it is byte-for-byte what it was before). The flag only permits the
declaration; it is the application's promise that the device feature is enabled.

Layout. The member is laid out by the same rules as a sized array of the same
element type, so ``Offset`` and ``ArrayStride`` follow the block's layout rule
(``std140`` by default, ``-fvk-use-dx-layout``, ``-fvk-use-scalar-layout``, ...).
For the example above ``values`` gets ``Offset 16`` and ``ArrayStride 16`` under
``std140`` (a ``float`` array element is padded to a ``vec4``), ``Offset 4`` and
``ArrayStride 4`` under ``-fvk-use-scalar-layout``. The array itself contributes
no size to the block, which is why it has to be last.

Restrictions enforced by the compiler:

* The unsized array must be the **last** member of the struct; a member declared
  after it has no defined offset and is rejected ("a member of type ... follows an
  unsized array member").
* The struct may only be used as the element type of a ``ConstantBuffer``, i.e. as
  a uniform buffer block. Push constant blocks and shader record buffers are not
  covered by the Vulkan extension - the Vulkan SPIR-V environment keeps rejecting
  an unsized array in the ``PushConstant`` storage class - and are rejected by
  DXC; a ``TextureBuffer``/``StructuredBuffer`` element type would nest a runtime
  array inside another runtime array, which no storage class allows; and a local
  variable or a function parameter of such a struct cannot have a runtime size.
  ``cbuffer``/``tbuffer`` members keep requiring an explicit dimension.
* ``.Length`` on the unsized member is a compile error. The Vulkan extension
  prohibits ``OpArrayLength`` on it (the length is not a property of the shader),
  so HLSL's array-length property - which lowers to a constant for a sized array -
  has no meaning here.
* The block cannot be copied. A local ``ConstantBuffer<T>`` variable, a
  ``ConstantBuffer<T>`` function parameter and a function returning one are all
  rejected, because CodeGen materializes such a copy in ``Function`` storage and a
  runtime array cannot live there - which is also why the Vulkan extension says
  the unsized array "cannot be passed as arguments to functions". An array of such
  blocks (``ConstantBuffer<T> blocks[2]``) is rejected as well, since the runtime
  array would have to be the last member of each element block.

How the shader learns the length. It does not; the length is passed in. The
application computes it from the size of the bound buffer object:

.. code:: text

    count = max((bufferObjectSize - offsetOfArray) / arrayStride, 0)

where ``offsetOfArray`` is the ``Offset`` decoration of the member and
``arrayStride`` the ``ArrayStride`` decoration of the runtime array - both are
printed by ``-Fc`` and reported by SPIRV-Reflect - and stores it in a separate
uniform buffer member. Indexing the array with any other index is an ordinary
out-of-range buffer access.

What the compiler cannot check. DXC validates the module it emits with the
SPIRV-Tools it ships, which accepts a ``Block``-decorated ``Uniform`` struct that
contains a runtime array (the check lives in
``source/val/validate_memory.cpp`` and defers the "last member, no
``OpArrayLength``, buffer range covers the elements" part to pipeline creation),
so no validator option is toggled. The device side is the application's
responsibility:

* enable ``VK_EXT_shader_uniform_buffer_unsized_array``
  (``VK_EXT_SHADER_UNIFORM_BUFFER_UNSIZED_ARRAY_EXTENSION_NAME``) at
  ``vkCreateDevice`` and set
  ``VkPhysicalDeviceShaderUniformBufferUnsizedArrayFeaturesEXT::shaderUniformBufferUnsizedArray``
  to ``VK_TRUE``;
* set the block's ``VkDescriptorBufferInfo::range`` to cover the sized members
  plus as many whole array elements as the shader should see
  (``VK_WHOLE_SIZE`` exposes the rest of the buffer), and keep indexes inside it.

Without the feature bit the pipeline is rejected at creation time, with the
feature bit and a range that is too small the array reads out of bounds.

See ``examples/spirv-extensions/ext-uniform-buffer-unsized-array.hlsl`` for a
self-contained example and
``tools/clang/test/CodeGenSPIRV/ext.unsized-array*.hlsl`` for the tests that pin
the encoding, the off path and the diagnostics.

Constant data arrays
~~~~~~~~~~~~~~~~~~~~
``SPV_KHR_constant_data`` adds ``OpConstantDataKHR`` (5147) and
``OpSpecConstantDataKHR`` (5148), which declare an array constant in a single
instruction: after *Result Type* and *Result <id>* the operands are the literal
words of the data, instead of one ``OpConstant`` per element plus an
``OpConstantComposite``. The extension introduces the ``ConstantDataKHR``
capability (5146), the ``UTFEncodedKHR`` decoration (5145) and the
``OpExtension "SPV_KHR_constant_data"`` string; on the Vulkan side it is
``VK_KHR_shader_constant_data``, whose feature struct carries one bit for the
extension.

HLSL has no syntax for the instruction: it is an encoding choice for an array
constant the source already contains, so it is selected by an option rather than
by a keyword. With ``-fspv-constant-data[=<threshold>]`` an integer array whose
elements are all known at compile time

.. code:: hlsl

  static const uint table[8] = {
    0x01234567, 0x89abcdef, 1, 2, 3, 4, 5, 6
  };

becomes one instruction instead of an ``OpConstantComposite`` over eight
``OpConstant`` instructions:

.. code:: text

  %uint_8 = OpConstant %uint 8
  %_arr_uint_uint_8 = OpTypeArray %uint %uint_8
  %15 = OpConstantDataKHR %_arr_uint_uint_8 19088743 2309737967 1 2 3 4 5 6

The words are the elements packed with no padding between them (below, and
``OpConstantDataKHR`` in the extension text): elements narrower than 32 bits are
packed from the least significant bits of each word upwards, and the most
significant bits of the final word are ignored. For the table above, which holds
32-bit elements, each word is one element:

* 8-bit elements: four per word, element 0 in the low byte, so
  ``{ 0x01, 0x23, 0x45, 0x67, ... }`` starts with ``0x67452301 0xefcdab89``.
  Signed elements are packed as their two's complement bit pattern at that width
  (``-1`` is the byte ``0xff``, not ``0xffffffff``).
* 16-bit elements: two per word, element 0 in the low half word, so
  ``{ 0x0123, 0x4567, ... }`` starts with ``0x45670123``.
* 32-bit elements: one per word.
* 64-bit elements: two words each, the low word first, so
  ``{ 0x0123456789abcdef, ... }`` starts with ``0x89abcdef 0x01234567``.
* An array whose size is not a multiple of the word size is padded with zero
  high bits in the final word, which the instruction defines as ignored.

Which arrays it applies to. The result type of ``OpConstantDataKHR`` must be an
``OpTypeArray`` of *integer scalar* elements, and must not be decorated with
``ArrayStride``. DXC therefore only encodes an array when all of the following
hold, and keeps the ``OpConstantComposite`` form otherwise:

* the element type is an integer scalar (``bool`` is ``OpTypeBool``, not
  ``OpTypeInt``, and HLSL enums are left alone), so arrays of ``float``,
  ``half``, vectors, matrices or structs are never packed;
* every element is a plain integer constant, not a specialization constant;
* the array has at least ``<threshold>`` elements (see below);
* the data fits in one instruction: the *Word Count* field of a SPIR-V
  instruction is 16 bits, so at most 65532 data words (issue 3 of the
  extension). A larger array keeps the composite form instead of being split.

The ``ArrayStride`` restriction needs no check in practice: the array type of a
constant is lowered with the void layout rule, which produces an ``OpTypeArray``
without a stride, and an array type that does have a stride is a different
``OpTypeArray``.

Threshold and cost. ``OpConstantDataKHR`` is not always smaller: it needs one
32-bit word per element, exactly what the ``<id>`` operands of the composite
cost, so the saving comes from not emitting the per-element ``OpConstant``
instructions. Below ``<threshold>`` elements those instructions are likely to be
shared with the rest of the shader, and the instruction only adds a capability
and an extension, so the default threshold is 8 and
``-fspv-constant-data=1`` is the way to ask for the encoding everywhere. For an
array of 256 ``uint`` elements the effect on the module ``-Fo`` writes is
5860 bytes to 1816 bytes with the default (legalizing and optimizing) pipeline,
and 6128 bytes to 2084 bytes with ``-fcgl``; the per-element ``OpConstant``
instructions that the DXC front end created for the initializer are dropped when
the array becomes constant data, and the optimizer would have removed the unused
remainder anyway.

Gating. The option is off by default, because the instruction changes the
module in a way that a driver, a validator or an offline tool has to understand.
It also requires the extension to be allowed: ``-fspv-constant-data`` without
``-fspv-extension=SPV_KHR_constant_data`` (or the ``KHR`` shorthand that allows
every ``SPV_KHR_*`` extension) is an error, so an explicit
``-fspv-extension=`` list stays an effective allow-list and a module never
declares an extension the host was not offered.
``-fspv-target-env`` does not suppress the ``OpExtension``: no released Vulkan
version makes the capability core, so ``isExtensionRequiredForTargetEnv`` is
true for every target.

What the compiler cannot check. The module validates with the SPIRV-Tools that
ship (the word count, the element type and the missing ``ArrayStride`` are all
validator rules), but whether the device has ``VK_KHR_shader_constant_data``
enabled is the application's responsibility: enable the extension at
``vkCreateDevice`` and set its feature bit, or the pipeline is rejected.

Not implemented. ``OpSpecConstantDataKHR`` is not emitted: HLSL has no
specialization surface for an array (``[[vk::constant_id]]`` applies to scalar
globals only, and ``OpSpecConstantDataKHR`` additionally wants the array
``Length`` to be a specialization constant so that a client can change the number
of words). ``UTFEncodedKHR`` is also not emitted - it is a debugging aid for
string data, and DXC has no HLSL construct that means "this integer array is a
string". The plain ``OpConstantDataKHR`` form below is complete.

See ``examples/spirv-extensions/khr-constant-data.hlsl`` for a self-contained
example (a 256-entry CRC-8 table, next to a 4-entry table that stays a
composite) and ``tools/clang/test/CodeGenSPIRV/constant-data*.hlsl`` for the
tests that pin the packing of every element width, the threshold, the off path,
the optimizer-survival path and the diagnostics.

Shader abort
~~~~~~~~~~~~
The ``SPV_KHR_abort`` extension adds ``OpAbortKHR`` (5121), an instruction that
ceases all further processing in the invocation that executes it and reports a
message to the client API. The extension describes it as follows:

  "Ceases all further processing in the invocation that executes it. Only
  instructions executed before OpAbortKHR will have side effects. Other
  invocations in the same Device scope instance will also be terminated in finite
  time, though may reach completion."

HLSL spells it ``vk::Abort()`` from ``<vk/ext/abort.h>``:

.. code:: hlsl

  #include <vk/ext/abort.h>

  [numthreads(64, 1, 1)]
  void main(uint3 tid : SV_DispatchThreadID) {
    if (!IsFinite(input[tid.x])) {
      vk::Abort(0x1000 + tid.x); // OpAbortKHR %uint %message
    }
    // ...
  }

The instruction has no result type and no result id; its two ``IdRef`` operands
are the *Message Type* and the *Message*, in that order (word 4 and word 5 in the
extension's encoding table):

  "Message Type is the type of the data to be written. [...] Message is data that
  is passed to the client API after termination. Message Type must logically
  match the type of Message."

Operand 4 is therefore a *type* id and operand 5 the id of a *value* of that type,
not a pointer to a message block. DXC uses the message value's own type as the
type operand and takes the message from the single ``uint`` argument, so the
message is four bytes of data in the host's byte order:

.. code:: text

  %uint = OpTypeInt 32 0
  %uint_12648430 = OpConstant %uint 12648430
  ...
  OpAbortKHR %uint %uint_12648430

``OpAbortKHR`` is a block terminator ("This instruction must be the last
instruction in a block"), so the emitter treats the call like ``return`` and
``discard``: the statement ends the current block, and statements written after
it are placed in a block that has no predecessor and is never emitted. "Only
instructions executed before OpAbortKHR will have side effects" therefore holds
structurally - code after the call cannot execute and does not appear in the
module. The instruction is legal in a helper function for the same reason: a
block that ends in it simply has no successor, so the function needs no return
path from it, and SPIRV-Tools models it exactly that way (``validate_cfg.cpp``
ends the current block on it and registers no execution-model restriction, which
is why DXC accepts ``vk::Abort`` in every stage, fragment shaders included).

The extension is **not** enabled by default. A module that aborts declares
``OpCapability AbortKHR`` (5120) together with ``OpExtension "SPV_KHR_abort"``,
and ``VK_KHR_shader_abort`` makes an abort lose the device, so enabling the
instruction implicitly would turn a shader that only wants to report something
into a device loss on a host that never opted in. Without
``-fspv-extension=SPV_KHR_abort`` every ``vk::Abort`` call is a compile error
instead, and a shader that does not abort is unchanged.

``OpAbortKHR`` needs the ``ConstantDataKHR`` capability and the
``SPV_KHR_constant_data`` extension only for a message that is built out of
``OpConstantDataKHR``. The extension's own example packs a format string and its
arguments into a struct laid out with scalar rules, where the string is an
``OpTypeArray`` of bytes decorated ``UTFEncodedKHR`` and its contents an
``OpConstantDataKHR``. HLSL has no equivalent of that convention - the format
string and the variadic argument list are GLSL surface, not SPIR-V - and a message
type that is an array must additionally carry an ``ArrayStride`` decoration in a
module that declares ``Shader``, which an ``OpConstantDataKHR`` result type may
not, so such a message needs two structurally identical array types (a value type
for the instruction and a load type for the abort). DXC does not emit that form,
so a module that aborts with the scalar message above declares ``AbortKHR`` only.
If an ``OpAbortKHR`` whose message *is* an ``OpConstantDataKHR`` does reach the
backend - through a hand-written ``[[vk::ext_instruction(5121)]]`` declaration,
for example - CapabilityVisitor adds the dependent ``ConstantDataKHR`` capability
and the ``SPV_KHR_constant_data`` extension as well.

Limitations:

* The abort is not a barrier and does not synchronize. Other invocations of the
  same device are terminated "in finite time" but "may reach completion", so a
  shader must not rely on an abort to publish data for other invocations, and the
  side effects the application may observe are only the ones that happened before
  the abort.
* The message is data, not a format string: nothing is formatted and the host
  receives the raw four bytes. With ``VK_KHR_device_fault`` enabled as well,
  ``VkDeviceFaultShaderAbortMessageInfoKHR`` reads the messages back as a sequence
  of 8-byte-aligned length/message pairs, so several invocations may each report
  one.
* The host must enable
  ``VkPhysicalDeviceShaderAbortFeaturesKHR::shaderAbort`` before it creates a
  pipeline that contains the instruction, and must be prepared for the device to be
  lost; the largest message it accepts is
  ``VkPhysicalDeviceShaderAbortPropertiesKHR::maxShaderAbortMessageSize``, at least
  65536 bytes. The compiler cannot check any of this.
* This is a SPIR-V only surface: DXIL has no abort instruction, so a ``vk::Abort``
  call on the DXIL path has no definition and is rejected with "External function
  used in non-library profile".

Arm cooperative matrix memory layouts
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

The ``SPV_ARM_cooperative_matrix_layouts`` extension adds two memory layouts to
the cooperative matrix load and store instructions, aimed at Arm GPUs that keep
matrices in a blocked, interleaved form in memory:

* ``RowBlockedInterleavedARM`` (4202) - the blocks of the matrix are ordered
  row-major.
* ``ColumnBlockedInterleavedARM`` (4203) - the blocks are ordered column-major.

Both are enabled by the ``CooperativeMatrixLayoutsARM`` capability.

The capability is 4201 and implicitly declares
``CooperativeMatrixKHR``, so a module that uses either layout also declares
``SPV_KHR_cooperative_matrix``. SPIR-V CodeGen adds the capability and
``OpExtension "SPV_ARM_cooperative_matrix_layouts"`` from the ``MemoryLayout``
operand of ``OpCooperativeMatrixLoadKHR`` / ``OpCooperativeMatrixStoreKHR``
itself, so a shader does not request anything: naming one of the two enumerants is
the request. The extension is enabled by default - there is no alternative
lowering to fall back to - and ``-fspv-extension=SPV_ARM_cooperative_matrix_layouts``
is accepted, and only needed when an explicit allow-list is in use.

Both layouts arrange a matrix in 64-byte blocks. A block holds a sub-matrix of 4
rows and ``16 / sizeof(ComponentType)`` columns, stored row-major inside the
block: 4 rows, times ``16 / sizeof(ComponentType)`` columns, times
``sizeof(ComponentType)`` bytes is 64 bytes.
``RowBlockedInterleavedARM`` orders the blocks row-major,
``ColumnBlockedInterleavedARM`` column-major, and in both the blocks are
interleaved at a 4-byte granularity in groups whose size is the *Stride* operand.

The ``Stride`` operand
++++++++++++++++++++++

For ``RowMajorKHR`` (0) and ``ColumnMajorKHR`` (1), ``Stride`` is a byte stride:
the distance between the starts of two consecutive rows (row-major) or columns
(column-major), and nothing else. For the two Arm layouts it is the *interleaving
group size, counted in blocks*, and the extension restricts it to 1, 2 or 4.
Every other value is invalid, not merely unusual.

The extension also requires ``Stride`` - and ``MemoryLayout`` itself - to come
from a *constant* instruction. DXC lowers every HLSL function parameter to a
pointer and reads it back with ``OpLoad``, so a stride passed as an argument can
never satisfy that rule. The Arm layouts are therefore reached through entry
points that take the stride as a template argument, which reaches the instruction
as an ``OpConstant``:

.. code:: hlsl

  #include <vk/arm/cooperative_matrix_layouts.h>

  using FloatMatA =
      vk::khr::CooperativeMatrixA<float, vk::ScopeSubgroup, 16, 16>;

  // MemoryLayout 4202, Stride 1, reading a structured buffer.
  FloatMatA a = FloatMatA::LoadBlockedInterleaved<
      vk::CooperativeMatrixLayoutRowBlockedInterleavedARM, 1>(source, 0);

  // MemoryLayout 4203, Stride 2, writing workgroup memory.
  a.StoreBlockedInterleaved<
      vk::CooperativeMatrixLayoutColumnBlockedInterleavedARM, 2>(
      vk::GetGroupSharedAddress(staging[0]));

``LoadBlockedInterleaved`` is available for ``StructuredBuffer``,
``RWStructuredBuffer`` and ``WorkgroupSpirvPointer``; ``StoreBlockedInterleaved``
for ``RWStructuredBuffer`` and ``WorkgroupSpirvPointer``. The workgroup forms add
the make-visible/non-private and make-available/non-private memory access operands
with the workgroup scope, exactly like the workgroup forms of ``Load``/``Store``.

Alignment requirements
++++++++++++++++++++++

``Stride`` is not a byte stride, so the shapes a matrix may have are restricted
rather than merely aligned. With ``T`` the component type (and ``sizeof(T)`` the
size the compiler gives it, which is what ``OpTypeCooperativeMatrixKHR`` carries):

* ``RowBlockedInterleavedARM``: ``Rows`` must be a multiple of 4, and ``Columns``
  a multiple of ``(16 / sizeof(T)) * Stride``.
* ``ColumnBlockedInterleavedARM``: ``Rows`` must be a multiple of ``4 * Stride``,
  and ``Columns`` a multiple of ``16 / sizeof(T)``.

The first factor of each rule says that the matrix has to tile exactly into whole
64-byte blocks; the ``Stride`` factor says that a row (or column) of blocks has to
contain whole interleaving groups. A 16x16 ``float`` matrix therefore works with
either layout and any of the three strides, because ``16 / sizeof(float)`` is 4:
16 is a multiple of 4, of 4, of 8 and of 16. A 16x8 ``float`` matrix with a stride
of 4 in ``RowBlockedInterleavedARM`` does not, because 8 is not a multiple of
``4 * 4``.

Combinations that are invalid
+++++++++++++++++++++++++++++

Both restrictions are checked at compile time, and the check costs nothing at run
time: ``LoadBlockedInterleaved`` / ``StoreBlockedInterleaved`` instantiate a
template that only has a definition for a supported combination, so

* a ``Stride`` other than 1, 2 or 4,
* a ``Rows``/``Columns`` pair that violates the tiling rule above, or
* a ``MemoryLayout`` that is not one of the two Arm enumerants,

is a compile-time error - ``error: implicit instantiation of undefined template
'vk::arm::BlockedInterleavedLayoutIsSupported<false>'`` followed by a note naming
the offending call. Rather than emitting SPIR-V that ``spirv-val`` rejects, which
is what happens if the combination is passed to the instruction anyway.
Handing one of the Arm layouts to the ordinary ``Load``/``Store`` entry points,
whose stride is a run-time argument, is a compile-time error as well:
``error: implicit instantiation of undefined template
'vk::arm::RuntimeStrideIsValidForLayout<false>'``.

The classic ``RowMajorKHR`` / ``ColumnMajorKHR`` path is untouched: a module that
does not name an Arm layout declares neither the capability nor the extension and
passes the same operands as before.

One combination is deliberately *not* diagnosed: a ``MemoryLayout`` that is a
specialization constant. ``OpSpecConstant`` is a constant instruction, so the module
is legal, but the compiler cannot know which layout the host will select - and the
checks above cannot run at all. The capability and the extension are then declared
conservatively, which is always valid, rather than rejecting legal SPIR-V; the host
carries the responsibility, since whatever it sets has to satisfy the same rules.

What the compiler cannot check
++++++++++++++++++++++++++++++

* the buffer contents. Blocks must have been written by the producer with the same
  layout, the same interleaving group size and the same block ordering; a mismatch
  is silently wrong numbers, not a validation error.
* the device. ``VkCooperativeMatrixPropertiesKHR::memoryLayout`` has to report
  ``VK_COOPERATIVE_MATRIX_LAYOUT_ROW_BLOCKED_INTERLEAVED_ARM`` or
  ``VK_COOPERATIVE_MATRIX_LAYOUT_COLUMN_BLOCKED_INTERLEAVED_ARM`` for the component
  type and shape in use, and the host has to enable
  ``VK_ARM_cooperative_matrix_layouts``. The layouts are device specific and have
  no portable fallback.

The stride operand of the workgroup-memory forms has one more restriction that is
not specific to this extension: ``spirv-val`` requires the ``Scope`` operand of
``OpCooperativeMatrixLoadKHR`` / ``OpCooperativeMatrixStoreKHR`` to be a constant,
and before legalization it is still a run-time argument. A ``-fcgl`` compile of
either workgroup-memory form - with the classic layouts as well - is therefore
rejected by validation, and the workgroup forms are covered by the tests that
compile without ``-fcgl``.

See ``examples/spirv-extensions/arm-cooperative-matrix-layouts.hlsl`` for a
self-contained example and
``tools/clang/test/CodeGenSPIRV/arm.cooperative-matrix.layouts*.hlsl`` for the
tests that pin the capability, the extension, the layout and stride operands, the
classic off path, the optimizer-survival path and the diagnostics.

Cooperative matrix maintenance
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
The ``SPV_EXT_cooperative_matrix_maintenance1`` extension adds four operations to
the cooperative matrix type of ``SPV_KHR_cooperative_matrix``: a *use* conversion,
a reduction, a per-element operation, and an index-to-coordinate mapping. It is
gated by the Vulkan ``VK_EXT_cooperative_matrix_maintenance1`` device extension.
That extension adds no feature struct and no property struct of its own - the four
capabilities are part of what a device already reports through
``vkGetPhysicalDeviceCooperativeMatrixPropertiesKHR``, and there is nothing extra
for the host to query or chain.

* ``ConvertUse`` - ``OpCooperativeMatrixConvertUseEXT`` (5293), capability
  ``CooperativeMatrixConversionsEXT`` (5429).
* ``Reduce`` - ``OpCooperativeMatrixReduceEXT`` (5366), capability
  ``CooperativeMatrixReductionsEXT`` (5430).
* ``PerElementOp`` - ``OpCooperativeMatrixPerElementOpEXT`` (5369), capability
  ``CooperativeMatrixPerElementOperationsEXT`` (5432).
* ``GetCoordinate`` - ``OpCooperativeMatrixGetCoordinateEXT`` (5363), capability
  ``CooperativeMatrixGetCoordinateEXT`` (5438).

A module that uses any of them declares the matching capability, once, and
``OpExtension "SPV_EXT_cooperative_matrix_maintenance1"``. The extension is
**enabled by default**: every instruction it gates is reachable only through an
entry point that did not exist before, so no existing shader changes code
generation, and the capability and the extension string are emitted only for a
module that actually contains one of the four instructions. ``-fspv-extension=SPV_EXT_cooperative_matrix_maintenance1``
is accepted and is only needed when an explicit allow-list is in use; with such a
list that omits it, the entry points are compile errors instead of a module whose
capability the header could not declare.

The entry points are the last four members of
``vk::khr::CooperativeMatrix<ComponentType, scope, rows, columns, use>`` in
``<vk/khr/cooperative_matrix.h>``:

.. code:: hlsl

  #include <vk/khr/cooperative_matrix.h>

  using Accumulator =
      vk::khr::CooperativeMatrixAccumulator<float, vk::ScopeSubgroup, 16, 16>;
  using AccumulatorRow =
      vk::khr::CooperativeMatrixAccumulator<float, vk::ScopeSubgroup, 16, 1>;
  using MatrixA = vk::khr::CooperativeMatrixA<float, vk::ScopeSubgroup, 16, 16>;

  // 16x16 -> 16x1, one value per row (CooperativeMatrixReductionsEXT).
  AccumulatorRow rowSum = c.Reduce<16, 1, vk::CooperativeMatrixReduceRow>();
  // 16x16 -> 8x8, one value per 2x2 block.
  Accumulator8x8 blockSum = c.Reduce<8, 8, vk::CooperativeMatrixReduce2x2>();
  // The (row, column) the element at `index` came from.
  uint2 coordinate = c.GetCoordinate(index);
  // The same values, in the A position of a multiply-add
  // (CooperativeMatrixConversionsEXT).
  MatrixA a = c.ConvertUse<vk::CooperativeMatrixUseMatrixAKHR>();
  // An element-wise operation (CooperativeMatrixPerElementOperationsEXT).
  Accumulator scaled = c.PerElementOp();

Use conversion
++++++++++++++
``OpCooperativeMatrixConvertUseEXT`` reinterprets a matrix with a different
``CooperativeMatrixUse``: the component type, the scope, the rows and the columns
have to be identical, and only the use changes. The extension restricts the
conversion to accumulator -> A or B, and A or B -> accumulator, which is what
moving a result into the input position of the next multiply-add needs; A -> B is
not a conversion, it would reinterpret the values. ``ConvertUse`` instantiates a
template that only has a definition for a supported pairing, so anything else is
``error: implicit instantiation of undefined template
'vk::khr::ConvertUseIsSupported<false>'`` followed by a note naming the call,
rather than SPIR-V that ``spirv-val`` rejects with "Matrix and Result Type must
convert between MatrixAccumulatorKHR and MatrixAKHR or MatrixBKHR".

Reductions
++++++++++
``OpCooperativeMatrixReduceEXT`` reduces a matrix along rows (``Row``, 1), along
columns (``Column``, 2), along both (``Row | Column``, 3, which leaves a 1x1
matrix) or across 2x2 blocks (``2x2``, 4), combining the elements with the
function named by its last operand. Both the matrix and the result have to be
accumulators, and the result shape has to be the one the mode produces: ``Row``
keeps the row count, ``Column`` the column count, ``2x2`` halves both and
``Row | Column`` leaves 1x1. ``Reduce`` takes the mode *and* the result shape as
template arguments, ``Reduce<newRows, newColumns, mode>()``, because the
``CooperativeMatrixReduce`` operand is a literal bit mask and not an ``<id>``: a
mode that is only known at run time cannot be encoded at all. Passing one anyway -
``Reduce<newRows, newColumns>(mode)`` - is a compile error, as is an unsupported
mode, a result shape that does not match it, or a matrix whose use is not
``MatrixAccumulatorKHR``: ``error: implicit instantiation of undefined template
'vk::khr::ReduceModeMustBeAConstant<false>'`` and
``... 'vk::khr::ReduceIsSupported<false>'`` respectively.

Per-element operations
++++++++++++++++++++++
``OpCooperativeMatrixPerElementOpEXT`` applies a function to every element of a
matrix. The result type has to be the matrix type - ``spirv-val`` compares the two
type ids - so ``PerElementOp()`` returns the same type as its receiver.

Index to coordinate
+++++++++++++++++++
``OpCooperativeMatrixGetCoordinateEXT`` maps an element index of a matrix to the
coordinate of the same element in the source matrix, as a two-component 32-bit
integer vector (``uvec2``); that is the result type ``spirv-val`` requires, and
``GetCoordinate`` returns it as a ``uint2``.

The combine and per-element functions
+++++++++++++++++++++++++++++++++++++
The last operand of ``OpCooperativeMatrixReduceEXT`` and
``OpCooperativeMatrixPerElementOpEXT`` is the id of an ``OpFunction``, and SPIR-V
has no operand form that can name an HLSL function, so the two entry points are
compiler builtins rather than ``[[vk::ext_instruction]]`` wrappers. CodeGen
synthesizes the function - ``__coopmat_combine`` takes the two component-type
values of a reduction, ``__coopmat_perelem`` takes (row, column, value) - and
passes a reference to it, and the module therefore contains the definition of a
function whose body is ``OpUndef``. **The operation itself is not defined yet**:
the encoding is, and the extension's capability is what makes the instruction
legal, but a shader that reduces or applies a per-element operation gets an
undefined value until HLSL has a way to pass a user-defined function. This
limitation is inherited from the ``SPV_NV_cooperative_matrix2`` spellings, which
use the same synthesized functions.

What the compiler cannot check
++++++++++++++++++++++++++++++
* the device. Shapes, component types, scopes and uses are device specific: the
  host has to find a ``VkCooperativeMatrixPropertiesKHR`` matching them and enable
  ``VK_EXT_cooperative_matrix_maintenance1`` before it creates the pipeline. A
  driver without the extension rejects a module that contains one of the four
  instructions.
* the result of a reduction or of a per-element operation, as described above.
* the semantics of a use conversion. ``spirv-val`` checks that the two types have
  the same shape and a legal pairing of uses; whether the values make sense in the
  new role is the shader author's responsibility.

See ``examples/spirv-extensions/ext-cooperative-matrix-maintenance1.hlsl`` for a
self-contained example and
``tools/clang/test/CodeGenSPIRV/ext.cooperative-matrix.maintenance1*.hlsl`` for the
tests that pin the four capabilities, the extension, the operand order of each
instruction, the off path, the optimizer-survival path and the two diagnostics.

TOSA tensor operations (``TOSA.001000.1``)
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
TOSA - Tensor Operator Set Architecture - is Arm's operator set for the tensor
graphs of the **ARM data-graph ecosystem**. It is not a Vulkan extension and this
compiler does not implement it as one: TOSA is an *extended instruction set*,
identified by the string in ``OpExtInstImport``, with no extension string and no
capability of its own.

.. code:: hlsl

  #include <vk/arm/tosa.h>
  using namespace vk::arm::tosa;
  Tensor<float> a = ...;
  Tensor<float> b = ...;
  Tensor<float> sum = Add(a, b);                        // ADD
  Tensor<float> mag = Abs(sum);                         // ABS
  Tensor<float> big = Maximum(NanModeIgnore, mag, b);   // MAXIMUM, nan_mode IGNORE

.. code:: text

  OpCapability TensorsARM
  OpExtension "SPV_ARM_tensors"
  %1 = OpExtInstImport "TOSA.001000.1"
  %tf = OpTypeTensorARM %float
  %add = OpExtInst %tf %1 ADD %a %b
  %abs = OpExtInst %tf %1 ABS %add
  %max = OpExtInst %tf %1 MAXIMUM %int_1 %abs %b

The set name pins the version: ``TOSA.001000.1`` is TOSA 1.0 revision 1
(``TOSAVersion`` 1000001, ``TOSARevision`` 1), whose 66 operations are numbered
0-65. A consumer looks the set up by that exact string, so a different version is a
different instruction set with a different opcode table; ``dxc`` refuses one
("Invalid extended instruction import '...'"), as it refuses an opcode outside the
table ("Invalid extended instruction number: ..."). Getting the *string* and the
*numbers* right is the whole contract - both are pinned in
``tools/clang/test/CodeGenSPIRV/tosa.identifiers.error.hlsl``.

The operand type is a tensor, not a scalar or a vector. ``SPV_ARM_tensors``
provides it as ``OpTypeTensorARM`` (4163), which HLSL has no spelling for, so
``<vk/arm/tosa.h>`` builds it out of the ordinary ``vk::`` type machinery:

.. code:: hlsl

  template <typename ElementType> using Tensor =
      vk::SpirvOpaqueType</* OpTypeTensorARM */ 4163, ElementType>;

and every declaration in the header is one ``[[vk::ext_instruction]]`` over it.
That type is in ``SPV_ARM_tensors``, so a module that contains a TOSA operation
declares ``OpCapability TensorsARM`` (4174) and ``OpExtension "SPV_ARM_tensors"`` -
once each, and only when an operation is used. Including the header and using
nothing from it adds nothing to the module, and there is no import until the first
TOSA call (``SpirvBuilder::getExtInstSet``).

``SPV_ARM_tensors`` is a ``FeatureManager`` allow-list entry (see the "Arm tensors"
section below), so ``-fspv-extension=SPV_ARM_tensors`` is accepted and the capability and the
extension are also inferred from the ``OpTypeTensorARM`` type itself. The header still
requests the pair on every declaration with ``[[vk::ext_capability]]`` /
``[[vk::ext_extension]]``: both paths produce the same single
``OpCapability``/``OpExtension`` pair, and the explicit request is what makes a
declaration that forgot one impossible, including for the unranked type the header
uses. Registration also means an explicit ``-fspv-extension`` list that omits
``SPV_ARM_tensors`` refuses a TOSA body with "SPIR-V extension 'SPV_ARM_tensors'
required for tensor types but not permitted to use", which is the right behaviour for
a graph instruction set: the alternative would be a module whose instructions need a
capability that the command line had just removed.

Operand order is the instructions' and not the mnemonics': ``MAXIMUM`` and
``MINIMUM`` take ``nan_mode`` first, ``TRANSPOSE`` takes its permutation first,
``CONCAT`` takes its axis first, and ``MUL``, ``NEGATE`` and ``MATMUL`` put their
attribute operands last, after every data operand. TOSA's attribute operands - a
``nan_mode``, an ``axis``, a zero point, a reshape shape - are ``IdRef`` operands in
the SPIR-V encoding, so each is an ordinary HLSL parameter in the header and each
must be a compile-time constant for TOSA to be meaningful. The compiler does not
enforce that: a computed value becomes an ``OpLoad`` where TOSA wants an
``OpConstant``, and the module validates anyway because the validator only checks
the operand count.

The same applies to the *values* of the mode selectors. ``NanModeIgnore`` is 1 and
``NanModePropagate`` is 0 because that is what the TOSA 1.0 specification assigns
them; SPIR-V sees an integer id and nothing else, so a consumer that reads a
different value reads a different mode. The header names the two enumerators that
exist rather than inviting a bare literal, but it cannot check them.

What the surface cannot express
+++++++++++++++++++++++++++++++

* **No shape, and only optionally a rank.** ``OpTypeTensorARM``'s two optional
  operands are Rank and Shape. Rank is expressible - it is the id of an integer
  constant, ``vk::integral_constant<uint, N>`` - and
  ``tools/clang/test/CodeGenSPIRV/tosa.ranked-tensor.hlsl`` shows the spelling.
  Shape is not: it is the id of an ``OpConstantComposite`` of an integer array, and
  the ``vk::`` template-argument machinery carries types and integer constants but
  not composite constants. A tensor in this compiler therefore has neither rank nor
  shape unless you declare the type yourself, which is why the header's ``Tensor``
  alias is unranked and why a consumer reads shapes from the graph that produced
  the tensors.
* **No data-graph entry point.** ``OpGraphARM``, ``OpGraphEntryPointARM`` and the
  rest of the ``OpGraph*ARM`` family - ``SPV_ARM_graph``, ``OpCapability
  GraphARM`` - are what make a module a *graph* rather than a kernel. DXC emits
  none of them, so a module using these operations is a compute shader that happens
  to contain TOSA instructions, and a runtime that requires them inside a graph
  rejects it. That is a front-end feature (a new kind of entry point), not
  something a header can supply.
* **No tensor resource, and no constant tensor.** ``SPV_ARM_tensors`` makes
  ``OpTypeTensorARM`` a descriptor type, but HLSL has no resource-object spelling
  for it: a global of an opaque type lands in ``$Globals``, and a
  ``RWStructuredBuffer`` of one embeds the opaque type in a ``StructBlock``. A
  tensor value can only come from another TOSA operation, or be an uninitialized
  local, until a data-graph entry point supplies one. A constant tensor needs the
  Shape operand the type cannot carry.
* **Not the whole set.** The header declares 47 of the 66 operations: the ones a
  shader can feed without inventing convolution-kernel, pooling, FFT, resize,
  gather/scatter, table or rescale operand conventions. Those are reachable through
  ``[[vk::ext_instruction(<opcode>, "TOSA.001000.1")]]`` directly.
* **Nothing numeric.** No CI in this repository implements TOSA, so the tests pin
  the encoding and not the arithmetic, and a driver rejecting the module at
  pipeline-creation time is outside the compiler's reach.

What the host has to do
+++++++++++++++++++++++

TOSA is a profile-and-level specification, and the module says nothing about
conformance:

* Which of the 66 operations a device implements, at which levels (8K, 16K, FP), and
  in which of TOSA's extensions (int16, fp8, bf16, control flow, ...) is discovered
  at runtime from the implementation. ``ADD`` in a module is not evidence that the
  device can execute ``ADD``.
* The device and driver have to support the Arm data-graph model that consumes
  these instructions, and the application has to have negotiated the TOSA version it
  is handing over - the compiler emits exactly ``TOSA.001000.1``.
* The compiler cannot check any of this and no test can execute it.

See ``examples/spirv-extensions/tosa.hlsl`` for a self-contained example and
``tools/clang/test/CodeGenSPIRV/tosa.*.hlsl`` for the tests that pin the import
string, the capability and extension pair, the operand order of 47 operations, the
ranked-tensor spelling, the off path, the optimizer-survival path and the two
element-type and set-string diagnostics.

Arm tensors (``SPV_ARM_tensors``)
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
The ``SPV_ARM_tensors`` extension adds a *tensor* type and three operations over it.
A tensor is a handle to a multi-dimensional array of one scalar element type that the
host creates, binds to memory and hands to the shader as a descriptor - the same shape
as an image or an acceleration structure, with a rank and an element type instead of a
format and a dimensionality. It is gated by the Vulkan ``VK_ARM_tensors`` device
extension, whose ``VkPhysicalDeviceTensorPropertiesARM`` structure carries the rank,
element-count, stride and descriptor-count limits.

.. code:: hlsl

  #include <vk/arm/tensors.h>
  using namespace vk::arm;

  Tensor<float, 2> t = ...; // the handle; see "Where the value comes from" below
  Coordinates<2> c = MakeCoordinates(0, 1);
  float v = TensorRead(t, c); // OpTensorReadARM
  TensorWrite(t, c, v + 1.0); // OpTensorWriteARM
  uint w = TensorSize<1>(t); // OpTensorQuerySizeARM

.. code:: text

  OpCapability TensorsARM
  OpExtension "SPV_ARM_tensors"
  %tensor = OpTypeTensorARM %float %uint_2
  %coords = OpTypeArray %uint %uint_2
  %c0 = OpCompositeConstruct %coords %uint_0 %uint_1
  %v = OpTensorReadARM %float %tensor %c0
  OpTensorWriteARM %tensor %c0 %sum        ; no result id
  %n = OpTensorQuerySizeARM %uint %tensor %uint_1

The instructions are ``OpTypeTensorARM`` (4163), ``OpTensorReadARM`` (4164),
``OpTensorWriteARM`` (4165) and ``OpTensorQuerySizeARM`` (4166), and the capability is
``TensorsARM`` (4174). Four details of that encoding are worth spelling out, because
none of them is what the names suggest:

* ``OpTypeTensorARM``'s *Element Type* is a type operand (not a result type) and its
  *Rank* is the id of a 32-bit integer constant, not a literal. Its third operand,
  *Shape* - the id of an ``OpConstantComposite`` of an integer array whose length
  equals Rank - is not expressible through the ``vk::`` template-argument machinery,
  which carries types and integer constants but not composite constants, so
  ``vk::arm::Tensor`` is ranked and unshaped. Only the reading operations need the
  rank: SPIRV-Tools rejects an unranked tensor for them ("Expected Tensor to be an
  ``OpTypeTensorARM`` whose Rank is specified"), which is why ``<vk/arm/tosa.h>``'s
  unranked operand type cannot be read with them.
* *Coordinates* is one operand: an id of an ``OpTypeArray`` whose element type is an
  integer and whose length equals the tensor's rank. Not a vector, and not one operand
  per dimension. ``Coordinates<Rank>`` is that array type and ``MakeCoordinates``
  builds one with ``OpCompositeConstruct``; SPIRV-Tools checks the length against the
  rank.
* ``OpTensorWriteARM`` has **no result id** and takes the value written as its third
  operand, after the tensor and the coordinates - not as an out-parameter pointer.
* The *Dimension* operand of ``OpTensorQuerySizeARM`` must name a constant
  instruction, so ``TensorSize<dimension>()`` takes it as a template argument; it also
  rejects a dimension that is not smaller than the rank.

``SPV_ARM_tensors`` is registered in ``FeatureManager`` and **enabled by default**. It
is not part of any Vulkan version, so no target environment implies it, and a module
that declares ``TensorsARM`` validates for ``vulkan1.0``. Registration buys three
things: ``-fspv-extension=SPV_ARM_tensors`` is accepted instead of being reported as an
unknown extension, it is listed by the ``-fspv-extension`` diagnostics, and the
capability and the extension are emitted through the same ``CapabilityVisitor`` path as
every other extension - inferred from the tensor *type*, so they cannot appear without
it. An explicit ``-fspv-extension`` list remains an allow-list: omitting
``SPV_ARM_tensors`` from it makes every use of a tensor type a compile error ("SPIR-V
extension 'SPV_ARM_tensors' required for tensor types but not permitted to use"). The
extension is enabled by default because the tensor type already ships: every TOSA
operation in ``<vk/arm/tosa.h>`` is declared over ``OpTypeTensorARM``, so opting in
would turn every existing TOSA shader - which passes no flag - into that error.

Diagnosed rather than miscompiled:

* A non-scalar element type (``Tensor<float2, 2>``) and a rank outside 1..4. A rank of
  0 is invalid SPIR-V; a rank above 4 is outside the range every implementation
  supports, because Vulkan requires ``maxTensorDimensionCount`` to be at least 4 and
  the compiler cannot query the device.
* A tensor in stage input or output, and a tensor as a member of a uniform, storage
  buffer or push constant block. SPIRV-Tools happens to accept both, so this diagnostic
  is the only thing between the shader and a module no host can bind. Note that an
  HLSL *global* of tensor type is placed in ``$Globals``, which is a uniform block, and
  that ``[vk::binding]`` on such a global is refused earlier ("variable 'x' will be
  placed in $Globals so cannot have vk::binding attribute").
* Use under an explicit ``-fspv-extension`` list that omits the extension.

Where the value comes from - and the limit of this landing
+++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
``SPV_ARM_tensors`` makes ``OpTypeTensorARM`` a descriptor type: SPIRV-Tools lists it
next to ``OpTypeImage`` and ``OpTypeAccelerationStructureKHR`` among the types a
``UniformConstant`` variable may have, and next to them in the ``ResourceHeapEXT`` type
list. HLSL has no resource-object spelling for it, and no way to ask for a
``UniformConstant`` variable of an arbitrary opaque type, so a tensor **resource** is
not expressible from HLSL today. That is a front-end feature - a resource type like
``RaytracingAccelerationStructure``, or the data-graph entry point of
``SPV_ARM_graph`` - and not something a header can supply.

Until then a tensor handle comes from one of two places:

* a TOSA operation. An ``[[vk::ext_instruction(<opcode>, "TOSA.001000.1")]]``
  declaration whose result type is ``vk::arm::Tensor<T, Rank>`` produces a ranked
  tensor, which can then be read.
* an uninitialized local. ``OpVariable`` in ``Function`` storage, ``OpLoad``\ ed once,
  is a structurally valid module; what the handle points at is whatever the
  implementation put there, so a shader that does this and runs is reading an undefined
  resource. It is what the tests compile.

What the host has to do - none of it is checkable here:

* enable the ``VK_ARM_tensors`` device extension and its tensor features, and query
  ``VkPhysicalDeviceTensorPropertiesARM`` for the limits;
* create the tensor with ``vkCreateTensorARM``, bind memory, and write the descriptor; a
  ``VkTensorDescriptionARM`` whose element type or ``dimensionCount`` does not match the
  type in the module, or a descriptor that is never written, fails at pipeline creation
  or reads garbage;
* keep the descriptor within ``maxDescriptorSetStorageTensors`` and
  ``maxPerStageDescriptor*StorageTensors``, each dimension within
  ``maxPerDimensionTensorElements``, and the rank within ``maxTensorDimensionCount`` (at
  least 4 everywhere, which is the largest rank the header accepts);
* ``shaderTensorSupportedStages`` requires ``VK_SHADER_STAGE_COMPUTE_BIT`` for the
  tensor features implemented here, so a module that uses a tensor belongs to a compute
  pipeline;
* numeric conformance is the implementation's: no CI in this repository executes a
  tensor instruction, so the tests pin the encoding, not the arithmetic.

See ``examples/spirv-extensions/arm-tensors.hlsl`` for a self-contained example and
``tools/clang/test/CodeGenSPIRV/arm.tensors*.hlsl`` for the tests that pin the capability
and extension pair, the type with its rank, the operand order of the three instructions,
the off path, the optimizer-survival path and the five diagnostics.

Supported extensions
~~~~~~~~~~~~~~~~~~~~

* SPV_KHR_16bit_storage
* SPV_KHR_bfloat16
* SPV_KHR_device_group
* SPV_KHR_fragment_shading_rate
* SPV_KHR_multivew
* SPV_KHR_post_depth_coverage
* SPV_KHR_non_semantic_info
* SPV_KHR_shader_draw_parameters
* SPV_KHR_ray_tracing
* SPV_KHR_shader_clock
* SPV_EXT_cooperative_matrix_maintenance1
* SPV_EXT_demote_to_helper_invocation
* SPV_EXT_descriptor_indexing
* SPV_EXT_fragment_fully_covered
* SPV_EXT_fragment_invocation_density
* SPV_EXT_fragment_shader_interlock
* SPV_EXT_float8
* SPV_EXT_long_vector
* SPV_EXT_mesh_shader
* SPV_EXT_shader_stencil_support
* SPV_EXT_shader_subgroup_partitioned
* SPV_EXT_shader_viewport_index_layer
* SPV_EXT_split_barrier
* SPV_AMD_shader_early_and_late_fragment_tests
* SPV_GOOGLE_hlsl_functionality1
* SPV_GOOGLE_user_type
* SPV_NV_ray_tracing
* SPV_NV_mesh_shader
* SPV_NV_cluster_acceleration_structure
* SPV_NV_linear_swept_spheres
* SPV_KHR_ray_query
* SPV_KHR_opacity_micromap
* SPV_EXT_shader_image_int64
* SPV_KHR_fragment_shader_barycentric
* SPV_KHR_physical_storage_buffer
* SPV_KHR_vulkan_memory_model
* SPV_KHR_compute_shader_derivatives
* SPV_NV_compute_shader_derivatives
* SPV_KHR_maximal_reconvergence
* SPV_KHR_float_controls
* SPV_NV_shader_subgroup_partitioned
* SPV_KHR_quad_control
* SPV_KHR_untyped_pointers
* SPV_EXT_descriptor_heap
* SPV_KHR_fma
* SPV_KHR_abort
* SPV_KHR_constant_data
* SPV_QCOM_image_processing3
* SPV_QCOM_multiple_wait_queues
* SPV_NV_push_constant_bank
* SPV_VALVE_mixed_float_dot_product
* SPV_ARM_cooperative_matrix_layouts
* SPV_ARM_tensors
* SPV_NV_cooperative_vector
* SPV_NV_cooperative_matrix2
* SPV_NV_tensor_addressing
* SPV_NV_cooperative_matrix_decode_vector

* ``VK_EXT_shader_uniform_buffer_unsized_array`` has no matching SPIR-V
  ``OpExtension``: it relaxes a rule of the Vulkan SPIR-V environment and reuses
  ``OpTypeRuntimeArray``, so there is no extension string to allow and nothing is
  added to the module header. DXC supports its uniform buffer rule with
  ``-fspv-enable-uniform-buffer-unsized-array``; see `Unsized array as the last
  uniform buffer member`_ above.

Vulkan specific attributes
--------------------------

`C++ attribute specifier sequence <http://en.cppreference.com/w/cpp/language/attributes>`_
is a non-intrusive way of providing Vulkan specific information in HLSL.

The namespace ``vk`` will be used for all Vulkan attributes:

- ``location(X)``: For specifying the location (``X``) numbers for stage
  input/output variables. Allowed on function parameters, function returns,
  and struct fields.
- ``binding(X[, Y])``: For specifying the descriptor set (``Y``) and binding
  (``X``) numbers for resource variables. The descriptor set (``Y``) is
  optional; if missing, it will be set to 0. Allowed on global variables.
- ``counter_binding(X)``: For specifying the binding number (``X``) for the
  associated counter for RW/Append/Consume structured buffer. The descriptor
  set number for the associated counter is always the same as the main resource.
- ``push_constant``: For marking a variable as the push constant block. Allowed
  on global variables of struct type. At most one variable can be marked as
  ``push_constant`` in a shader, unless ``SPV_NV_push_constant_bank`` is enabled,
  in which case it is at most one per bank. See `Push constant banks`_ above.
- ``push_constant_bank(X)``: For placing the annotated ``push_constant`` block in
  hardware bank ``X`` (``BankNV``). Requires
  ``-fspv-extension=SPV_NV_push_constant_bank`` and a ``push_constant`` block,
  at most once per declaration. See `Push constant banks`_ above.
- ``push_constant_bank_offset(X)``: For adding the base byte offset ``X`` to every
  member offset of the annotated ``push_constant`` block (``MemberOffsetNV``).
  Requires ``-fspv-extension=SPV_NV_push_constant_bank`` and a ``push_constant``
  block, at most once per declaration. See `Push constant banks`_ above.
- ``offset(X)``: For manually layout struct members. Annotating a struct member
  with this attribute will force the compiler to put the member at offset ``X``
  w.r.t. the beginning of the struct. Only allowed on struct members.
- ``constant_id(X)``: For marking a global constant as a specialization constant.
  Allowed on global variables of boolean/integer/float types.
- ``input_attachment_index(X)``: To associate the Xth entry in the input pass
  list to the annotated object. Only allowed on objects whose type are
  ``SubpassInput`` or ``SubpassInputMS``.
- ``builtin("X")``: For specifying an entity should be translated into a certain
  Vulkan builtin variable. Allowed on function parameters, function returns,
  and struct fields.
- ``index(X)``: For specifying the index at a specific pixel shader output
  location. Used for dual-source blending.
- ``post_depth_coverage``: The input variable decorated with SampleMask will
  reflect the result of the EarlyFragmentTests. Only valid on pixel shader entry points.
- ``combinedImageSampler``: For specifying a Texture (e.g., ``Texture2D``,
  ``Texture1DArray``, ``TextureCube``) and ``SamplerState`` to use the combined image
  sampler (or sampled image) type with the same descriptor set and binding numbers (see
  `wiki page <https://github.com/microsoft/DirectXShaderCompiler/wiki/Vulkan-combined-image-sampler-type>`_
  for more detail).
- ``early_and_late_tests``: Marks an entry point as enabling early and late depth
  tests. If depth is written via ``SV_Depth``, ``depth_unchanged`` must also be specified
  (``SV_DepthLess`` and ``SV_DepthGreater`` can be written freely). If a stencil reference
  value is written via ``SV_StencilRef``, one of ``stencil_ref_unchanged_front``,
  ``stencil_ref_greater_equal_front``, or ``stencil_ref_less_equal_front`` and
  one of ``stencil_ref_unchanged_back``, ``stencil_ref_greater_equal_back``, or
  ``stencil_ref_less_equal_back`` must be specified.
- ``depth_unchanged``: Specifies that any depth written to ``SV_Depth`` will not
  invalidate the result of early depth tests. Sets the ``DepthUnchanged`` execution
  mode in SPIR-V. Only valid on pixel shader entry points.
- ``stencil_ref_unchanged_front``: Specifies that any stencil ref written to
  ``SV_StencilRef`` will not invalidate the result of early stencil tests when
  the fragment is front facing. Sets the ``StencilRefUnchangedFrontAMD`` execution
  mode in SPIR-V. Only valid on pixel shader entry points.
- ``stencil_ref_greater_equal_front``: Specifies that any stencil ref written to
  ``SV_StencilRef`` will be greater than or equal to the stencil reference value
  set by the API when the fragment is front facing. Sets the ``StencilRefGreaterFrontAMD``
  execution mode in SPIR-V. Only valid on pixel shader entry points.
- ``stencil_ref_less_equal_front``: Specifies that any stencil ref written to
  ``SV_StencilRef`` will be less than or equal to the stencil reference value
  set by the API when the fragment is front facing. Sets the ``StencilRefLessFrontAMD``
  execution mode in SPIR-V. Only valid on pixel shader entry points.
- ``stencil_ref_unchanged_back``: Specifies that any stencil ref written to
  ``SV_StencilRef`` will not invalidate the result of early stencil tests when
  the fragment is back facing. Sets the ``StencilRefUnchangedBackAMD`` execution
  mode in SPIR-V. Only valid on pixel shader entry points.
- ``stencil_ref_greater_equal_back``: Specifies that any stencil ref written to
  ``SV_StencilRef`` will be greater than or equal to the stencil reference value
  set by the API when the fragment is back facing. Sets the ``StencilRefGreaterBackAMD``
  execution mode in SPIR-V. Only valid on pixel shader entry points.
- ``stencil_ref_less_equal_back``: Specifies that any stencil ref written to
  ``SV_StencilRef`` will be less than or equal to the stencil reference value
  set by the API when the fragment is back facing. Sets the ``StencilRefLessBackAMD``
  execution mode in SPIR-V. Only valid on pixel shader entry points.
- ``multiple_wait_queues[([N])]``: For marking a loop as a candidate for multiple
  hardware wait queues. Sets the ``MultipleWaitQueuesQCOM`` loop control bit on the
  annotated loop's ``OpLoopMerge``, with the optional ``N`` as the maximum number of
  wait queues (``0``, the default, means all available). Only valid on ``for``,
  ``while`` and ``do`` statements, at most once per statement. See
  `Multiple wait queues`_ above.

Only ``vk::`` attributes in the above list are supported. Other attributes will
result in warnings and be ignored by the compiler. All C++11 attributes will
only trigger warnings and be ignored if not compiling towards SPIR-V.

For example, to specify the layout of resource variables and the location of
interface variables:

.. code:: hlsl

  struct S { ... };

  [[vk::binding(X, Y), vk::counter_binding(Z)]]
  RWStructuredBuffer<S> mySBuffer;

  [[vk::location(M)]] float4
  main([[vk::location(N)]] float4 input: A) : B
  { ... }

Macros for SPIR-V
-----------------

If SPIR-V CodeGen is enabled and ``-spirv`` flag is used as one of the command
line options (meaning that "generates SPIR-V code"), it defines an implicit
macro ``__spirv__``. For example, this macro definition can be used for SPIR-V
specific part of the HLSL code:

.. code:: hlsl

  #ifdef __spirv__
  [[vk::binding(X, Y), vk::counter_binding(Z)]]
  #endif
  RWStructuredBuffer<S> mySBuffer;

When the ``-spirv`` flag is used, the ``-fspv-target-env`` option will
implicitly define the macros ``__SPIRV_MAJOR_VERSION__`` and
``__SPIRV_MINOR_VERSION__``, which will be integers representing the major and
minor version of the SPIR-V being generated. This can be used to enable code that uses a feature
only for environments where that feature is available.

SPIR-V version and extension
----------------------------

SPIR-V CodeGen provides two command-line options for fine-grained SPIR-V target
environment (hence SPIR-V version) and SPIR-V extension control:

- ``-fspv-target-env=``: for specifying SPIR-V target environment
- ``-fspv-extension=``: for specifying allowed SPIR-V extensions

``-fspv-target-env=`` accepts a Vulkan target environment (see ``-help`` for
supported values). If such an option is not given, the CodeGen defaults to
``vulkan1.0``. When targeting ``vulkan1.0``, trying to use features that are only
available in Vulkan 1.1 (SPIR-V 1.3), like `Shader Model 6.0 wave intrinsic <https://github.com/microsoft/directxshadercompiler/wiki/wave-intrinsics>`_,
will trigger a compiler error.

If ``-fspv-extension=`` is not specified, the CodeGen will select suitable
SPIR-V extensions to translate the source code. Otherwise, only extensions
supplied via ``-fspv-extension=`` will be used. If that does not suffice, errors
will be emitted explaining what additional extensions are required to translate
what specific feature in the source code. If you want to allow all KHR
extensions, you can use ``-fspv-extension=KHR``.

``-fspv-enable-uniform-buffer-unsized-array`` is the same kind of option for
``VK_EXT_shader_uniform_buffer_unsized_array``: the extension adds no SPIR-V
instruction and no capability, it only lets the last member of a uniform buffer
block be an unsized array, so neither a target environment nor an extension
string can express it. It is off by default; see `Unsized array as the last
uniform buffer member`_ for the emitted types, the restrictions and the host
requirements.

``-fspv-constant-data[=<threshold>]`` selects the ``OpConstantDataKHR`` encoding
for integer array constants (``SPV_KHR_constant_data``); it is off by default and
requires ``-fspv-extension=SPV_KHR_constant_data``, see `Constant data arrays`_
above.

``-fspv-enable-maintenance9`` is a third, independent kind of option: it is not
a version and not an extension, but a statement about the *device*. It declares
that ``VK_KHR_maintenance9`` (feature bit ``maintenance9``) is enabled, which
lets the five bitwise instructions that the Vulkan environment restricted to
32-bit Base operands (``OpBitReverse``, ``OpBitCount``, ``OpBitFieldInsert``,
``OpBitFieldSExtract``, ``OpBitFieldUExtract``) keep the natural width of a
narrow or 64-bit operand instead of being emulated. It changes the generated
instruction stream, so it is off by default; see `Narrow integer bitwise
operations`_ above for the exact before/after sequences and for the host
requirements.

Legalization, optimization, validation
--------------------------------------

After initial translation of the HLSL source code, SPIR-V CodeGen will further
conduct legalization (if needed), optimization (if requested), and validation
(if not turned off). All these three stages are outsourced to `SPIRV-Tools <https://github.com/KhronosGroup/SPIRV-Tools>`_.
Here are the options controlling these stages:

* ``-fcgl``: turn off legalization and optimization
* ``-Od``: turn off optimization
* ``-Vd``: turn off validation

Legalization
~~~~~~~~~~~~

HLSL is a fairly permissive language considering the flexibility it provides for
manipulating resource objects. The developer can create local copies, pass
them around as function parameters and return values, as long as after certain
transformations (function inlining, constant evaluation and propagating, dead
code elimination, etc.), the compiler can remove all temporary copies and
pinpoint all uses to unique global resource objects.

Resulting from the above property of HLSL, if we translate into SPIR-V for
Vulkan literally from the input HLSL source code, we will sometimes generate
illegal SPIR-V. Certain transformations are needed to legalize the literally
translated SPIR-V. Performing such transformations at the frontend AST level
is cumbersome or impossible (e.g., function inlining). They are better to be
conducted at SPIR-V level. Therefore, legalization is delegated to SPIRV-Tools.

Specifically, we need to legalize the following HLSL source code patterns:

* Using resource types in struct types
* Creating aliases of global resource objects
* Control flows invovling the above cases

Legalization transformations will not run unless the above patterns are
encountered in the source code.

For more details, please see the `SPIR-V cookbook <https://github.com/Microsoft/DirectXShaderCompiler/tree/main/docs/SPIRV-Cookbook.rst>`_,
which contains examples of what HLSL code patterns will be accepted and
generate valid SPIR-V for Vulkan.

Optimization
~~~~~~~~~~~~

Optimization is also delegated to SPIRV-Tools. Right now there are no difference
between optimization levels greater than zero; they will all invoke the same
optimization recipe. That is, the recipe behind ``spirv-opt -O``.  If you want to
run a custom optimization recipe, you can do so using the command line option
``-Oconfig=`` and specifying a comma-separated list of your desired passes.
The passes are invoked in the specified order.

For example, you can specify ``-Oconfig=--loop-unroll,--scalar-replacement=300,--eliminate-dead-code-aggressive``
to firstly invoke loop unrolling, then invoke scalar replacement of aggregates,
lastly invoke aggressive dead code elimination. All valid options to
``spirv-opt`` are accepted as components to the comma-separated list.

Here are the typical passes in alphabetical order:

* ``--ccp``
* ``--cfg-cleanup``
* ``--convert-local-access-chains``
* ``--copy-propagate-arrays``
* ``--eliminate-dead-branches``
* ``--eliminate-dead-code-aggressive``
* ``--eliminate-dead-functions``
* ``--eliminate-local-multi-store``
* ``--eliminate-local-single-block``
* ``--eliminate-local-single-store``
* ``--flatten-decorations``
* ``--if-conversion``
* ``--inline-entry-points-exhaustive``
* ``--local-redundancy-elimination``
* ``--loop-fission``
* ``--loop-fusion``
* ``--loop-unroll``
* ``--loop-unroll-partial=[<n>]``
* ``--loop-peeling`` (requires ``--loop-peeling-threshold``)
* ``--merge-blocks``
* ``--merge-return``
* ``--loop-unswitch``
* ``--private-to-local``
* ``--reduce-load-size``
* ``--redundancy-elimination``
* ``--remove-duplicates``
* ``--replace-invalid-opcode``
* ``--ssa-rewrite``
* ``--scalar-replacement[=<n>]``
* ``--simplify-instructions``
* ``--vector-dce``


Besides, there are two special batch options; each stands for a recommended
recipe by itself:

* ``-O``: A bunch of passes in an appropriate order that attempt to improve
  performance of generated code. Same as ``spirv-opt -O``. Also same as SPIR-V
  CodeGen's default recipe.
* ``-Os``: A bunch of passes in an appropriate order that attempt to reduce the
  size of the generated code. Same as ``spirv-opt -Os``.

So if you want to run loop unrolling additionally after the default optimization
recipe, you can specify ``-Oconfig=-O,--loop-unroll``.

For the whole list of accepted passes and details about each one, please see
``spirv-opt``'s help manual (``spirv-opt --help``), or the SPIRV-Tools `optimizer header file <https://github.com/KhronosGroup/SPIRV-Tools/blob/main/include/spirv-tools/optimizer.hpp>`_.

Validation
~~~~~~~~~~

Validation is turned on by default as the last stage of SPIR-V CodeGen. Failing
validation, which indicates there is a CodeGen bug, will trigger a fatal error.
Please file an issue if you see that.

Debugging
---------

By default, the compiler will only emit names for types and variables as debug
information, to aid reading of the generated SPIR-V. The ``-Zi`` option will
let the compiler emit the following additional debug information:

* Full path of the main source file using ``OpSource``
* Preprocessed source code using ``OpSource`` and ``OpSourceContinued``
* Line information for certain instructions using ``OpLine`` (WIP)
* DXC Git commit hash using ``OpModuleProcessed`` (requires Vulkan 1.1)
* DXC command-line options used to compile the shader using ``OpModuleProcessed``
  (requires Vulkan 1.1)

We chose to embed preprocessed source code instead of original source code to
avoid pulling in lots of contents unrelated to the current entry point, and
boilerplate contents generated by engines. We may add a mode for selecting
between preprocessed single source code and original separated source code in
the future.

One thing to note is that to keep the line numbers in consistent with the
embedded source, the compiler is invoked twice; the first time is for
preprocessing the source code, and the second time is for feeding the
preprocessed source code as input for a whole compilation. So using ``-Zi``
means performance penality.

If you want to have fine-grained control over the categories of emitted debug
information, you can use ``-fspv-debug=``. It accepts:

* ``file``: for emitting full path of the main source file
* ``source``: for emitting preprocessed source code (turns on ``file`` implicitly)
* ``line``: for emitting line information (turns on ``source`` implicitly)
* ``tool``: for emitting DXC Git commit hash and command-line options

These ``-fspv-debug=`` options overrule ``-Zi``. And you can provide multiple
instances of ``-fspv-debug=``. For example, you can use ``-fspv-debug=file
-fspv-debug=tool`` to turn on emitting file path and DXC information; source
code and line information will not be emitted.

If you want to generate `NonSemantic.Shader.DebugInfo.100 <http://htmlpreview.github.io/?https://github.com/KhronosGroup/SPIRV-Registry/blob/main/nonsemantic/NonSemantic.Shader.DebugInfo.100.html>`_ extended instructions, you can use
``-fspv-debug=vulkan-with-source``. These instructions support source-level
shader debugging with tools such as RenderDoc, even if the SPIR-V is optimized.
This option overrules the other ``-fspv-debug`` options above.

Reflection
----------

Making reflection easier is one of the goals of SPIR-V CodeGen. This section
provides guidelines about how to reflect on certain facts.

Note that we generate ``OpName``/``OpMemberName`` instructions for various
types/variables both explicitly defined in the source code and interally created
by the compiler. These names are primarily for debugging purposes in the
compiler. They have "no semantic impact and can safely be removed" according
to the SPIR-V spec. And they are subject to changes without notice. So we do
not suggest to use them for reflection.

Source code shader profile
~~~~~~~~~~~~~~~~~~~~~~~~~~

The source code shader profile version can be re-discovered by the "Version"
operand in ``OpSource`` instruction. For ``*s_<major>_<minor>``, the "Verison"
operand in ``OpSource`` will be set as ``<major>`` * 100 + ``<minor>`` * 10.
For example, ``vs_5_1`` will have 510, ``ps_6_2`` will have 620.

HLSL Semantic
~~~~~~~~~~~~~

HLSL semantic strings are by default not emitted into the SPIR-V binary module.
If you need them, by specifying ``-fspv-reflect``, the compiler will use
the ``Op*DecorateStringGOOGLE`` instruction in `SPV_GOOGLE_hlsl_funtionality1 <https://github.com/KhronosGroup/SPIRV-Registry/blob/main/extensions/GOOGLE/SPV_GOOGLE_hlsl_functionality1.asciidoc>`_
extension to emit them.

HLSL User Types
~~~~~~~~~~~~~~~

HLSL type information is by default not emitted into the SPIR-V binary module.
If you need them, by specifying ``-fspv-reflect``, the compiler will emit
``OpDecorateString*`` instructions with a ``UserTypeGOOGLE`` decoration and the
`SPV_GOOGLE_user_type <https://github.com/KhronosGroup/SPIRV-Registry/blob/main/extensions/GOOGLE/SPV_GOOGLE_user_type.asciidoc>`_
extension. A string name for the unambiguous type of the decorated object will
be included in the user's source using the lowercase type name followed by
template params. For example, ``Texture2DMSArray<float4, 64> arr`` would be
decorated with ``OpDecorateString %arr UserTypeGOOGLE "texture2dmsarray:<float4,64>"``.

Counter buffers for RW/Append/Consume StructuredBuffer
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

The association between a counter buffer and its main RW/Append/Consume
StructuredBuffer is conveyed by ``OpDecorateId <structured-buffer-id>
HLSLCounterBufferGOOGLE <counter-buffer-id>`` instruction from the
`SPV_GOOGLE_hlsl_funtionality1 <https://github.com/KhronosGroup/SPIRV-Registry/blob/main/extensions/GOOGLE/SPV_GOOGLE_hlsl_functionality1.asciidoc>`_
extension. This information is by default missing; you need to specify
``-fspv-reflect`` to direct the compiler to emit them.

Read-only vs. read-write resource types
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

There are no clear and consistent decorations in the SPIR-V to show whether a
resource type is translated from a read-only (RO) or read-write (RW) HLSL
resource type. Instead, you need to use different checks for reflecting different
resource types:

* HLSL samplers: RO.
* HLSL ``Buffer``/``RWBuffer``/``Texture*``/``RWTexture*``: Check the "Sampled"
  operand in the ``OpTypeImage`` instruction they translated into. "2" means RW,
  "1" means RO.
* HLSL constant/texture/structured/byte buffers: Check both ``Block``/``BufferBlock``
  and ``NonWritable`` decoration. If decorated with ``Block`` (``cbuffer`` &
  ``ConstantBuffer``), then RO; if decorated with ``BufferBlock`` and ``NonWritable``
  (``tbuffer``, ``TextureBuffer``, ``StructuredBuffer``), then RO; Otherwise, RW.


HLSL Types
==========

This section lists how various HLSL types are mapped.

Normal scalar types
-------------------

`Normal scalar types <https://msdn.microsoft.com/en-us/library/windows/desktop/bb509646(v=vs.85).aspx>`_
in HLSL are relatively easy to handle and can be mapped directly to SPIR-V
type instructions:

============================== ======================= ================== ===========
      HLSL                      Command Line Option           SPIR-V       Capability
============================== ======================= ================== ===========
``bool``                                               ``OpTypeBool``
``int``/``int32_t``                                    ``OpTypeInt 32 1``
``int16_t``                    ``-enable-16bit-types`` ``OpTypeInt 16 1`` ``Int16``
``uint``/``dword``/``uin32_t``                         ``OpTypeInt 32 0``
``uint16_t``                   ``-enable-16bit-types`` ``OpTypeInt 16 0`` ``Int16``
``half``                                               ``OpTypeFloat 32``
``half``/``float16_t``         ``-enable-16bit-types`` ``OpTypeFloat 16`` ``Float16``
``float``/``float32_t``                                ``OpTypeFloat 32``
``snorm float``                                        ``OpTypeFloat 32``
``unorm float``                                        ``OpTypeFloat 32``
``double``/``float64_t``                               ``OpTypeFloat 64`` ``Float64``
============================== ======================= ================== ===========

Please note that ``half`` is translated into 32-bit floating point numbers
if without ``-enable-16bit-types`` because MSDN says that "this data type
is provided only for language compatibility. Direct3D 10 shader targets map
all ``half`` data types to ``float`` data types."

Minimal precision scalar types
------------------------------

HLSL also supports various
`minimal precision scalar types <https://msdn.microsoft.com/en-us/library/windows/desktop/bb509646(v=vs.85).aspx>`_,
which graphics drivers can implement by using any precision greater than or
equal to their specified bit precision.
There are no direct mappings in SPIR-V for these types. We translate them into
the corresponding 16-bit or 32-bit scalar types with the ``RelaxedPrecision`` decoration.
We use the 16-bit variants if '-enable-16bit-types' command line option is present.
For more information on these types, please refer to:
https://github.com/Microsoft/DirectXShaderCompiler/wiki/16-Bit-Scalar-Types

============== ======================= ================== ==================== ============
    HLSL        Command Line Option          SPIR-V            Decoration       Capability 
============== ======================= ================== ==================== ============
``min16float``                         ``OpTypeFloat 32`` ``RelaxedPrecision``
``min10float``                         ``OpTypeFloat 32`` ``RelaxedPrecision``
``min16int``                           ``OpTypeInt 32 1`` ``RelaxedPrecision``
``min12int``                           ``OpTypeInt 32 1`` ``RelaxedPrecision``
``min16uint``                          ``OpTypeInt 32 0`` ``RelaxedPrecision``
``min16float`` ``-enable-16bit-types`` ``OpTypeFloat 16``                      ``Float16`` 
``min10float`` ``-enable-16bit-types`` ``OpTypeFloat 16``                      ``Float16`` 
``min16int``   ``-enable-16bit-types`` ``OpTypeInt 16 1``                      ``Int16``
``min12int``   ``-enable-16bit-types`` ``OpTypeInt 16 1``                      ``Int16``
``min16uint``  ``-enable-16bit-types`` ``OpTypeInt 16 0``                      ``Int16``
============== ======================= ================== ==================== ============

Vectors and matrices
--------------------

`Vectors <https://msdn.microsoft.com/en-us/library/windows/desktop/bb509707(v=vs.85).aspx>`_
and `matrices <https://msdn.microsoft.com/en-us/library/windows/desktop/bb509623(v=vs.85).aspx>`_
are translated into:

==================================== ====================================================
              HLSL                                         SPIR-V
==================================== ====================================================
``|type|N`` (``N`` > 1)              ``OpTypeVector |type| N``
``|type|1``                          The scalar type for ``|type|``
``|type|MxN`` (``M`` > 1, ``N`` > 1) ``%v = OpTypeVector |type| N`` ``OpTypeMatrix %v M``
``|type|Mx1`` (``M`` > 1)            ``OpTypeVector |type| M``
``|type|1xN`` (``N`` > 1)            ``OpTypeVector |type| N``
``|type|1x1``                        The scalar type for ``|type|``
==================================== ====================================================

The above table is for float matrices.

A MxN HLSL float matrix is translated into a SPIR-V matrix with M vectors, each with
N elements. Conceptually HLSL matrices are row-major while SPIR-V matrices are
column-major, thus all HLSL matrices are represented by their transposes.
Doing so may require special handling of certain matrix operations:

- **Indexing**: no special handling required. ``matrix[m][n]`` will still access
  the correct element since ``m``/``n`` means the ``m``-th/``n``-th row/column
  in HLSL but ``m``-th/``n``-th vector/element in SPIR-V.
- **Per-element operation**: no special handling required.
- **Matrix multiplication**: need to swap the operands. ``mat1 x mat2`` should
  be translated as ``transpose(mat2) x transpose(mat1)``. Then the result is
  ``transpose(mat1 x mat2)``.
- **Storage layout**: ``row_major``/``column_major`` will be translated into
  SPIR-V ``ColMajor``/``RowMajor`` decoration. This is because HLSL matrix
  row/column becomes SPIR-V matrix column/row. If elements in a row/column are
  packed together, they should be loaded into a column/row correspondingly.

See `Appendix A. Matrix Representation`_ for further explanation regarding these design choices.

Since the ``Shader`` capability in SPIR-V does not allow to parameterize matrix
types with non-floating-point types, a non-floating-point MxN matrix is translated
into an array with M elements, with each element being a vector with N elements.

Structs
-------

`Structs <https://msdn.microsoft.com/en-us/library/windows/desktop/bb509668(v=vs.85).aspx>`_
in HLSL are defined in the a format similar to C structs. They are translated
into SPIR-V ``OpTypeStruct``. Depending on the storage classes of the instances,
a single struct definition may generate multiple ``OpTypeStruct`` instructions
in SPIR-V. For example, for the following HLSL source code:

.. code:: hlsl

  struct S { ... }

  ConstantBuffer<S>   myCBuffer;
  StructuredBuffer<S> mySBuffer;

  float4 main() : A {
    S myLocalVar;
    ...
  }

There will be three different ``OpTypeStruct`` generated, one for each variable
defined in the above source code. This is because the ``OpTypeStruct`` for
both ``myCBuffer`` and ``mySBuffer`` will have layout decorations (``Offset``,
``MatrixStride``, ``ArrayStride``, ``RowMajor``, ``ColMajor``). However, their
layout rules are different (by default); ``myCBuffer`` will use vector-relaxed
OpenGL ``std140`` while ``mySBuffer`` will use vector-relaxed OpenGL ``std430``.
``myLocalVar`` will have its ``OpTypeStruct`` without layout decorations.
Read more about storage classes in the `Constant/Texture/Structured/Byte Buffers`_
section.

Structs used as stage inputs/outputs will have semantics attached to their
members. These semantics are handled in the `entry function wrapper`_.

Structs used as pixel shader inputs can have optional interpolation modifiers
for their members, which will be translated according to the following table:

=========================== ================= =====================
HLSL Interpolation Modifier SPIR-V Decoration   SPIR-V Capability
=========================== ================= =====================
``linear``                  <none>
``centroid``                ``Centroid``
``nointerpolation``         ``Flat``
``noperspective``           ``NoPerspective``
``sample``                  ``Sample``        ``SampleRateShading``
=========================== ================= =====================

Arrays
------

Sized (either explicitly or implicitly) arrays are translated into SPIR-V
`OpTypeArray`. Unsized arrays are translated into `OpTypeRuntimeArray`.

Arrays, if used for external resources (residing in SPIR-V `Uniform` or
`UniformConstant` storage class), will need layout decorations like SPIR-V
`ArrayStride` decoration. For arrays of opaque types, e.g., HLSL textures
or samplers, we don't decorate with `ArrayStride` decorations since there is
no meaningful strides. Similarly for arrays of structured/byte buffers.

User-defined types
------------------

`User-defined types <https://msdn.microsoft.com/en-us/library/windows/desktop/bb509702(v=vs.85).aspx>`_
are type aliases introduced by typedef. No new types are introduced and we can
rely on Clang to resolve to the original types.

Samplers
--------

All `sampler types <https://msdn.microsoft.com/en-us/library/windows/desktop/bb509644(v=vs.85).aspx>`_
will be translated into SPIR-V ``OpTypeSampler``.

SPIR-V ``OpTypeSampler`` is an opaque type that cannot be parameterized;
therefore state assignments on sampler types is not supported (yet).

Textures
--------

`Texture types <https://msdn.microsoft.com/en-us/library/windows/desktop/bb509700(v=vs.85).aspx>`_
are translated into SPIR-V ``OpTypeImage``, with parameters:

======================= ==================== ===== =================== ========== ===== ======= == ======= ================ =================
       HLSL                   Vulkan                                        SPIR-V
----------------------- -------------------------- ------------------------------------------------------------------------------------------
     Texture Type         Descriptor Type    RO/RW    Storage Class        Dim    Depth Arrayed MS Sampled   Image Format      Capability
======================= ==================== ===== =================== ========== ===== ======= == ======= ================ =================
``Texture1D``           Sampled Image         RO   ``UniformConstant`` ``1D``      2       0    0    1     ``Unknown``
``Texture2D``           Sampled Image         RO   ``UniformConstant`` ``2D``      2       0    0    1     ``Unknown``
``Texture3D``           Sampled Image         RO   ``UniformConstant`` ``3D``      2       0    0    1     ``Unknown``
``TextureCube``         Sampled Image         RO   ``UniformConstant`` ``Cube``    2       0    0    1     ``Unknown``
``Texture1DArray``      Sampled Image         RO   ``UniformConstant`` ``1D``      2       1    0    1     ``Unknown``
``Texture2DArray``      Sampled Image         RO   ``UniformConstant`` ``2D``      2       1    0    1     ``Unknown``
``Texture2DMS``         Sampled Image         RO   ``UniformConstant`` ``2D``      2       0    1    1     ``Unknown``
``Texture2DMSArray``    Sampled Image         RO   ``UniformConstant`` ``2D``      2       1    1    1     ``Unknown``
``TextureCubeArray``    Sampled Image         RO   ``UniformConstant`` ``3D``      2       1    0    1     ``Unknown``
``Buffer<T>``           Uniform Texel Buffer  RO   ``UniformConstant`` ``Buffer``  2       0    0    1     Depends on ``T`` ``SampledBuffer``
``RWBuffer<T>``         Storage Texel Buffer  RW   ``UniformConstant`` ``Buffer``  2       0    0    2     Depends on ``T`` ``SampledBuffer``
``RWTexture1D<T>``      Storage Image         RW   ``UniformConstant`` ``1D``      2       0    0    2     Depends on ``T``
``RWTexture2D<T>``      Storage Image         RW   ``UniformConstant`` ``2D``      2       0    0    2     Depends on ``T``
``RWTexture3D<T>``      Storage Image         RW   ``UniformConstant`` ``3D``      2       0    0    2     Depends on ``T``
``RWTexture1DArray<T>`` Storage Image         RW   ``UniformConstant`` ``1D``      2       1    0    2     Depends on ``T``
``RWTexture2DArray<T>`` Storage Image         RW   ``UniformConstant`` ``2D``      2       1    0    2     Depends on ``T``
======================= ==================== ===== =================== ========== ===== ======= == ======= ================ =================

The meanings of the headers in the above table is explained in ``OpTypeImage``
of the SPIR-V spec.

For storage images (e.g. ``RWTexture2D<T>``) and texel buffers (e.g. ``RWBuffer<T>``),
the image format is typically inferred from the data type ``T``. However, the
``-fspv-use-unknown-image-format`` command-line option can be used to change
this behavior. When this option is active, the default format for these
resources becomes ``Unknown`` if not otherwise specified by the
``[[vk::image_format]]`` attribute.

Vulkan specific Image Formats
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

Since HLSL lacks the syntax for fully specifying image formats for textures in
SPIR-V, we introduce ``[[vk::image_format("FORMAT")]]`` attribute for texture types.
For example,

.. code:: hlsl

  [[vk::image_format("rgba8")]]
  RWBuffer<float4> Buf;

  [[vk::image_format("rg16f")]]
  RWTexture2D<float2> Tex;

  RWTexture2D<float2> Tex2; // Works like before

``rgba8`` means ``Rgba8`` `SPIR-V Image Format <https://registry.khronos.org/SPIR-V/specs/unified1/SPIRV.html#Image_Format>`_.
The following table lists the mapping between ``FORMAT`` of
``[[vk::image_format("FORMAT")]]`` and its corresponding SPIR-V Image Format.

======================= ============================================
       FORMAT                   SPIR-V Image Format
======================= ============================================
``unknown``             ``Unknown``
``rgba32f``             ``Rgba32f``
``rgba16f``             ``Rgba16f``
``r32f``                ``R32f``
``rgba8``               ``Rgba8``
``rgba8snorm``          ``Rgba8Snorm``
``rg32f``               ``Rg32f``
``rg16f``               ``Rg16f``
``r11g11b10f``          ``R11fG11fB10f``
``r16f``                ``R16f``
``rgba16``              ``Rgba16``
``rgb10a2``             ``Rgb10A2``
``rg16``                ``Rg16``
``rg8``                 ``Rg8``
``r16``                 ``R16``
``r8``                  ``R8``
``rgba16snorm``         ``Rgba16Snorm``
``rg16snorm``           ``Rg16Snorm``
``rg8snorm``            ``Rg8Snorm``
``r16snorm``            ``R16Snorm``
``r8snorm``             ``R8Snorm``
``rgba32i``             ``Rgba32i``
``rgba16i``             ``Rgba16i``
``rgba8i``              ``Rgba8i``
``r32i``                ``R32i``
``rg32i``               ``Rg32i``
``rg16i``               ``Rg16i``
``rg8i``                ``Rg8i``
``r16i``                ``R16i``
``r8i``                 ``R8i``
``rgba32ui``            ``Rgba32ui``
``rgba16ui``            ``Rgba16ui``
``rgba8ui``             ``Rgba8ui``
``r32ui``               ``R32ui``
``rgb10a2ui``           ``Rgb10a2ui``
``rg32ui``              ``Rg32ui``
``rg16ui``              ``Rg16ui``
``rg8ui``               ``Rg8ui``
``r16ui``               ``R16ui``
``r8ui``                ``R8ui``
``r64ui``               ``R64ui``
``r64i``                ``R64i``
======================= ============================================

Constant/Texture/Structured/Byte Buffers
----------------------------------------

There are serveral buffer types in HLSL:

- ``cbuffer`` and ``ConstantBuffer``
- ``tbuffer`` and ``TextureBuffer``
- ``StructuredBuffer`` and ``RWStructuredBuffer``
- ``AppendStructuredBuffer`` and ``ConsumeStructuredBuffer``
- ``ByteAddressBuffer`` and ``RWByteAddressBuffer``

Note that ``Buffer`` and ``RWBuffer`` are considered as texture object in HLSL.
They are listed in the above section.

Please see the following sections for the details of each type. As a summary:

=========================== ================== ================================ ==================== =================
         HLSL Type          Vulkan Buffer Type    Default Memory Layout Rule    SPIR-V Storage Class SPIR-V Decoration
=========================== ================== ================================ ==================== =================
``cbuffer``                   Uniform Buffer   Vector-relaxed OpenGL ``std140``      ``Uniform``     ``Block``
``ConstantBuffer``            Uniform Buffer   Vector-relaxed OpenGL ``std140``      ``Uniform``     ``Block``
``tbuffer``                   Storage Buffer   Vector-relaxed OpenGL ``std430``      ``Uniform``     ``BufferBlock``
``TextureBuffer``             Storage Buffer   Vector-relaxed OpenGL ``std430``      ``Uniform``     ``BufferBlock``
``StructuredBuffer``          Storage Buffer   Vector-relaxed OpenGL ``std430``      ``Uniform``     ``BufferBlock``
``RWStructuredBuffer``        Storage Buffer   Vector-relaxed OpenGL ``std430``      ``Uniform``     ``BufferBlock``
``AppendStructuredBuffer``    Storage Buffer   Vector-relaxed OpenGL ``std430``      ``Uniform``     ``BufferBlock``
``ConsumeStructuredBuffer``   Storage Buffer   Vector-relaxed OpenGL ``std430``      ``Uniform``     ``BufferBlock``
``ByteAddressBuffer``         Storage Buffer   Vector-relaxed OpenGL ``std430``      ``Uniform``     ``BufferBlock``
``RWByteAddressBuffer``       Storage Buffer   Vector-relaxed OpenGL ``std430``      ``Uniform``     ``BufferBlock``
=========================== ================== ================================ ==================== =================

To know more about the Vulkan buffer types, please refer to the Vulkan spec
`14.1 Descriptor Types <https://registry.khronos.org/vulkan/specs/latest/html/vkspec.html#descriptorsets-types>`_.

Memory layout rules
~~~~~~~~~~~~~~~~~~~

SPIR-V CodeGen supports four sets of memory layout rules for buffer resources
right now:

1. Vector-relaxed OpenGL ``std140`` for uniform buffers and vector-relaxed
   OpenGL ``std430`` for storage buffers: these rules satisfy Vulkan `"Standard
   Uniform Buffer Layout" and "Standard Storage Buffer Layout" <https://registry.khronos.org/vulkan/specs/latest/html/vkspec.html#interfaces-resources-layout>`_,
   respectively.
   They are the default.
2. DirectX memory layout rules for uniform buffers and storage buffers:
   they allow packing data on the application side that can be shared with
   DirectX. They can be enabled by ``-fvk-use-dx-layout``.
   
   NOTE: This requires ``VK_EXT_scalar_block_layout`` to be enabled on the
   application side.
3. Strict OpenGL ``std140`` for uniform buffers and strict OpenGL ``std430``
   for storage buffers: they allow packing data on the application side that
   can be shared with OpenGL. They can be enabled by ``-fvk-use-gl-layout``.
4. Scalar layout rules introduced via `VK_EXT_scalar_block_layout`, which
   basically aligns all aggregrate types according to their elements'
   natural alignment. They can be enabled by ``-fvk-use-scalar-layout``.
   
   NOTE: This requires ``VK_EXT_scalar_block_layout`` to be enabled on the
   application side.

In the above, "vector-relaxed OpenGL ``std140``/``std430``" rules mean OpenGL
``std140``/``std430`` rules with the following modification for vector type
alignment:

1. The alignment of a vector type is set to be the alignment of its element type
2. If the above causes an `improper straddle <https://registry.khronos.org/vulkan/specs/latest/html/vkspec.html#interfaces-resources-layout>`_,
   the alignment will be set to 16 bytes.

As an example, for the following HLSL definition:

.. code:: hlsl

  struct S {
      float3 f;
  };

  struct T {
                float    a_float;
                float3   b_float3;
                S        c_S_float3;
                float2x3 d_float2x3;
      row_major float2x3 e_float2x3;
                int      f_int_3[3];
                float2   g_float2_2[2];
  };

We will have the following offsets for each member:

============== ====== ====== ====== ========== ====== ====== ====== ==========
     HLSL             Uniform Buffer                Storage Buffer
-------------- ------------------------------- -------------------------------
    Member     1 (VK) 2 (DX) 3 (GL) 4 (Scalar) 1 (VK) 2 (DX) 3 (GL) 4 (Scalar)
============== ====== ====== ====== ========== ====== ====== ====== ==========
``a_float``      0      0      0        0        0      0     0        0
``b_float3``     4      4      16       4        4      4     16       4
``c_S_float3``   16     16     32       16       16     16    32       16
``d_float2x3``   32     32     48       28       32     28    48       28
``e_float2x3``   80     80     96       52       64     52    80       52
``f_int_3``      112    112    128      76       96     76    112      76
``g_float2_2``   160    160    176      88       112    88    128      88
============== ====== ====== ====== ========== ====== ====== ====== ==========

If the above layout rules do not satisfy your needs and you want to manually
control the layout of struct members, you can use either

* The native HLSL ``:packoffset()`` attribute: only available for cbuffers; or
* The Vulkan-specific ``[[vk::offset()]]`` attribute: applies to all resources.

``[[vk::offset]]`` overrules ``:packoffset``. Attaching ``[[vk::offset]]``
to a struct memeber affects all variables of the struct type in question. So
sharing the same struct definition having ``[[vk::offset]]`` annotations means
also sharing the layout.

For global variables (which are collected into the ``$Globals`` cbuffer), you
can use the native HLSL ``:register(c#)`` attribute. Note that ``[[vk::offset]]``
and ``:packoffset`` cannot be applied to these variables.

If ``register(cX)`` is used on any global variable, the offset for that variable
is set to ``X * 16``, and the offset for all other global variables without the
``register(c#)`` annotation will be set to the next available address after
the highest explicit address. For example:

.. code:: hlsl

  float x : register(c10);   // Offset = 160 (10 * 16)
  float y;                   // Offset = 164 (160 + 4)
  float z: register(c1);     // Offset = 16  (1  * 16)


These attributes give great flexibility but also responsibility to the
developer; the compiler will just take in what is specified in the source code
and emit it to SPIR-V with no error checking.

``cbuffer`` and ``ConstantBuffer``
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

These two buffer types are treated as uniform buffers using Vulkan's
terminology. They are translated into an ``OpTypeStruct`` with the
necessary layout decorations (``Offset``, ``ArrayStride``, ``MatrixStride``,
``RowMajor``, ``ColMajor``) and the ``Block`` decoration. The layout rule
used is vector-relaxed OpenGL ``std140`` (by default). A variable declared as
one of these types will be placed in the ``Uniform`` storage class.

For example, for the following HLSL source code:

.. code:: hlsl

  struct T {
    float  a;
    float3 b;
  };

  ConstantBuffer<T> myCBuffer;

will be translated into

.. code:: spirv

  ; Layout decoration
  OpMemberDecorate %type_ConstantBuffer_T 0 Offset 0
  OpMemberDecorate %type_ConstantBuffer_T 0 Offset 4
  ; Block decoration
  OpDecorate %type_ConstantBuffer_T Block

  ; Types
  %type_ConstantBuffer_T = OpTypeStruct %float %v3float
  %_ptr_Uniform_type_ConstantBuffer_T = OpTypePointer Uniform %type_ConstantBuffer_T

  ; Variable
  %myCbuffer = OpVariable %_ptr_Uniform_type_ConstantBuffer_T Uniform

``tbuffer`` and ``TextureBuffer``
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

These two buffer types are treated as storage buffers using Vulkan's
terminology. They are translated into an ``OpTypeStruct`` with the
necessary layout decorations (``Offset``, ``ArrayStride``, ``MatrixStride``,
``RowMajor``, ``ColMajor``) and the ``BufferBlock`` decoration. All the struct
members are also decorated with ``NonWritable`` decoration. The layout rule
used is vector-relaxed OpenGL ``std430`` (by default). A variable declared as
one of these types will be placed in the ``Uniform`` storage class.


``StructuredBuffer`` and ``RWStructuredBuffer``
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

``StructuredBuffer<T>``/``RWStructuredBuffer<T>`` is treated as storage buffer
using Vulkan's terminology. It is translated into an ``OpTypeStruct`` containing
an ``OpTypeRuntimeArray`` of type ``T``, with necessary layout decorations
(``Offset``, ``ArrayStride``, ``MatrixStride``, ``RowMajor``, ``ColMajor``) and
the ``BufferBlock`` decoration.  The default layout rule used is vector-relaxed
OpenGL ``std430``. A variable declared as one of these types will be placed in
the ``Uniform`` storage class.

For ``RWStructuredBuffer<T>``, each variable will have an associated counter
variable generated. The counter variable will be of ``OpTypeStruct`` type, which
only contains a 32-bit integer. The counter variable takes its own binding
number. ``.IncrementCounter()``/``.DecrementCounter()`` will modify this counter
variable.

For example, for the following HLSL source code:

.. code:: hlsl

  struct T {
    float  a;
    float3 b;
  };

  StructuredBuffer<T> mySBuffer;

will be translated into

.. code:: spirv

  ; Layout decoration
  OpMemberDecorate %T 0 Offset 0
  OpMemberDecorate %T 1 Offset 4
  OpDecorate %_runtimearr_T ArrayStride 16
  OpMemberDecorate %type_StructuredBuffer_T 0 Offset 0
  OpMemberDecorate %type_StructuredBuffer_T 0 NoWritable
  ; BufferBlock decoration
  OpDecorate %type_StructuredBuffer_T BufferBlock

  ; Types
  %T = OpTypeStruct %float %v3float
  %_runtimearr_T = OpTypeRuntimeArray %T
  %type_StructuredBuffer_T = OpTypeStruct %_runtimearr_T
  %_ptr_Uniform_type_StructuredBuffer_T = OpTypePointer Uniform %type_StructuredBuffer_T

  ; Variable
  %myCbuffer = OpVariable %_ptr_Uniform_type_ConstantBuffer_T Uniform

``AppendStructuredBuffer`` and ``ConsumeStructuredBuffer``
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

``AppendStructuredBuffer<T>``/``ConsumeStructuredBuffer<T>`` is treated as
storage buffer using Vulkan's terminology. It is translated into an
``OpTypeStruct`` containing an ``OpTypeRuntimeArray`` of type ``T``, with
necessary layout decorations (``Offset``, ``ArrayStride``, ``MatrixStride``,
``RowMajor``, ``ColMajor``) and the ``BufferBlock`` decoration. The default
layout rule used is vector-relaxed OpenGL ``std430``.

A variable declared as one of these types will be placed in the ``Uniform``
storage class. Besides, each variable will have an associated counter variable
generated. The counter variable will be of ``OpTypeStruct`` type, which only
contains a 32-bit integer. The integer is the total number of elements in the
buffer. The counter variable takes its own binding number.
``.Append()``/``.Consume()`` will use the counter variable as the index and
adjust it accordingly.

For example, for the following HLSL source code:

.. code:: hlsl

  struct T {
    float  a;
    float3 b;
  };

  AppendStructuredBuffer<T> mySBuffer;

will be translated into

.. code:: spirv

  ; Layout decorations
  OpMemberDecorate %T 0 Offset 0
  OpMemberDecorate %T 1 Offset 4
  OpDecorate %_runtimearr_T ArrayStride 16
  OpMemberDecorate %type_AppendStructuredBuffer_T 0 Offset 0
  OpDecorate %type_AppendStructuredBuffer_T BufferBlock
  OpMemberDecorate %type_ACSBuffer_counter 0 Offset 0
  OpDecorate %type_ACSBuffer_counter BufferBlock

  ; Binding numbers
  OpDecorate %myASbuffer DescriptorSet 0
  OpDecorate %myASbuffer Binding 0
  OpDecorate %counter_var_myASbuffer DescriptorSet 0
  OpDecorate %counter_var_myASbuffer Binding 1

  ; Types
  %T = OpTypeStruct %float %v3float
  %_runtimearr_T = OpTypeRuntimeArray %T
  %type_AppendStructuredBuffer_T = OpTypeStruct %_runtimearr_T
  %_ptr_Uniform_type_AppendStructuredBuffer_T = OpTypePointer Uniform %type_AppendStructuredBuffer_T
  %type_ACSBuffer_counter = OpTypeStruct %int
  %_ptr_Uniform_type_ACSBuffer_counter = OpTypePointer Uniform %type_ACSBuffer_counter

  ; Variables
  %myASbuffer = OpVariable %_ptr_Uniform_type_AppendStructuredBuffer_T Uniform
  %counter_var_myASbuffer = OpVariable %_ptr_Uniform_type_ACSBuffer_counter Uniform

``ByteAddressBuffer`` and ``RWByteAddressBuffer``
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

``ByteAddressBuffer``/``RWByteAddressBuffer`` is treated as storage buffer using
Vulkan's terminology. It is translated into an ``OpTypeStruct`` containing an
``OpTypeRuntimeArray`` of 32-bit unsigned integers, with ``BufferBlock``
decoration.

A variable declared as one of these types will be placed in the ``Uniform``
storage class.

For example, for the following HLSL source code:

.. code:: hlsl

  ByteAddressBuffer   myBuffer1;
  RWByteAddressBuffer myBuffer2;

will be translated into

.. code:: spirv

  ; Layout decorations

  OpDecorate %_runtimearr_uint ArrayStride 4

  OpDecorate %type_ByteAddressBuffer BufferBlock
  OpMemberDecorate %type_ByteAddressBuffer 0 Offset 0
  OpMemberDecorate %type_ByteAddressBuffer 0 NonWritable

  OpDecorate %type_RWByteAddressBuffer BufferBlock
  OpMemberDecorate %type_RWByteAddressBuffer 0 Offset 0

  ; Types

  %_runtimearr_uint = OpTypeRuntimeArray %uint

  %type_ByteAddressBuffer = OpTypeStruct %_runtimearr_uint
  %_ptr_Uniform_type_ByteAddressBuffer = OpTypePointer Uniform %type_ByteAddressBuffer

  %type_RWByteAddressBuffer = OpTypeStruct %_runtimearr_uint
  %_ptr_Uniform_type_RWByteAddressBuffer = OpTypePointer Uniform %type_RWByteAddressBuffer

  ; Variables

  %myBuffer1 = OpVariable %_ptr_Uniform_type_ByteAddressBuffer Uniform
  %myBuffer2 = OpVariable %_ptr_Uniform_type_RWByteAddressBuffer Uniform

Rasterizer Ordered Views
------------------------

The following types are rasterizer ordered views:

* ``RasterizerOrderedBuffer``
* ``RasterizerOrderedByteAddressBuffer``
* ``RasterizerOrderedStructuredBuffer``
* ``RasterizerOrderedTexture1D``
* ``RasterizerOrderedTexture1DArray``
* ``RasterizerOrderedTexture2D``
* ``RasterizerOrderedTexture2DArray``
* ``RasterizerOrderedTexture3D``

These are translated to the same types as their equivalent RW* types - for
example, a ``RasterizerOrderedBuffer`` is translated to the same SPIR-V type as
an ``RWBuffer``. The sole difference lies in how loads and stores to these
values are treated.

The access order guarantee made by ROVs is implemented in SPIR-V using the
`SPV_EXT_fragment_shader_interlock <https://github.com/KhronosGroup/SPIRV-Registry/blob/main/extensions/EXT/SPV_EXT_fragment_shader_interlock.asciidoc>`_.
When you load or store a value from or to a rasterizer ordered view, using
either the ``Load*()`` or ``Store*()`` methods or the indexing operator,
``OpBeginInvocationInterlockEXT`` will be inserted before the first access and
``OpEndInvocationInterlockEXT`` will be inserted after the last access.

An execution mode will be added to the entry point, depending on the sample
frequency, which will be deduced based on the semantics inputted by the entry
point. ``PixelInterlockOrderedEXT`` will be selected by default,
``SampleInterlockOrderedEXT`` will be selected if the ``SV_SampleIndex``
semantic is input, and ``ShadingRateInterlockOrderedEXT`` will be selected if
the ``SV_ShadingRate`` semantic is input.

HLSL Variables and Resources
============================

This section lists how various HLSL variables and resources are mapped.

According to `Shader Constants <https://msdn.microsoft.com/en-us/library/windows/desktop/bb509581(v=vs.85).aspx>`_,

  There are two default constant buffers available, $Global and $Param. Variables
  that are placed in the global scope are added implicitly to the $Global cbuffer,
  using the same packing method that is used for cbuffers. Uniform parameters in
  the parameter list of a function appear in the $Param constant buffer when a
  shader is compiled outside of the effects framework.

So all global externally-visible non-resource-type stand-alone variables will
be collected into a cbuffer named as ``$Globals``, no matter whether they are
statically referenced by the entry point or not. The ``$Globals`` cbuffer
follows the layout rules like normal cbuffer.

Storage class
-------------

Normal local variables (without any modifier) will be placed in the ``Function``
SPIR-V storage class. Normal global variables (without any modifer) will be
placed in the ``Uniform`` or ``UniformConstant`` storage class.

- ``static``

  - Global variables with ``static`` modifier will be placed in the ``Private``
    SPIR-V storage class. Initalizers of such global variables will be translated
    into SPIR-V ``OpVariable`` initializers if possible; otherwise, they will be
    initialized at the very beginning of the `entry function wrapper`_ using
    SPIR-V ``OpStore``.
  - Local variables with ``static`` modifier will also be placed in the
    ``Private`` SPIR-V storage class. initializers of such local variables will
    also be translated into SPIR-V ``OpVariable`` initializers if possible;
    otherwise, they will be initialized at the very beginning of the enclosing
    function. To make sure that such a local variable is only initialized once,
    a second boolean variable of the ``Private`` SPIR-V storage class will be
    generated to mark its initialization status.

- ``groupshared``

  - Global variables with ``groupshared`` modifier will be placed in the
    ``Workgroup`` storage class.
  - Note that this modifier overrules ``static``; if both ``groupshared`` and
    ``static`` are applied to a variable, ``static`` will be ignored.

- ``uniform``

  - This does not affect codegen. Variables will be treated like normal global
    variables.

- ``extern``

  - This does not affect codegen. Variables will be treated like normal global
    variables.

- ``shared``

  - This is a hint to the compiler. It will be ignored.

- ``volatile``

  - This is a hint to the compiler. It will be ignored.

HLSL semantic and Vulkan ``Location``
-------------------------------------

Direct3D uses HLSL "`semantics <https://msdn.microsoft.com/en-us/library/windows/desktop/bb509647(v=vs.85).aspx>`_"
to compose and match the interfaces between subsequent stages. These semantic
strings can appear after struct members, function parameters and return
values. E.g.,

.. code:: hlsl

  struct VSInput {
    float4 pos  : POSITION;
    float3 norm : NORMAL;
  };

  float4 VSMain(in  VSInput input,
                in  float4  tex   : TEXCOORD,
                out float4  pos   : SV_Position) : TEXCOORD {
    pos = input.pos;
    return tex;
  }

In contrary, Vulkan stage input and output interface matching is via explicit
``Location`` numbers. Details can be found `here <https://www.khronos.org/registry/vulkan/specs/1.1-extensions/html/vkspec.html#interfaces-iointerfaces>`_.

To translate HLSL to SPIR-V for Vulkan, semantic strings need to be mapped to
Vulkan ``Location`` numbers properly. This can be done either explicitly via
information provided by the developer or implicitly by the compiler.

Explicit ``Location`` number assignment
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

``[[vk::location(X)]]`` can be attached to the entities where semantic are
allowed to attach (struct fields, function parameters, and function returns).
For the above exmaple we can have:

.. code:: hlsl

  struct VSInput {
    [[vk::location(0)]] float4 pos  : POSITION;
    [[vk::location(1)]] float3 norm : NORMAL;
  };

  [[vk::location(1)]]
  float4 VSMain(in  VSInput input,
                [[vk::location(2)]]
                in  float4  tex     : TEXCOORD,
                out float4  pos     : SV_Position) : TEXCOORD {
    pos = input.pos;
    return tex;
  }

In the above, input ``POSITION``, ``NORMAL``, and ``TEXCOORD`` will be mapped to
``Location`` 0, 1, and 2, respectively, and output ``TEXCOORD`` will be mapped
to ``Location`` 1.

[TODO] Another explicit way: using command-line options

Please note that the compiler prohibits mixing the explicit and implicit
approach for the same SigPoint to avoid complexity and fallibility. However,
for a certain shader stage, one SigPoint using the explicit approach while the
other adopting the implicit approach is permitted.

Implicit ``Location`` number assignment
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

Without hints from the developer, the compiler will try its best to map
semantics to ``Location`` numbers. However, there is no single rule for this
mapping; semantic strings should be handled case by case.

Firstly, under certain `SigPoints <https://github.com/Microsoft/DirectXShaderCompiler/blob/main/docs/DXIL.rst#hlsl-signatures-and-semantics>`_,
some system-value (SV) semantic strings will be translated into SPIR-V
``BuiltIn`` decorations:

.. table:: Mapping from HLSL SV semantic to SPIR-V builtin and execution mode

+---------------------------+-------------+----------------------------------------+-----------------------+-----------------------------+
| HLSL Semantic             | SigPoint    | SPIR-V ``BuiltIn``                     | SPIR-V Execution Mode |   SPIR-V Capability         |
+===========================+=============+========================================+=======================+=============================+
|                           | VSOut       | ``Position``                           | N/A                   | ``Shader``                  |
|                           +-------------+----------------------------------------+-----------------------+-----------------------------+
|                           | HSCPIn      | ``Position``                           | N/A                   | ``Shader``                  |
|                           +-------------+----------------------------------------+-----------------------+-----------------------------+
|                           | HSCPOut     | ``Position``                           | N/A                   | ``Shader``                  |
|                           +-------------+----------------------------------------+-----------------------+-----------------------------+
|                           | DSCPIn      | ``Position``                           | N/A                   | ``Shader``                  |
|                           +-------------+----------------------------------------+-----------------------+-----------------------------+
| SV_Position               | DSOut       | ``Position``                           | N/A                   | ``Shader``                  |
|                           +-------------+----------------------------------------+-----------------------+-----------------------------+
|                           | GSVIn       | ``Position``                           | N/A                   | ``Shader``                  |
|                           +-------------+----------------------------------------+-----------------------+-----------------------------+
|                           | GSOut       | ``Position``                           | N/A                   | ``Shader``                  |
|                           +-------------+----------------------------------------+-----------------------+-----------------------------+
|                           | PSIn        | ``FragCoord``                          | N/A                   | ``Shader``                  |
|                           +-------------+----------------------------------------+-----------------------+-----------------------------+
|                           | MSOut       | ``Position``                           | N/A                   | ``Shader``                  |
+---------------------------+-------------+----------------------------------------+-----------------------+-----------------------------+
|                           | VSOut       | ``ClipDistance``                       | N/A                   | ``ClipDistance``            |
|                           +-------------+----------------------------------------+-----------------------+-----------------------------+
|                           | HSCPIn      | ``ClipDistance``                       | N/A                   | ``ClipDistance``            |
|                           +-------------+----------------------------------------+-----------------------+-----------------------------+
|                           | HSCPOut     | ``ClipDistance``                       | N/A                   | ``ClipDistance``            |
|                           +-------------+----------------------------------------+-----------------------+-----------------------------+
|                           | DSCPIn      | ``ClipDistance``                       | N/A                   | ``ClipDistance``            |
|                           +-------------+----------------------------------------+-----------------------+-----------------------------+
| SV_ClipDistance           | DSOut       | ``ClipDistance``                       | N/A                   | ``ClipDistance``            |
|                           +-------------+----------------------------------------+-----------------------+-----------------------------+
|                           | GSVIn       | ``ClipDistance``                       | N/A                   | ``ClipDistance``            |
|                           +-------------+----------------------------------------+-----------------------+-----------------------------+
|                           | GSOut       | ``ClipDistance``                       | N/A                   | ``ClipDistance``            |
|                           +-------------+----------------------------------------+-----------------------+-----------------------------+
|                           | PSIn        | ``ClipDistance``                       | N/A                   | ``ClipDistance``            |
|                           +-------------+----------------------------------------+-----------------------+-----------------------------+
|                           | MSOut       | ``ClipDistance``                       | N/A                   | ``ClipDistance``            |
+---------------------------+-------------+----------------------------------------+-----------------------+-----------------------------+
|                           | VSOut       | ``CullDistance``                       | N/A                   | ``CullDistance``            |
|                           +-------------+----------------------------------------+-----------------------+-----------------------------+
|                           | HSCPIn      | ``CullDistance``                       | N/A                   | ``CullDistance``            |
|                           +-------------+----------------------------------------+-----------------------+-----------------------------+
|                           | HSCPOut     | ``CullDistance``                       | N/A                   | ``CullDistance``            |
|                           +-------------+----------------------------------------+-----------------------+-----------------------------+
|                           | DSCPIn      | ``CullDistance``                       | N/A                   | ``CullDistance``            |
|                           +-------------+----------------------------------------+-----------------------+-----------------------------+
| SV_CullDistance           | DSOut       | ``CullDistance``                       | N/A                   | ``CullDistance``            |
|                           +-------------+----------------------------------------+-----------------------+-----------------------------+
|                           | GSVIn       | ``CullDistance``                       | N/A                   | ``CullDistance``            |
|                           +-------------+----------------------------------------+-----------------------+-----------------------------+
|                           | GSOut       | ``CullDistance``                       | N/A                   | ``CullDistance``            |
|                           +-------------+----------------------------------------+-----------------------+-----------------------------+
|                           | PSIn        | ``CullDistance``                       | N/A                   | ``CullDistance``            |
|                           +-------------+----------------------------------------+-----------------------+-----------------------------+
|                           | MSOut       | ``CullDistance``                       | N/A                   | ``CullDistance``            |
+---------------------------+-------------+----------------------------------------+-----------------------+-----------------------------+
| SV_VertexID               | VSIn        | ``VertexIndex``                        | N/A                   | ``Shader``                  |
+---------------------------+-------------+----------------------------------------+-----------------------+-----------------------------+
| SV_InstanceID             | VSIn        | ``InstanceIndex`` or                   | N/A                   | ``Shader``                  |
|                           |             | ``InstanceIndex - BaseInstance``       |                       |                             |
|                           |             | with                                   |                       |                             |
|                           |             | ``-fvk-support-nonzero-base-instance`` |                       |                             |
+---------------------------+-------------+----------------------------------------+-----------------------+-----------------------------+
| SV_StartVertexLocation    | VSIn        | ``BaseVertex``                         | N/A                   | ``Shader``                  |
+---------------------------+-------------+----------------------------------------+-----------------------+-----------------------------+
| SV_StartInstanceLocation  | VSIn        | ``BaseInstance``                       | N/A                   | ``Shader``                  |
+---------------------------+-------------+----------------------------------------+-----------------------+-----------------------------+
| SV_Depth                  | PSOut       | ``FragDepth``                          | N/A                   | ``Shader``                  |
+---------------------------+-------------+----------------------------------------+-----------------------+-----------------------------+
| SV_DepthGreaterEqual      | PSOut       | ``FragDepth``                          | ``DepthGreater``      | ``Shader``                  |
+---------------------------+-------------+----------------------------------------+-----------------------+-----------------------------+
| SV_DepthLessEqual         | PSOut       | ``FragDepth``                          | ``DepthLess``         | ``Shader``                  |
+---------------------------+-------------+----------------------------------------+-----------------------+-----------------------------+
| SV_IsFrontFace            | PSIn        | ``FrontFacing``                        | N/A                   | ``Shader``                  |
+---------------------------+-------------+----------------------------------------+-----------------------+-----------------------------+
|                           | CSIn        | ``GlobalInvocationId``                 | N/A                   | ``Shader``                  |
|                           +-------------+----------------------------------------+-----------------------+-----------------------------+
| SV_DispatchThreadID       | MSIn        | ``GlobalInvocationId``                 | N/A                   | ``Shader``                  |
|                           +-------------+----------------------------------------+-----------------------+-----------------------------+
|                           | ASIn        | ``GlobalInvocationId``                 | N/A                   | ``Shader``                  |
+---------------------------+-------------+----------------------------------------+-----------------------+-----------------------------+
|                           | CSIn        | ``WorkgroupId``                        | N/A                   | ``Shader``                  |
|                           +-------------+----------------------------------------+-----------------------+-----------------------------+
| SV_GroupID                | MSIn        | ``WorkgroupId``                        | N/A                   | ``Shader``                  |
|                           +-------------+----------------------------------------+-----------------------+-----------------------------+
|                           | ASIn        | ``WorkgroupId``                        | N/A                   | ``Shader``                  |
+---------------------------+-------------+----------------------------------------+-----------------------+-----------------------------+
|                           | CSIn        | ``LocalInvocationId``                  | N/A                   | ``Shader``                  |
|                           +-------------+----------------------------------------+-----------------------+-----------------------------+
| SV_GroupThreadID          | MSIn        | ``LocalInvocationId``                  | N/A                   | ``Shader``                  |
|                           +-------------+----------------------------------------+-----------------------+-----------------------------+
|                           | ASIn        | ``LocalInvocationId``                  | N/A                   | ``Shader``                  |
+---------------------------+-------------+----------------------------------------+-----------------------+-----------------------------+
|                           | CSIn        | ``LocalInvocationIndex``               | N/A                   | ``Shader``                  |
|                           +-------------+----------------------------------------+-----------------------+-----------------------------+
| SV_GroupIndex             | MSIn        | ``LocalInvocationIndex``               | N/A                   | ``Shader``                  |
|                           +-------------+----------------------------------------+-----------------------+-----------------------------+
|                           | ASIn        | ``LocalInvocationIndex``               | N/A                   | ``Shader``                  |
+---------------------------+-------------+----------------------------------------+-----------------------+-----------------------------+
| SV_OutputControlPointID   | HSIn        | ``InvocationId``                       | N/A                   | ``Tessellation``            |
+---------------------------+-------------+----------------------------------------+-----------------------+-----------------------------+
| SV_GSInstanceID           | GSIn        | ``InvocationId``                       | N/A                   | ``Geometry``                |
+---------------------------+-------------+----------------------------------------+-----------------------+-----------------------------+
| SV_DomainLocation         | DSIn        | ``TessCoord``                          | N/A                   | ``Tessellation``            |
+---------------------------+-------------+----------------------------------------+-----------------------+-----------------------------+
|                           | HSIn        | ``PrimitiveId``                        | N/A                   | ``Tessellation``            |
|                           +-------------+----------------------------------------+-----------------------+-----------------------------+
|                           | PCIn        | ``PrimitiveId``                        | N/A                   | ``Tessellation``            |
|                           +-------------+----------------------------------------+-----------------------+-----------------------------+
|                           | DsIn        | ``PrimitiveId``                        | N/A                   | ``Tessellation``            |
|                           +-------------+----------------------------------------+-----------------------+-----------------------------+
|                           | GSIn        | ``PrimitiveId``                        | N/A                   | ``Geometry``                |
| SV_PrimitiveID            +-------------+----------------------------------------+-----------------------+-----------------------------+
|                           | GSOut       | ``PrimitiveId``                        | N/A                   | ``Geometry``                |
|                           +-------------+----------------------------------------+-----------------------+-----------------------------+
|                           | PSIn        | ``PrimitiveId``                        | N/A                   | ``Geometry``                |
|                           +-------------+----------------------------------------+-----------------------+-----------------------------+
|                           |             |                                        |                       | ``MeshShadingNV``           |
|                           | MSOut       | ``PrimitiveId``                        | N/A                   |                             |
|                           |             |                                        |                       | ``MeshShadingEXT``          |
+---------------------------+-------------+----------------------------------------+-----------------------+-----------------------------+
|                           | PCOut       | ``TessLevelOuter``                     | N/A                   | ``Tessellation``            |
| SV_TessFactor             +-------------+----------------------------------------+-----------------------+-----------------------------+
|                           | DSIn        | ``TessLevelOuter``                     | N/A                   | ``Tessellation``            |
+---------------------------+-------------+----------------------------------------+-----------------------+-----------------------------+
|                           | PCOut       | ``TessLevelInner``                     | N/A                   | ``Tessellation``            |
| SV_InsideTessFactor       +-------------+----------------------------------------+-----------------------+-----------------------------+
|                           | DSIn        | ``TessLevelInner``                     | N/A                   | ``Tessellation``            |
+---------------------------+-------------+----------------------------------------+-----------------------+-----------------------------+
| SV_SampleIndex            | PSIn        | ``SampleId``                           | N/A                   | ``SampleRateShading``       |
+---------------------------+-------------+----------------------------------------+-----------------------+-----------------------------+
| SV_StencilRef             | PSOut       | ``FragStencilRefEXT``                  | N/A                   | ``StencilExportEXT``        |
+---------------------------+-------------+----------------------------------------+-----------------------+-----------------------------+
| SV_Barycentrics           | PSIn        | ``BaryCoord*KHR``                      | N/A                   | ``FragmentBarycentricKHR``  |
+---------------------------+-------------+----------------------------------------+-----------------------+-----------------------------+
|                           | GSOut       | ``Layer``                              | N/A                   | ``Geometry``                |
|                           +-------------+----------------------------------------+-----------------------+-----------------------------+
|                           | PSIn        | ``Layer``                              | N/A                   | ``Geometry``                |
| SV_RenderTargetArrayIndex +-------------+----------------------------------------+-----------------------+-----------------------------+
|                           |             |                                        |                       | ``MeshShadingNV``           |
|                           | MSOut       | ``Layer``                              | N/A                   |                             |
|                           |             |                                        |                       | ``MeshShadingEXT``          |
+---------------------------+-------------+----------------------------------------+-----------------------+-----------------------------+
|                           | GSOut       | ``ViewportIndex``                      | N/A                   | ``MultiViewport``           |
|                           +-------------+----------------------------------------+-----------------------+-----------------------------+
|                           | PSIn        | ``ViewportIndex``                      | N/A                   | ``MultiViewport``           |
| SV_ViewportArrayIndex     +-------------+----------------------------------------+-----------------------+-----------------------------+
|                           |             |                                        |                       | ``MeshShadingNV``           |
|                           | MSOut       | ``ViewportIndex``                      | N/A                   |                             |
|                           |             |                                        |                       | ``MeshShadingEXT``          |
+---------------------------+-------------+----------------------------------------+-----------------------+-----------------------------+
|                           | PSIn        | ``SampleMask``                         | N/A                   | ``Shader``                  |
| SV_Coverage               +-------------+----------------------------------------+-----------------------+-----------------------------+
|                           | PSOut       | ``SampleMask``                         | N/A                   | ``Shader``                  |
+---------------------------+-------------+----------------------------------------+-----------------------+-----------------------------+
| SV_InnerCoverage          | PSIn        | ``FullyCoveredEXT``                    | N/A                   | ``FragmentFullyCoveredEXT`` |
+---------------------------+-------------+----------------------------------------+-----------------------+-----------------------------+
|                           | VSIn        | ``ViewIndex``                          | N/A                   | ``MultiView``               |
|                           +-------------+----------------------------------------+-----------------------+-----------------------------+
|                           | HSIn        | ``ViewIndex``                          | N/A                   | ``MultiView``               |
|                           +-------------+----------------------------------------+-----------------------+-----------------------------+
|                           | DSIn        | ``ViewIndex``                          | N/A                   | ``MultiView``               |
| SV_ViewID                 +-------------+----------------------------------------+-----------------------+-----------------------------+
|                           | GSIn        | ``ViewIndex``                          | N/A                   | ``MultiView``               |
|                           +-------------+----------------------------------------+-----------------------+-----------------------------+
|                           | PSIn        | ``ViewIndex``                          | N/A                   | ``MultiView``               |
|                           +-------------+----------------------------------------+-----------------------+-----------------------------+
|                           | MSIn        | ``ViewIndex``                          | N/A                   | ``MultiView``               |
+---------------------------+-------------+----------------------------------------+-----------------------+-----------------------------+
|                           | VSOut       | ``PrimitiveShadingRateKHR``            | N/A                   | ``FragmentShadingRate``     |
|                           +-------------+----------------------------------------+-----------------------+-----------------------------+
|                           | GSOut       | ``PrimitiveShadingRateKHR``            | N/A                   | ``FragmentShadingRate``     |
| SV_ShadingRate            +-------------+----------------------------------------+-----------------------+-----------------------------+
|                           | PSIn        | ``ShadingRateKHR``                     | N/A                   | ``FragmentShadingRate``     |
|                           +-------------+----------------------------------------+-----------------------+-----------------------------+
|                           | MSOut       | ``PrimitiveShadingRateKHR``            | N/A                   | ``FragmentShadingRate``     |
+---------------------------+-------------+----------------------------------------+-----------------------+-----------------------------+
| SV_CullPrimitive          | MSOut       | ``CullPrimitiveEXT``                   | N/A                   | ``MeshShadingEXT``          |
+---------------------------+-------------+----------------------------------------+-----------------------+-----------------------------+


For entities (function parameters, function return values, struct fields) with
the above SV semantic strings attached, SPIR-V variables of the
``Input``/``Output`` storage class will be created. They will have the
corresponding SPIR-V ``Builtin``  decorations according to the above table.

SV semantic strings not translated into SPIR-V ``BuiltIn`` decorations will be
handled similarly as non-SV (arbitrary) semantic strings: a SPIR-V variable
of the ``Input``/``Output`` storage class will be created for each entity with
such semantic string. Then sort all semantic strings according to declaration
(the default, or if ``-fvk-stage-io-order=decl`` is given) or alphabetical
(if ``-fvk-stage-io-order=alpha`` is given) order, and assign ``Location``
numbers sequentially to the corresponding SPIR-V variables. Note that this means
flattening all structs if structs are used as function parameters or returns.

There is an exception to the above rule for SV_Target[N]. It will always be
mapped to ``Location`` number N.

``ClipDistance & CullDistance``
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

Variables decorated with ``SV_ClipDistanceX`` can be float or vector of float
type. To map them into one float array in the struct, we firstly sort them
asecendingly according to ``X``, and then concatenate them tightly. For example,

.. code:: hlsl

  struct T {
    float clip0: SV_ClipDistance0,
  };

  struct S {
    float3 clip5: SV_ClipDistance5;
    ...
  };

  void main(T t, S s, float2 clip2 : SV_ClipDistance2) { ... }

Then we have an float array of size (1 + 2 + 3 =) 6 for ``ClipDistance``, with
``clip0`` at offset 0, ``clip2`` at offset 1, ``clip5`` at offset 3.

Decorating a variable or struct member with the ``ClipDistance`` builtin but not
requiring the ``ClipDistance`` capability is legal as long as we don't read or
write the variable or struct member. But as per the way we handle `shader entry
function`_, this is not satisfied because we need to read their contents to
prepare for the source code entry function call or write back them after the
call. So annotating a variable or struct member with ``SV_ClipDistanceX`` means
requiring the ``ClipDistance`` capability in the generated SPIR-V.

Variables decorated with ``SV_CullDistanceX`` are mapped similarly as above.

Signature packing
~~~~~~~~~~~~~~~~~

In usual, Vulkan drivers have a limitation of the number of available locations.
It varies depending on the device. To avoid the driver crash caused by the
limitation, we added an experimental signature packing support using Component
decoration (see the Vulkan spec "15.1.5. Component Assignment").
``-pack-optimized`` is the command line option to enable it.

In a high level, for a stage variable that needs ``M`` components in ``N``
locations e.g., stage variable ``float3 foo[2]`` needs 3 components in 2
locations, we find a minimum ``K`` where each of ``N`` continuous locations in
``[K, K + N)`` has ``M`` continuous unused Component slots. We create a Location
decoration instruction for the stage variable with ``K`` and a Component
decoration instruction with the first unused component number of the
``M`` continuous unused Component slots.

HLSL register and Vulkan binding
--------------------------------

In shaders for DirectX, resources are accessed via registers; while in shaders
for Vulkan, it is done via descriptor set and binding numbers. The developer
can explicitly annotate variables in HLSL to specify descriptor set and binding
numbers, or leave it to the compiler to derive implicitly from registers.

Explicit binding number assignment
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

``[[vk::binding(X[, Y])]]`` can be attached to global variables to specify the
descriptor set as ``Y`` and binding number as ``X``. The descriptor set number
is optional; if missing, it will be zero (If ``-auto-binding-space N`` command
line option is used, then descriptor set #N will be used instead of descriptor
set #0). RW/append/consume structured buffers have associated counters, which
will occupy their own Vulkan descriptors. ``[vk::counter_binding(Z)]`` can be
attached to a RW/append/consume structured buffers to specify the binding number
for the associated counter to ``Z``. Note that the set number of the counter is
always the same as the main buffer.

.. warning::
   When a RW/append/consume structured buffer is accessed through a resource
   heap, its associated counter is in its own binding, but shares the same
   index in the binding as its associated resource.

   Example:
    - ResourceDescriptorHeap -> binding 0, set 0
    - No other resources are used.

    - RWStructuredBuffer buff = ResourceDescriptorHeap[3]
    - buff.IncrementCounter()

    - buff will be at index 3 of the array at binding 0, set 0.
      buff.counter will be at index 3 of the array at binding 1, set 0


Implicit binding number assignment
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

Without explicit annotations, the compiler will try to deduce descriptor sets
and binding numbers in the following way:

If there is ``:register(xX, spaceY)`` specified for the given global variable,
the corresponding resource will be assigned to descriptor set ``Y`` and binding
number ``X``, regardless of the register type ``x``. Note that this will cause
binding number collision if, say, two resources are of different register
type but the same register number. To solve this problem, four command-line
options, ``-fvk-b-shift N M``, ``-fvk-s-shift N M``, ``-fvk-t-shift N M``, and
``-fvk-u-shift N M``, are provided to shift by ``N`` all binding numbers
inferred for register type ``b``, ``s``, ``t``, and ``u`` in space ``M``,
respectively.

If there is no register specification, the corresponding resource will be
assigned to the next available binding number, starting from 0, in descriptor
set #0 (If ``-auto-binding-space N`` command line option is used, then
descriptor set #N will be used instead of descriptor set #0).

If there is no register specification AND ``-fvk-auto-shift-bindings`` is specified,
then the register type will be automatically identified based on the resource
type (according to the following table), and the appropriate shift will
automatically be applied according to ``-fvk-*shift N M``.

.. code:: spirv

  t - for shader resource views (SRV)
      TEXTURE1D
      TEXTURE1DARRAY
      TEXTURE2D
      TEXTURE2DARRAY
      TEXTURE3D
      TEXTURECUBE
      TEXTURECUBEARRAY
      TEXTURE2DMS
      TEXTURE2DMSARRAY
      STRUCTUREDBUFFER
      BYTEADDRESSBUFFER
      BUFFER
      TBUFFER

  s - for samplers
      SAMPLER
      SAMPLER1D
      SAMPLER2D
      SAMPLER3D
      SAMPLERCUBE
      SAMPLERSTATE
      SAMPLERCOMPARISONSTATE

  u - for unordered access views (UAV)
      RWBYTEADDRESSBUFFER
      RWSTRUCTUREDBUFFER
      APPENDSTRUCTUREDBUFFER
      CONSUMESTRUCTUREDBUFFER
      RWBUFFER
      RWTEXTURE1D
      RWTEXTURE1DARRAY
      RWTEXTURE2D
      RWTEXTURE2DARRAY
      RWTEXTURE3D

  b - for constant buffer views (CBV)
      CBUFFER
      CONSTANTBUFFER

Binding number assignment for resources in cbuffer
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

Basically, we use the same binding assignment rule described above for a
cbuffer, but when a cbuffer contains one or more resources, it is inevitable
to use multiple binding numbers for a single cbuffer. For this type of
cbuffers, we first assign the next available binding number to the resources.
Based the order of the appearance in the cbuffer, a resource that appears early
uses a smaller (earlier available) binding number than a resource that appears
later. After assigning binding numbers to all resource members, if the cbuffer
contains one or more members with non-resource types, it creates a struct for
the remaining members and assign the next available binding number to the
variable with the struct type.

For example, the binding numbers for the following resources and cbuffers

.. code:: hlsl

  cbuffer buf0 : register(b0) {
    float4 non_resource0;
  };
  cbuffer buf1 : register(b4) {
    float4 non_resource1;
  };
  cbuffer buf2 {
    float4 non_resource2;
    Texture2D resource0;
    SamplerState resource1;
  };
  cbuffer buf3 : register(b2) {
    SamplerState resource2;
  }

will be

- ``buf0``: 0 because of ``register(b0)``

- ``buf1``: 4 because of ``register(b4)``

- ``resource2``: 2 because of ``register(b2)``. Note that ``buf3`` is empty
  without ``resource2``. We do not assign a binding number to an empty struct.

- ``resource0``: 1 because it is the next available binding number.

- ``resource1``: 3 because it is the next available binding number.

- ``buf2`` including only ``non_resource2``: 5 because it is the next available
  binding number.

Summary
~~~~~~~

In summary, the compiler essentially assigns binding numbers in three passes.

- Firstly it handles all declarations with explicit ``[[vk::binding(X[, Y])]]``
  annotation.

- Then the compiler processes all remaining declarations with
  ``:register(xX, spaceY)`` annotation, by applying the shift passed in using
  command-line option ``-fvk-{b|s|t|u}-shift N M``, if provided.

  - If ``:register`` assignment is missing and ``-fvk-auto-shift-bindings`` is
    specified, the register type will be automatically detected based on the
    resource type, and the ``-fvk-{b|s|t|u}-shift N M`` will be applied.

- Finally, the compiler assigns next available binding numbers to the rest in
  the declaration order.

As an example, for the following code:

.. code:: hlsl

  struct S { ... };

  ConstantBuffer<S> cbuffer1 : register(b0);
  Texture2D<float4> texture1 : register(t0);
  Texture2D<float4> texture2 : register(t1, space1);
  SamplerState      sampler1;
  [[vk::binding(3)]]
  RWBuffer<float4> rwbuffer1 : register(u5, space2);

If we compile with ``-fvk-t-shift 10 0 -fvk-t-shift 20 1``:

- ``rwbuffer1`` will take binding #3 in set #0, since explicit binding
  assignment has precedence over the rest.
- ``cbuffer1`` will take binding #0 in set #0, since that's what deduced from
  the register assignment, and there is no shift requested from command line.
- ``texture1`` will take binding #10 in set #0, and ``texture2`` will take
  binding #21 in set #1, since we requested an 10 shift on t-type registers.
- ``sampler1`` will take binding 1 in set #0, since that's the next available
  binding number in set #0.

HLSL global variables and Vulkan binding
----------------------------------------
As mentioned above, all global externally-visible non-resource-type stand-alone
variables will be collected into a cbuffer named ``$Globals``. By default,
the ``$Globals`` cbuffer is placed in descriptor set #0, and the binding number
would be the next available binding number in that set. Meaning, the binding number
depends on where the very first global variable is in the code.

Example 1:

.. code:: hlsl

  float4 someColors;
    // $Globals cbuffer placed at DescriptorSet #0, Binding #0
  Texture2D<float4> texture1;
    // texture1         placed at DescriptorSet #0, Binding #1

Example 2:

.. code:: hlsl

  Texture2D<float4> texture1;
    // texture1         placed at DescriptorSet #0, Binding #0
  float4 someColors;
    // $Globals cbuffer placed at DescriptorSet #0, Binding #1

In order provide more control over the descriptor set and binding number of the
``$Globals`` cbuffer, you can use the ``-fvk-bind-globals B S`` command line
option, which will place this cbuffer at descriptor set ``S``, and binding number ``B``.

Example 3: (compiled with ``-fvk-bind-globals 2 1``)

.. code:: hlsl

  Texture2D<float4> texture1;
    // texture1         placed at DescriptorSet #0, Binding #0
  float4 someColors;
    // $Globals cbuffer placed at DescriptorSet #1, Binding #2

Note that if the developer chooses to use this command line option, it is their
responsibility to provide proper numbers and avoid binding overlaps.

ResourceDescriptorHeaps & SamplerDescriptorHeaps
------------------------------------------------

By default, the SPIR-V backend supports SM6.6 resource heaps by emulating the
heaps with descriptor-indexing runtime arrays, using 2 extensions:

- `SPV_EXT_descriptor_indexing`
- `VK_EXT_mutable_descriptor_type`

This is also the behavior selected by ``-fspv-use-emulated-heap``.

Each type loaded from a heap is considered to be an unbounded RuntimeArray
bound to the descriptor set 0.

Each heap uses at most 1 binding in that set. Meaning if 2 types are loaded
from the same heap, DXC will generate 2 RuntimeArray, one for each type, and
will bind them to the same binding/set.
(This requires `VK_EXT_mutable_descriptor_type`).

For resources with counters, like RW/Append/Consume structured buffers,
DXC generates another RuntimeArray of counters, and binds it to a new
binding in the set 0.

This means Resource/Sampler heaps can use at most 3 bindings:
    - 1 for all RuntimeArrays associated with the ResourceDescriptorHeap.
    - 1 for all RuntimeArrays associated with the SamplerDescriptorHeaps.
    - 1 for UAV counters.

The index of a counter in the counters RuntimeArray matches the index of the
associated ResourceDescriptorHeap RuntimeArray.

The selection of the binding indices for those RuntimeArrays is done once all
other resources are bound to their respective bindings/sets.
DXC takes the first 3 unused bindings in the set 0, and distributes them in
that order:
    1. Resource heap.
    2. Sampler heap.
    3. Resouce heap counters.

Bindings are lazily allocated: if only the sampler heap is used,
1 binding will be used.

.. code:: hlsl
   Texture2D tex = ResourceDescriptorHeap[10];
   // tex is in the descriptor set 0, binding 0.

.. code:: hlsl
   [[vk::binding(0, 0)]]
   Texture2D Texture;
   // Texture is using set=0, binding=0

   Texture2D tex = ResourceDescriptorHeap[0];
   // tex is in the descriptor set 0, binding 1.

.. code:: hlsl
   [[vk::binding(0, 0)]]
   RWStructuredBuffer<int> buffer;
   // Texture is using set=0, binding=0

   RWStructuredBuffer<int> tmp = ResourceDescriptorHeap[0];
   tmp.IncrementCounter();
   // tmp is in the descriptor set 0, binding 1.
   // tmp.counter is in the descriptor set 0, binding 2

.. code:: hlsl
   [[vk::binding(1, 0)]]
   RWStructuredBuffer<int> buffer;
   // Texture is using set=0, binding=1

   RWStructuredBuffer<int> tmp = ResourceDescriptorHeap[0];
   tmp.IncrementCounter();
   // tmp is in the descriptor set 0, binding 0.
   // tmp.counter is in the descriptor set 0, binding 2

.. code:: hlsl
   RWStructuredBuffer buffer = ResourceDescriptorHeap[2];
   // buffer is in the descriptor set 0, binding 0.
   // Counter not generated, because unused.

Bindings & sets associated with each heap can be explicitly set using:

- `-fvk-bind-sampler-heap <binding> <set>`: Specify Vulkan binding number
  and set number for the sampler heap.
- `-fvk-bind-resource-heap <binding> <set>`: Specify Vulkan binding number
  and set number for the resource heap.
- `-fvk-bind-counter-heap <binding> <set>`: Specify Vulkan binding number
  and set number for the counter heap.

Native descriptor heap extension lowering
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

When ``-fspv-use-descriptor-heap`` is specified, DXC lowers
``ResourceDescriptorHeap`` and ``SamplerDescriptorHeap`` through
``SPV_EXT_descriptor_heap`` instead of the default emulated heap path. This
also requires ``SPV_KHR_untyped_pointers`` and ``-fspv-target-env=vulkan1.3``
(targeting a lower environment is an error), and a SPIRV-Headers / SPIRV-Tools
build that defines these extensions. The emitted module declares the heap
objects as untyped variables in ``UniformConstant`` storage class:

.. code:: spirv

  %uptr_uc = OpTypeUntypedPointerKHR UniformConstant
  %resource_heap = OpUntypedVariableKHR %uptr_uc UniformConstant
  %sampler_heap  = OpUntypedVariableKHR %uptr_uc UniformConstant
  OpDecorate %resource_heap BuiltIn ResourceHeapEXT
  OpDecorate %sampler_heap BuiltIn SamplerHeapEXT

The concrete descriptor type is selected at each heap access. For image,
sampler, and texel buffer resources, DXC forms a runtime array of that
descriptor type, decorates the array with a byte stride, and uses
``OpUntypedAccessChainKHR`` followed by ``OpLoad``. By default the stride is an
``ArrayStrideIdEXT`` decoration referencing a constant built from
``OpConstantSizeOfEXT``; a literal ``ArrayStride`` is emitted only when the
stride is overridden on the command line (see `Descriptor heap array stride`_
below):

.. code:: spirv

  %image_type = OpTypeImage %float 2D 2 0 0 1 Unknown
  %image_array = OpTypeRuntimeArray %image_type
  OpDecorateId %image_array ArrayStrideIdEXT %resource_stride
  %descriptor = OpUntypedAccessChainKHR %uptr_uc %image_array %resource_heap %index
  %image = OpLoad %image_type %descriptor

For buffer-like resources, DXC uses ``OpTypeBufferEXT`` as the descriptor type
and ``OpBufferPointerEXT`` to recover the pointer to the buffer data. The
descriptor storage class matches the recovered buffer pointer storage class; for
example, ``ConstantBuffer<T>`` uses ``Uniform`` and ``TextureBuffer<T>`` uses
``StorageBuffer``:

.. code:: spirv

  %buffer_type = OpTypeBufferEXT Uniform
  %buffer_array = OpTypeRuntimeArray %buffer_type
  OpDecorateId %buffer_array ArrayStrideIdEXT %resource_stride
  %descriptor = OpUntypedAccessChainKHR %uptr_uc %buffer_array %resource_heap %index
  %buffer_ptr = OpBufferPointerEXT %_ptr_Uniform_type_BufferData %descriptor

For ``RWTexture`` resources loaded from ``ResourceDescriptorHeap``, interlocked
operations that need a texel pointer use ``OpUntypedImageTexelPointerEXT``.
The image descriptor pointer produced by ``OpUntypedAccessChainKHR`` is passed
directly to the texel-pointer instruction instead of first storing the image
handle into a function-scope image variable:

.. code:: spirv

  %image_type = OpTypeImage %uint 2D 2 0 0 2 R32ui
  %image_array = OpTypeRuntimeArray %image_type
  %descriptor = OpUntypedAccessChainKHR %uptr_uc %image_array %resource_heap %index
  %uptr_image = OpTypeUntypedPointerKHR Image
  %texel_ptr = OpUntypedImageTexelPointerEXT %uptr_image %image_type %descriptor %coord %sample
  %old = OpAtomicIAdd %uint %texel_ptr %scope %semantics %value

``RaytracingAccelerationStructure`` resources loaded from
``ResourceDescriptorHeap`` follow the same access-chain-then-load shape over a
runtime array of ``OpTypeAccelerationStructureKHR``:

.. code:: spirv

  %accel_type = OpTypeAccelerationStructureKHR
  %accel_array = OpTypeRuntimeArray %accel_type
  OpDecorateId %accel_array ArrayStrideIdEXT %resource_stride
  %descriptor = OpUntypedAccessChainKHR %uptr_uc %accel_array %resource_heap %index
  %accel = OpLoad %accel_type %descriptor

This path supports texture, RWTexture, sampler, Buffer/RWBuffer,
StructuredBuffer/RWStructuredBuffer without associated counter operations,
ByteAddressBuffer/RWByteAddressBuffer, ConstantBuffer, TextureBuffer, and
``RaytracingAccelerationStructure`` heap loads, including direct field and
array-element accesses for ``ConstantBuffer<T>`` and ``TextureBuffer<T>``.
Acceleration structure loads are additionally subject to the stride requirement
described in `Descriptor heap array stride`_ below.
``NonUniformResourceIndex`` is accepted, but no ``NonUniform`` decoration is
emitted on the ``OpUntypedAccessChainKHR`` result or on the loaded descriptor;
``SPV_EXT_descriptor_heap`` deprecates the decoration for heap accesses and
drivers handle divergent heap indices natively. The index operand itself may
still carry ``NonUniform`` from the surrounding expression.

Append/consume structured buffers and UAV counter heap lowering are not
supported by the native descriptor heap path yet. Those forms should continue
to use the default emulated heap lowering, or DXC will emit a diagnostic for
unsupported append/consume structured-buffer heap loads. Heap-loaded
``RWStructuredBuffer`` resources are supported for ordinary data access, but
associated counter operations such as ``IncrementCounter`` and
``DecrementCounter`` emit a diagnostic because the native descriptor heap path
does not recover an associated counter descriptor.

Buffer-like local variables initialized from a heap access are tracked by their
heap index, and later uses are re-lowered as fresh access chains. Image
variables retain their loaded descriptor handle for ordinary reads and writes;
the tracked heap index is used when an atomic operation requires
``OpUntypedImageTexelPointerEXT``. A ``RaytracingAccelerationStructure``
variable initialized from a heap access is a name for the handle loaded by its
initializer.

These aliases are compile-time state and do not model control-flow merges, so
DXC rejects a variable that holds both a bound resource and a heap descriptor,
whether through a conditional assignment, a reassignment back to a bound
resource, or an assignment inside a loop:

.. code:: text

  error: mixing bound and descriptor heap resources in the same variable is not
  supported with SPV_EXT_descriptor_heap

A heap-initialized ``RaytracingAccelerationStructure`` variable cannot be
reassigned at all, whether from a bound resource or from another heap access:

.. code:: text

  error: reassigning a RaytracingAccelerationStructure initialized from
  ResourceDescriptorHeap is not supported with SPV_EXT_descriptor_heap

Supporting these forms requires modelling the alias as a value with real
control-flow merges instead of as compile-time state.

``StructuredBuffer``, ``ByteAddressBuffer``, and related buffer-type aliases
cannot yet be passed to or returned from user functions; access the resource
directly at each call or return site.

Three further restrictions on heap accesses produce diagnostics:

- The object being subscripted must be a direct reference to the builtin
  ``ResourceDescriptorHeap`` or ``SamplerDescriptorHeap`` variable.
- The subscript result must be immediately converted to a concrete resource
  type so that DXC can select a descriptor type for the access. A subscript
  whose result is discarded, or used in a context that supplies no target
  resource type, is rejected.
- A local ``RaytracingAccelerationStructure`` must be initialized from a
  loadable heap access, since the alias has no backing descriptor otherwise.

Descriptor heap array stride
++++++++++++++++++++++++++++

By default, all resource heap runtime arrays share a single ``ArrayStrideIdEXT``
decoration rather than a literal ``ArrayStride``, because descriptor sizes are
not known until pipeline creation. The shared value is built from
``OpConstantSizeOfEXT`` and ``OpSpecConstantOp`` and evaluates to
``max(sizeof(image_descriptor), sizeof(buffer_descriptor))``. The sampler heap
carries its own ``ArrayStrideIdEXT`` equal to ``sizeof(sampler_descriptor)``.

The ``OpConstantSizeOfEXT`` operands are placeholder types chosen only for their
descriptor class. All image types report the same descriptor size, so the
placeholder is a plain sampled 2D float image and bears no relation to the image
types the shader actually uses; a module will normally contain both the
placeholder type and the distinct image types its heap accesses lower to.

The stride is a property of the heap layout, not of the shader's loads. DXC
decides it before translating any function, either from explicit user input
(``-fvk-resource-heap-stride`` and ``-fvk-sampler-heap-stride``, see below) or
by calculating it from the shader stage and the ``-fspv-extension`` list. When
acceleration structure descriptors may be on the resource heap, the formula expands to a three-way max
``max(max(sizeof(image_descriptor), sizeof(buffer_descriptor)), sizeof(acceleration_structure))``.
A ray-tracing shader that only heap-loads a texture still gets the three-way
max. DXC adds the acceleration structure term when either

- any entry point is a ray-tracing stage, or
- the user lists ``-fspv-extension=SPV_KHR_ray_query``,
  ``-fspv-extension=SPV_KHR_ray_tracing`` or
  ``-fspv-extension=SPV_NV_ray_tracing``.

Extensions allowed by default do not satisfy the second condition. The
acceleration structure type added by widening is declared with the capability
of the listed extension (``RayQueryKHR``, ``RayTracingKHR`` or
``RayTracingNV``); if several are listed, ``SPV_KHR_ray_query`` is preferred,
then ``SPV_KHR_ray_tracing``, then ``SPV_NV_ray_tracing``. A shader that is not
a ray-tracing stage and heap-loads a ``RaytracingAccelerationStructure``
without such an extension or ``-fvk-resource-heap-stride`` is rejected, because
its stride would not cover the acceleration structure descriptor.

The computed stride can be replaced with a literal using
``-fvk-resource-heap-stride <N>`` and ``-fvk-sampler-heap-stride <N>``. They
emit ``OpDecorate <array> ArrayStride N`` on every runtime array of the resource
heap and of the sampler heap respectively. ``N`` must be a power of two in the
inclusive range [8, 256]. Both flags require ``-spirv`` and
``-fspv-use-descriptor-heap``, and are rejected otherwise because they would
have no effect.

For a heap with an override, no ``ArrayStrideIdEXT`` is emitted and no
``OpConstantSizeOfEXT`` is built. The flags are independent: the other heap
keeps its computed stride.

The literal is not validated against the descriptor sizes of the target
implementation. It must match the stride at which the application lays out
descriptors in the heap, and be at least the size of the largest descriptor
that may appear in it; otherwise heap indices select the wrong descriptors or
read out of bounds.
``-fvk-resource-heap-stride`` also disables the acceleration structure check
above, so the stride must cover acceleration structure descriptors when the
shader loads them from the heap.

HLSL Expressions
================

Unless explicitly noted, matrix per-element operations will be conducted on
each component vector and then collected into the result matrix. The following
sections lists the SPIR-V opcodes for scalars and vectors.

Arithmetic operators
--------------------

`Arithmetic operators <https://msdn.microsoft.com/en-us/library/windows/desktop/bb509631(v=vs.85).aspx#Additive_and_Multiplicative_Operators>`_
(``+``, ``-``, ``*``, ``/``, ``%``) are translated into their corresponding
SPIR-V opcodes according to the following table.

+-------+-----------------------------+-------------------------------+--------------------+
|       | (Vector of) Signed Integers | (Vector of) Unsigned Integers | (Vector of) Floats |
+=======+=============================+===============================+====================+
| ``+`` |                         ``OpIAdd``                          |     ``OpFAdd``     |
+-------+-------------------------------------------------------------+--------------------+
| ``-`` |                         ``OpISub``                          |     ``OpFSub``     |
+-------+-------------------------------------------------------------+--------------------+
| ``*`` |                         ``OpIMul``                          |     ``OpFMul``     |
+-------+-----------------------------+-------------------------------+--------------------+
| ``/`` |    ``OpSDiv``               |       ``OpUDiv``              |     ``OpFDiv``     |
+-------+-----------------------------+-------------------------------+--------------------+
| ``%`` |    ``OpSRem``               |       ``OpUMod``              |     ``OpFRem``     |
+-------+-----------------------------+-------------------------------+--------------------+

Note that for modulo operation, SPIR-V has two sets of instructions: ``Op*Rem``
and ``Op*Mod``. For ``Op*Rem``, the sign of a non-0 result comes from the first
operand; while for ``Op*Mod``, the sign of a non-0 result comes from the second
operand. HLSL doc does not mandate which set of instructions modulo operations
should be translated into; it only says "the % operator is defined only in cases
where either both sides are positive or both sides are negative." So technically
it's undefined behavior to use the modulo operation with operands of different
signs. But considering HLSL's C heritage and the behavior of Clang frontend, we
translate modulo operators into ``Op*Rem`` (there is no ``OpURem``).

For multiplications of float vectors and float scalars, the dedicated SPIR-V
operation ``OpVectorTimesScalar`` will be used. Similarly, for multiplications
of float matrices and float scalars, ``OpMatrixTimesScalar`` will be generated.

Bitwise operators
-----------------

`Bitwise operators <https://msdn.microsoft.com/en-us/library/windows/desktop/bb509631(v=vs.85).aspx#Bitwise_Operators>`_
(``~``, ``&``, ``|``, ``^``, ``<<``, ``>>``) are translated into their
corresponding SPIR-V opcodes according to the following table.

+--------+-----------------------------+-------------------------------+
|        | (Vector of) Signed Integers | (Vector of) Unsigned Integers |
+========+=============================+===============================+
| ``~``  |                         ``OpNot``                           |
+--------+-------------------------------------------------------------+
| ``&``  |                      ``OpBitwiseAnd``                       |
+--------+-------------------------------------------------------------+
| ``|``  |                      ``OpBitwiseOr``                        |
+--------+-----------------------------+-------------------------------+
| ``^``  |                      ``OpBitwiseXor``                       |
+--------+-----------------------------+-------------------------------+
| ``<<`` |                   ``OpShiftLeftLogical``                    |
+--------+-----------------------------+-------------------------------+
| ``>>`` | ``OpShiftRightArithmetic``  | ``OpShiftRightLogical``       |
+--------+-----------------------------+-------------------------------+

Note that for ``<<``/``>>``, the right hand side will be culled: only the ``n``
- 1 least significant bits are considered, where ``n`` is the bitwidth of the
left hand side.

Comparison operators
--------------------

`Comparison operators <https://msdn.microsoft.com/en-us/library/windows/desktop/bb509631(v=vs.85).aspx#Comparison_Operators>`_
(``<``, ``<=``, ``>``, ``>=``, ``==``, ``!=``) are translated into their
corresponding SPIR-V opcodes according to the following table.

+--------+-----------------------------+-------------------------------+------------------------------+
|        | (Vector of) Signed Integers | (Vector of) Unsigned Integers |     (Vector of) Floats       |
+========+=============================+===============================+==============================+
| ``<``  |  ``OpSLessThan``            |  ``OpULessThan``              |  ``OpFOrdLessThan``          |
+--------+-----------------------------+-------------------------------+------------------------------+
| ``<=`` |  ``OpSLessThanEqual``       |  ``OpULessThanEqual``         |  ``OpFOrdLessThanEqual``     |
+--------+-----------------------------+-------------------------------+------------------------------+
| ``>``  |  ``OpSGreaterThan``         |  ``OpUGreaterThan``           |  ``OpFOrdGreaterThan``       |
+--------+-----------------------------+-------------------------------+------------------------------+
| ``>=`` |  ``OpSGreaterThanEqual``    |  ``OpUGreaterThanEqual``      |  ``OpFOrdGreaterThanEqual``  |
+--------+-----------------------------+-------------------------------+------------------------------+
| ``==`` |                     ``OpIEqual``                            |  ``OpFOrdEqual``             |
+--------+-------------------------------------------------------------+------------------------------+
| ``!=`` |                     ``OpINotEqual``                         |  ``OpFOrdNotEqual``          |
+--------+-------------------------------------------------------------+------------------------------+

Note that for comparison of (vectors of) floats, SPIR-V has two sets of
instructions: ``OpFOrd*``, ``OpFUnord*``. We translate into ``OpFOrd*`` ones.

Boolean math operators
----------------------

`Boolean match operators <https://msdn.microsoft.com/en-us/library/windows/desktop/bb509631(v=vs.85).aspx#Boolean_Math_Operators>`_
(``&&``, ``||``, ``?:``) are translated into their corresponding SPIR-V opcodes
according to the following table.

+--------+----------------------+
|        | (Vector of) Booleans |
+========+======================+
| ``&&`` |  ``OpLogicalAnd``    |
+--------+----------------------+
| ``||`` |  ``OpLogicalOr``     |
+--------+----------------------+
| ``?:`` |  ``OpSelect``        |
+--------+----------------------+

Please note that "unlike short-circuit evaluation of ``&&``, ``||``, and ``?:``
in C, HLSL expressions never short-circuit an evaluation because they are vector
operations. All sides of the expression are always evaluated."

Unary operators
---------------

For `unary operators <https://msdn.microsoft.com/en-us/library/windows/desktop/bb509631(v=vs.85).aspx#Unary_Operators>`_:

- ``!`` is translated into ``OpLogicalNot``. Parsing will gurantee the operands
  are of boolean types by inserting necessary casts.
- ``+`` requires no additional SPIR-V instructions.
- ``-`` is translated into ``OpSNegate`` and ``OpFNegate`` for (vectors of)
  integers and floats, respectively.

Casts
-----

Casting between (vectors) of scalar types is translated according to the following table:

+------------+-------------------+-------------------+-------------------+-------------------+
| From \\ To |        Bool       |       SInt        |      UInt         |       Float       |
+============+===================+===================+===================+===================+
|   Bool     |       no-op       |                 select between one and zero               |
+------------+-------------------+-------------------+-------------------+-------------------+
|   SInt     |                   |     no-op         |  ``OpBitcast``    | ``OpConvertSToF`` |
+------------+                   +-------------------+-------------------+-------------------+
|   UInt     | compare with zero |   ``OpBitcast``   |      no-op        | ``OpConvertUToF`` |
+------------+                   +-------------------+-------------------+-------------------+
|   Float    |                   | ``OpConvertFToS`` | ``OpConvertFToU`` |      no-op        |
+------------+-------------------+-------------------+-------------------+-------------------+

It is also feasible in HLSL to cast a float matrix to another float matrix with a smaller size.
This is known as matrix truncation cast. For instance, the following code casts a 3x4 matrix
into a 2x3 matrix.

.. code:: hlsl

  float3x4 m = { 1,  2,  3, 4,
                 5,  6,  7, 8,
                 9, 10, 11, 12 };

  float2x3 a = (float2x3)m;

Such casting takes the upper-left most corner of the original matrix to generate the result.
In the above example, matrix ``a`` will have 2 rows, with 3 columns each. First row will be
``1, 2, 3`` and the second row will be ``5, 6, 7``.

Indexing operator
-----------------

The ``[]`` operator can also be used to access elements in a matrix or vector.
A matrix whose row and/or column count is 1 will be translated into a vector or
scalar. If a variable is used as the index for the dimension whose count is 1,
that variable will be ignored in the generated SPIR-V code. This is because
out-of-bound indexing triggers undefined behavior anyway. For example, for a
1xN matrix ``mat``, ``mat[index][0]`` will be translated into
``OpAccessChain ... %mat %uint_0``. Similarly, variable index into a size 1
vector will also be ignored and the only element will be always returned.

Assignment operators
--------------------

Assigning to struct object may involve decomposing the source struct object and
assign each element separately and recursively. This happens when the source
struct object is of different memory layout from the destination struct object.
For example, for the following source code:

.. code:: hlsl

  struct S {
    float    a;
    float2   b;
    float2x3 c;
  };

      ConstantBuffer<S> cbuf;
  RWStructuredBuffer<S> sbuf;

  ...
  sbuf[0] = cbuf[0];
  ...

We need to assign each element because ``ConstantBuffer`` and
``RWStructuredBuffer`` has different memory layout.

HLSL Control Flows
==================

This section lists how various HLSL control flows are mapped.

Switch statement
----------------

HLSL `switch statements <https://msdn.microsoft.com/en-us/library/windows/desktop/bb509669(v=vs.85).aspx>`_
are translated into SPIR-V using:

- **OpSwitch**: if (all case values are integer literals or constant integer
  variables) and (no attribute or the ``forcecase`` attribute is specified)
- **A series of if statements**: for all other scenarios (e.g., when
  ``flatten``, ``branch``, or ``call`` attribute is specified)

Loops (for, while, do)
----------------------

HLSL `for statements <https://msdn.microsoft.com/en-us/library/windows/desktop/bb509602(v=vs.85).aspx>`_,
`while statements <https://msdn.microsoft.com/en-us/library/windows/desktop/bb509708(v=vs.85).aspx>`_,
and `do statements <https://msdn.microsoft.com/en-us/library/windows/desktop/bb509593(v=vs.85).aspx>`_
are translated into SPIR-V by constructing all necessary basic blocks and using
``OpLoopMerge`` to organize as structured loops.

The HLSL attributes for these statements are translated into SPIR-V loop control
masks according to the following table:

+-------------------------+--------------------------------------------------+
|   HLSL loop attribute   |            SPIR-V Loop Control Mask              |
+=========================+==================================================+
|        ``unroll(x)``    |                ``Unroll``                        |
+-------------------------+--------------------------------------------------+
|         ``loop``        |              ``DontUnroll``                      |
+-------------------------+--------------------------------------------------+
|        ``fastopt``      |              ``DontUnroll``                      |
+-------------------------+--------------------------------------------------+
| ``allow_uav_condition`` |           Currently Unimplemented                |
+-------------------------+--------------------------------------------------+

HLSL Functions
==============

All functions reachable from the entry-point function will be translated into
SPIR-V code. Functions not reachable from the entry-point function will be
ignored.

Entry function wrapper
----------------------

HLSL entry functions takes in parameters and returns values. These parameters
and return values can have semantics attached or if they are struct type,
the struct fields can have semantics attached. However, in Vulkan, the entry
function must be of the ``void(void)`` signature. To handle this difference,
for a given entry function ``main``, we will emit a wrapper function for it.

The wrapper function will take the name of the source code entry function,
while the source code entry function will have its name prefixed with "src.".
The wrapper function reads in stage input/builtin variables created according
to semantics and groups them into composites meeting the requirements of the
source code entry point. Then the wrapper calls the source code entry point.
The return value is extracted and components of it will be written to stage
output/builtin variables created according to semantics. For example:


.. code:: hlsl

  // HLSL source code

  struct S {
    bool a : A;
    uint2 b: B;
    float2x3 c: C;
  };

  struct T {
    S x;
    int y: D;
  };

  T main(T input) {
    return input;
  }


.. code:: spirv

  ; SPIR-V code

  %in_var_A = OpVariable %_ptr_Input_bool Input
  %in_var_B = OpVariable %_ptr_Input_v2uint Input
  %in_var_C = OpVariable %_ptr_Input_mat2v3float Input
  %in_var_D = OpVariable %_ptr_Input_int Input

  %out_var_A = OpVariable %_ptr_Output_bool Output
  %out_var_B = OpVariable %_ptr_Output_v2uint Output
  %out_var_C = OpVariable %_ptr_Output_mat2v3float Output
  %out_var_D = OpVariable %_ptr_Output_int Output

  ; Wrapper function starts

  %main    = OpFunction %void None ...
  ...      = OpLabel

  %param_var_input = OpVariable %_ptr_Function_T Function

  ; Load stage input variables and group into the expected composite

  %inA = OpLoad %bool %in_var_A
  %inB = OpLoad %v2uint %in_var_B
  %inC = OpLoad %mat2v3float %in_var_C
  %inS = OpCompositeConstruct %S %inA %inB %inC
  %inD = OpLoad %int %in_var_D
  %inT = OpCompositeConstruct %T %inS %inD
         OpStore %param_var_input %inT

  %ret = OpFunctionCall %T %src_main %param_var_input

  ; Extract component values from the composite and store into stage output variables

  %outS = OpCompositeExtract %S %ret 0
  %outA = OpCompositeExtract %bool %outS 0
          OpStore %out_var_A %outA
  %outB = OpCompositeExtract %v2uint %outS 1
          OpStore %out_var_B %outB
  %outC = OpCompositeExtract %mat2v3float %outS 2
          OpStore %out_var_C %outC
  %outD = OpCompositeExtract %int %ret 1
          OpStore %out_var_D %outD

  OpReturn
  OpFunctionEnd

  ; Source code entry point starts

  %src_main = OpFunction %T None ...

In this way, we can concentrate all stage input/output/builtin variable
manipulation in the wrapper function and handle the source code entry function
just like other nomal functions.

Function parameter
------------------

For a function ``f`` which has a parameter of type ``T``, the generated SPIR-V
signature will use type ``T*`` for the parameter. At every call site of ``f``,
additional local variables will be allocated to hold the actual arguments.
The local variables are passed in as direct function arguments. For example:

.. code:: hlsl

  // HLSL source code

  float4 f(float a, int b) { ... }

  void caller(...) {
    ...
    float4 result = f(...);
    ...
  }

.. code:: spirv

  ; SPIR-V code

                ...
  %i32PtrType = OpTypePointer Function %int
  %f32PtrType = OpTypePointer Function %float
      %fnType = OpTypeFunction %v4float %f32PtrType %i32PtrType
                ...

           %f = OpFunction %v4float None %fnType
           %a = OpFunctionParameter %f32PtrType
           %b = OpFunctionParameter %i32PtrType
                ...

      %caller = OpFunction ...
                ...
     %aAlloca = OpVariable %_ptr_Function_float Function
     %bAlloca = OpVariable %_ptr_Function_int Function
                ...
                OpStore %aAlloca ...
                OpStore %bAlloca ...
      %result = OpFunctioncall %v4float %f %aAlloca %bAlloca
                ...

This approach gives us unified handling of function parameters and local
variables: both of them are accessed via load/store instructions.

Intrinsic functions
-------------------

The following intrinsic HLSL functions have no direct SPIR-V opcode or GLSL
extended instruction mapping, so they are handled with additional steps:

- ``dot`` : performs dot product of two vectors, each containing floats or
  integers. If the two parameters are vectors of floats, we use SPIR-V's
  ``OpDot`` instruction to perform the translation. If the two parameters are
  vectors of integers, we multiply corresponding vector elements using
  ``OpIMul`` and accumulate the results using ``OpIAdd`` to compute the dot
  product.
- ``mul``: performs multiplications. Each argument may be a scalar, vector,
  or matrix. Depending on the argument type, this will be translated into
  one of the multiplication instructions.
- ``all``: returns true if all components of the given scalar, vector, or
  matrix are true. Performs conversions to boolean where necessary. Uses SPIR-V
  ``OpAll`` for scalar arguments and vector arguments. For matrix arguments,
  performs ``OpAll`` on each row, and then again on the vector containing the
  results of all rows.
- ``any``: returns true if any component of the given scalar, vector, or matrix
  is true. Performs conversions to boolean where necessary. Uses SPIR-V
  ``OpAny`` for scalar arguments and vector arguments. For matrix arguments,
  performs ``OpAny`` on each row, and then again on the vector containing the
  results of all rows.
- ``asfloat``: converts the component type of a scalar/vector/matrix from float,
  uint, or int into float. Uses ``OpBitcast``. This method currently does not
  support taking non-float matrix arguments.
- ``asint``: converts the component type of a scalar/vector/matrix from float or
  uint into int. Uses ``OpBitcast``. This method currently does not support
  conversion into integer matrices.
- ``asuint``: converts the component type of a scalar/vector/matrix from float
  or int into uint. Uses ``OpBitcast``. This method currently does not support
- ``asuint``: Converts a double into two 32-bit unsigned integers. Uses SPIR-V ``OpBitCast``.
- ``asdouble``: Converts two 32-bit unsigned integers into a double, or four 32-bit unsigned
  integers into two doubles. Uses SPIR-V ``OpVectorShuffle`` and ``OpBitCast``.
  conversion into unsigned integer matrices.
- ``isfinite`` : Determines if the specified value is finite. Since ``OpIsFinite``
  requires the ``Kernel`` capability, translation is done using ``OpIsNan`` and
  ``OpIsInf``.  A given value is finite iff it is not NaN and not infinite.
- ``isnormal`` : Determines if the specified value is normal (not zero, INF, NAN or subnormal).
  Since ``OpIsNormal`` requires the ``Kernel`` capability, the operation is emulated.
- ``clip``: Discards the current pixel if the specified value is less than zero.
  Uses conditional control flow as well as SPIR-V ``OpKill``.
- ``rcp``: Calculates a fast, approximate, per-component reciprocal.
  Uses SIR-V ``OpFDiv``.
- ``lit``: Returns a lighting coefficient vector. This vector is a float4 with
  components of (ambient, diffuse, specular, 1). How ``diffuse`` and ``specular``
  are calculated are explained `here <https://msdn.microsoft.com/en-us/library/windows/desktop/bb509619(v=vs.85).aspx>`_.
- ``D3DCOLORtoUBYTE4``: Converts a floating-point, 4D vector set by a D3DCOLOR to a UBYTE4.
  This is achieved by performing ``int4(input.zyxw * 255.002)`` using SPIR-V ``OpVectorShuffle``,
  ``OpVectorTimesScalar``, and ``OpConvertFToS``, respectively.
- ``dst``: Calculates a distance vector. The resulting vector, ``dest``, has the following specifications:
  ``dest.x = 1.0``, ``dest.y = src0.y * src1.y``, ``dest.z = src0.z``, and ``dest.w = src1.w``.
  Uses SPIR-V ``OpCompositeExtract`` and ``OpFMul``.

Using SPIR-V opcode
~~~~~~~~~~~~~~~~~~~

The following intrinsic HLSL functions have direct SPIR-V opcodes for them:

==================================== =================================
   HLSL Intrinsic Function                   SPIR-V Opcode
==================================== =================================
``AllMemoryBarrier``                 ``OpMemoryBarrier``
``AllMemoryBarrierWithGroupSync``    ``OpControlBarrier``
``countbits``                        ``OpBitCount``
``DeviceMemoryBarrier``              ``OpMemoryBarrier``
``DeviceMemoryBarrierWithGroupSync`` ``OpControlBarrier``
``ddx``                              ``OpDPdx``
``ddy``                              ``OpDPdy``
``ddx_coarse``                       ``OpDPdxCoarse``
``ddy_coarse``                       ``OpDPdyCoarse``
``ddx_fine``                         ``OpDPdxFine``
``ddy_fine``                         ``OpDPdyFine``
``fmod``                             ``OpFRem``
``fwidth``                           ``OpFwidth``
``GroupMemoryBarrier``               ``OpMemoryBarrier``
``GroupMemoryBarrierWithGroupSync``  ``OpControlBarrier``
``InterlockedAdd``                   ``OpAtomicIAdd``
``InterlockedAnd``                   ``OpAtomicAnd``
``InterlockedOr``                    ``OpAtomicOr``
``InterlockedXor``                   ``OpAtomicXor``
``InterlockedMin``                   ``OpAtomicUMin``/``OpAtomicSMin``
``InterlockedMax``                   ``OpAtomicUMax``/``OpAtomicSMax``
``InterlockedExchange``              ``OpAtomicExchange``
``InterlockedCompareExchange``       ``OpAtomicCompareExchange``
``InterlockedCompareStore``          ``OpAtomicCompareExchange``
``isnan``                            ``OpIsNan``
``isInf``                            ``OpIsInf``
``reversebits``                      ``OpBitReverse``
``transpose``                        ``OpTranspose``
``CheckAccessFullyMapped``           ``OpImageSparseTexelsResident``
==================================== =================================

Using GLSL extended instructions
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

The following intrinsic HLSL functions are translated using their equivalent
instruction in the `GLSL extended instruction set <https://www.khronos.org/registry/spir-v/specs/1.0/GLSL.std.450.html>`_.

======================= ===================================
HLSL Intrinsic Function   GLSL Extended Instruction
======================= ===================================
``abs``                 ``SAbs``/``FAbs``
``acos``                ``Acos``
``asin``                ``Asin``
``atan``                ``Atan``
``atan2``               ``Atan2``
``ceil``                ``Ceil``
``clamp``               ``SClamp``/``UClamp``/``FClamp``
``cos``                 ``Cos``
``cosh``                ``Cosh``
``cross``               ``Cross``
``degrees``             ``Degrees``
``distance``            ``Distance``
``radians``             ``Radian``
``determinant``         ``Determinant``
``exp``                 ``Exp``
``exp2``                ``exp2``
``f16tof32``            ``UnpackHalf2x16``
``f32tof16``            ``PackHalf2x16``
``faceforward``         ``FaceForward``
``firstbithigh``        ``FindSMsb`` / ``FindUMsb``
``firstbitlow``         ``FindILsb``
``floor``               ``Floor``
``fma``                 ``Fma``
``frac``                ``Fract``
``frexp``               ``FrexpStruct``
``ldexp``               ``Ldexp``
``length``              ``Length``
``lerp``                ``FMix``
``log``                 ``Log``
``log10``               ``Log2`` (scaled by ``1/log2(10)``)
``log2``                ``Log2``
``mad``                 ``Fma``
``max``                 ``SMax``/``UMax``/``NMax``/``FMax``
``min``                 ``SMin``/``UMin``/``NMin``/``FMin``
``modf``                ``ModfStruct``
``normalize``           ``Normalize``
``pow``                 ``Pow``
``reflect``             ``Reflect``
``refract``             ``Refract``
``round``               ``RoundEven``
``rsqrt``               ``InverseSqrt``
``saturate``            ``FClamp``
``sign``                ``SSign``/``FSign``
``sin``                 ``Sin``
``sincos``              ``Sin`` and ``Cos``
``sinh``                ``Sinh``
``smoothstep``          ``SmoothStep``
``sqrt``                ``Sqrt``
``step``                ``Step``
``tan``                 ``Tan``
``tanh``                ``Tanh``
``trunc``               ``Trunc``
======================= ===================================

Note on NMax,Nmin,FMax & FMin:

This compiler supports the ``--ffinite-math-only`` option, which allows
assuming non-NaN parameters to some operations. ``min`` & ``max`` intrinsics
will by default generate ``NMin`` & ``NMax`` instructions, but if this option
is enabled, ``FMin`` & ``FMax`` can be generated instead.

Synchronization intrinsics
~~~~~~~~~~~~~~~~~~~~~~~~~~

Synchronization intrinsics are translated into ``OpMemoryBarrier`` (for those
non-``WithGroupSync`` variants) or ``OpControlBarrier`` (for those ``WithGroupSync``
variants) instructions with parameters:

======================= ============ ===== ======= ========= ==============
       HLSL                SPIR-V          SPIR-V Memory Semantics
----------------------- ------------ --------------------------------------
     Intrinsic          Memory Scope Image Uniform Workgroup AcquireRelease
======================= ============ ===== ======= ========= ==============
``AllMemoryBarrier``    Device       ✓       ✓         ✓          ✓
``DeviceMemoryBarrier`` Device       ✓       ✓                    ✓
``GroupMemoryBarrier``  Workgroup                       ✓          ✓
======================= ============ ===== ======= ========= ==============

For the ``*WithGroupSync`` intrinsics, SPIR-V memory scope and semantics are the
same as their counterparts in the above. They have an additional execution
scope:

==================================== ======================
       HLSL Intrinsic                SPIR-V Execution Scope
==================================== ======================
``AllMemoryBarrierWithGroupSync``    Workgroup
``DeviceMemoryBarrierWithGroupSync`` Workgroup
``GroupMemoryBarrierWithGroupSync``  Workgroup
==================================== ======================

HLSL OO features
================

A HLSL struct/class member method is translated into a normal SPIR-V function,
whose signature has an additional first parameter for the struct/class called
upon. Every calling site of the method is generated to pass in the object as
the first argument.

HLSL struct/class static member variables are translated into SPIR-V variables
in the ``Private`` storage class.

HLSL Methods
============

This section lists how various HLSL methods are mapped.

Buffers
-------

``Buffer``
~~~~~~~~~~

``.Load()``
+++++++++++
Since Buffers are represented as ``OpTypeImage`` with ``Sampled`` set to 1
(meaning to be used with a sampler), ``OpImageFetch`` is used to perform this
operation. The return value of ``OpImageFetch`` is always a four-component
vector; so proper additional instructions are generated to truncate the vector
and return the desired number of elements.
If an output unsigned integer ``status`` argument is present, ``OpImageSparseFetch``
is used instead. The resulting SPIR-V ``Residency Code`` will be written to ``status``.

``operator[]``
++++++++++++++
Handled similarly as ``.Load()``.

``.GetDimensions()``
++++++++++++++++++++
Since Buffers are represented as ``OpTypeImage`` with dimension of ``Buffer``,
``OpImageQuerySize`` is used to perform this operation.

``RWBuffer``
~~~~~~~~~~~~

``.Load()``
+++++++++++
Since RWBuffers are represented as ``OpTypeImage`` with ``Sampled`` set to 2
(meaning to be used without a sampler), ``OpImageRead`` is used to perform this
operation. If an output unsigned integer ``status`` argument is present, ``OpImageSparseRead``
is used instead. The resulting SPIR-V ``Residency Code`` will be written to ``status``.

``operator[]``
++++++++++++++
Using ``operator[]`` for reading is handled similarly as ``.Load()``, while for
writing, the ``OpImageWrite`` instruction is generated.

``.GetDimensions()``
++++++++++++++++++++
Since RWBuffers are represented as ``OpTypeImage`` with dimension of ``Buffer``,
``OpImageQuerySize`` is used to perform this operation.

``StructuredBuffer`` and ``RWStructuredBuffer``
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

``.GetDimensions()``
++++++++++++++++++++
Since StructuredBuffers/RWStructuredBuffers are represented as a struct with one
member that is a runtime array of structures, ``OpArrayLength`` is invoked on
the runtime array in order to find the dimension.

``ByteAddressBuffer``
~~~~~~~~~~~~~~~~~~~~~

``.GetDimensions()``
++++++++++++++++++++
Since ByteAddressBuffers are represented as a struct with one member that is a
runtime array of unsigned integers, ``OpArrayLength`` is invoked on the runtime array
in order to find the number of unsigned integers. This is then multiplied by 4 to find
the number of bytes.

``.Load()``, ``.Load2()``, ``.Load3()``, ``.Load4()``
+++++++++++++++++++++++++++++++++++++++++++++++++++++
ByteAddressBuffers are represented as a struct with one member that is a runtime array of
unsigned integers. The ``address`` argument passed to the function is first divided by 4
in order to find the offset into the array (because each array element is 4 bytes). The
SPIR-V ``OpAccessChain`` instruction is then used to access that offset, and ``OpLoad`` is
used to load a 32-bit unsigned integer. For ``Load2``, ``Load3``, and ``Load4``, this is
done 2, 3, and 4 times, respectively. Each time the word offset is incremented by 1 before
performing ``OpAccessChain``. After all ``OpLoad`` operations are performed, a vector is
constructed with all the resulting values.

``RWByteAddressBuffer``
~~~~~~~~~~~~~~~~~~~~~~~

``.GetDimensions()``
++++++++++++++++++++
Since RWByteAddressBuffers are represented as a struct with one member that is a
runtime array of unsigned integers, ``OpArrayLength`` is invoked on the runtime array
in order to find the number of unsigned integers. This is then multiplied by 4 to find
the number of bytes.

``.Load()``, ``.Load2()``, ``.Load3()``, ``.Load4()``
+++++++++++++++++++++++++++++++++++++++++++++++++++++
RWByteAddressBuffers are represented as a struct with one member that is a runtime array of
unsigned integers. The ``address`` argument passed to the function is first divided by 4
in order to find the offset into the array (because each array element is 4 bytes). The
SPIR-V ``OpAccessChain`` instruction is then used to access that offset, and ``OpLoad`` is
used to load a 32-bit unsigned integer. For ``Load2``, ``Load3``, and ``Load4``, this is
done 2, 3, and 4 times, respectively. Each time the word offset is incremented by 1 before
performing ``OpAccessChain``. After all ``OpLoad`` operations are performed, a vector is
constructed with all the resulting values.

``.Store()``, ``.Store2()``, ``.Store3()``, ``.Store4()``
+++++++++++++++++++++++++++++++++++++++++++++++++++++++++
RWByteAddressBuffers are represented as a struct with one member that is a runtime array of
unsigned integers. The ``address`` argument passed to the function is first divided by 4
in order to find the offset into the array (because each array element is 4 bytes). The
SPIR-V ``OpAccessChain`` instruction is then used to access that offset, and ``OpStore`` is
used to store a 32-bit unsigned integer. For ``Store2``, ``Store3``, and ``Store4``, this is
done 2, 3, and 4 times, respectively. Each time the word offset is incremented by 1 before
performing ``OpAccessChain``.

``.Interlocked*()``
+++++++++++++++++++

================================= =================================
     HLSL Intrinsic Method                SPIR-V Opcode
================================= =================================
``.InterlockedAdd()``             ``OpAtomicIAdd``
``.InterlockedAnd()``             ``OpAtomicAnd``
``.InterlockedOr()``              ``OpAtomicOr``
``.InterlockedXor()``             ``OpAtomicXor``
``.InterlockedMin()``             ``OpAtomicUMin``/``OpAtomicSMin``
``.InterlockedMax()``             ``OpAtomicUMax``/``OpAtomicSMax``
``.InterlockedExchange()``        ``OpAtomicExchange``
``.InterlockedCompareExchange()`` ``OpAtomicCompareExchange``
``.InterlockedCompareStore()``    ``OpAtomicCompareExchange``
================================= =================================

``AppendStructuredBuffer``
~~~~~~~~~~~~~~~~~~~~~~~~~~

``.Append()``
+++++++++++++

The associated counter number will be increased by 1 using ``OpAtomicIAdd``.
The return value of ``OpAtomicIAdd``, which is the original count number, will
be used as the index for storing the new element. E.g., for ``buf.Append(vec)``:

.. code:: spirv

  %counter = OpAccessChain %_ptr_Uniform_int %counter_var_buf %uint_0
    %index = OpAtomicIAdd %uint %counter %uint_1 %uint_0 %uint_1
      %ptr = OpAccessChain %_ptr_Uniform_v4float %buf %uint_0 %index
      %val = OpLoad %v4float %vec
             OpStore %ptr %val

``.GetDimensions()``
++++++++++++++++++++
Since AppendStructuredBuffers are represented as a struct with one member that
is a runtime array, ``OpArrayLength`` is invoked on the runtime array in order
to find the number of elements. The stride is also calculated based on GLSL
``std430`` as explained above.

``ConsumeStructuredBuffer``
~~~~~~~~~~~~~~~~~~~~~~~~~~~

``.Consume()``
++++++++++++++

The associated counter number will be decreased by 1 using ``OpAtomicISub``.
The return value of ``OpAtomicISub`` minus 1, which is the new count number,
will be used as the index for reading the new element. E.g., for
``buf.Consume(vec)``:

.. code:: spirv

  %counter = OpAccessChain %_ptr_Uniform_int %counter_var_buf %uint_0
     %prev = OpAtomicISub %uint %counter %uint_1 %uint_0 %uint_1
    %index = OpISub %uint %prev %uint_1
      %ptr = OpAccessChain %_ptr_Uniform_v4float %buf %uint_0 %index
      %val = OpLoad %v4float %vec
             OpStore %ptr %val

``.GetDimensions()``
++++++++++++++++++++
Since ConsumeStructuredBuffers are represented as a struct with one member that
is a runtime array, ``OpArrayLength`` is invoked on the runtime array in order
to find the number of elements. The stride is also calculated based on GLSL
``std430`` as explained above.

Read-only textures
------------------

Methods common to all texture types are explained in the "common texture methods"
section. Methods unique to a specific texture type is explained in the section
for that texture type.

Common texture methods
~~~~~~~~~~~~~~~~~~~~~~

``.Sample(sampler, location[, offset][, clamp][, Status])``
+++++++++++++++++++++++++++++++++++++++++++++++++++++++++++

Not available to ``Texture2DMS`` and ``Texture2DMSArray``.

The ``OpImageSampleImplicitLod`` instruction is used to translate ``.Sample()``
since texture types are represented as ``OpTypeImage``. An ``OpSampledImage`` is
created based on the ``sampler`` passed to the function. The resulting sampled
image and the ``location`` passed to the function are used as arguments to
``OpImageSampleImplicitLod``, with the optional ``offset`` tranlated into
addtional SPIR-V image operands ``ConstOffset`` or ``Offset`` on it. The optional
``clamp`` argument will be translated to the ``MinLod`` image operand.

If an output unsigned integer ``status`` argument is present,
``OpImageSparseSampleImplicitLod`` is used instead. The resulting SPIR-V
``Residency Code`` will be written to ``status``.

``.SampleLevel(sampler, location, lod[, offset][, Status])``
++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++

Not available to ``Texture2DMS`` and ``Texture2DMSArray``.

The ``OpImageSampleExplicitLod`` instruction is used to translate this method.
An ``OpSampledImage`` is created based on the ``sampler`` passed to the function.
The resulting sampled image and the ``location`` passed to the function are used
as arguments to ``OpImageSampleExplicitLod``. The ``lod`` passed to the function
is attached to the instruction as an SPIR-V image operands ``Lod``. The optional
``offset`` is also tranlated into addtional SPIR-V image operands ``ConstOffset``
or ``Offset`` on it.

If an output unsigned integer ``status`` argument is present,
``OpImageSparseSampleExplicitLod`` is used instead. The resulting SPIR-V
``Residency Code`` will be written to ``status``.

``.SampleGrad(sampler, location, ddx, ddy[, offset][, clamp][, Status])``
+++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++

Not available to ``Texture2DMS`` and ``Texture2DMSArray``.

Similarly to ``.SampleLevel``, the ``ddx`` and ``ddy`` parameter are attached to
the ``OpImageSampleExplicitLod`` instruction as an SPIR-V image operands
``Grad``. The optional ``clamp`` argument will be translated into the ``MinLod``
image operand.

If an output unsigned integer ``status`` argument is present,
``OpImageSparseSampleExplicitLod`` is used instead. The resulting SPIR-V
``Residency Code`` will be written to ``status``.

``.SampleBias(sampler, location, bias[, offset][, clamp][, Status])``
+++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++

Not available to ``Texture2DMS`` and ``Texture2DMSArray``.

The translation is similar to ``.Sample()``, with the ``bias`` parameter
attached to the ``OpImageSampleImplicitLod`` instruction as an SPIR-V image
operands ``Bias``.

If an output unsigned integer ``status`` argument is present,
``OpImageSparseSampleImplicitLod`` is used instead. The resulting SPIR-V
``Residency Code`` will be written to ``status``.

``.SampleCmp(sampler, location, comparator[, offset][, clamp][, Status])``
++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++

Not available to ``Texture3D``, ``Texture2DMS``, and ``Texture2DMSArray``.

The translation is similar to ``.Sample()``, but the
``OpImageSampleDrefImplicitLod`` instruction are used.

If an output unsigned integer ``status`` argument is present,
``OpImageSparseSampleDrefImplicitLod`` is used instead. The resulting SPIR-V
``Residency Code`` will be written to ``status``.

``.SampleCmpLevelZero(sampler, location, comparator[, offset][, Status])``
++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++

Not available to ``Texture3D``, ``Texture2DMS``, and ``Texture2DMSArray``.

The translation is similar to ``.Sample()``, but the
``OpImageSampleDrefExplicitLod`` instruction are used, with the additional
``Lod`` image operands set to 0.0.

If an output unsigned integer ``status`` argument is present,
``OpImageSparseSampleDrefExplicitLod`` is used instead. The resulting SPIR-V
``Residency Code`` will be written to ``status``.

``.SampleCmpBias(sampler, location, bias, comparator[, offset][, clamp][, Status])``
++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++

Not available to ``Texture3D``, ``Texture2DMS``, and ``Texture2DMSArray``.

The translation is similar to ``.SampleBias()``, but the
``OpImageSampleDrefImplicitLod`` instruction is used.

If an output unsigned integer ``status`` argument is present,
``OpImageSparseSampleDrefImplicitLod`` is used instead. The resulting SPIR-V
``Residency Code`` will be written to ``status``.

``.SampleCmpGrad(sampler, location, ddx, ddy, comparator[, offset][, clamp][, Status])``
++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++

Not available to ``Texture3D``, ``Texture2DMS``, and ``Texture2DMSArray``.

The translation is similar to ``.SampleGrad()``, but the
``OpImageSampleDrefExplicitLod`` instruction are used.

If an output unsigned integer ``status`` argument is present,
``OpImageSparseSampleDrefExplicitLod`` is used instead. The resulting SPIR-V
``Residency Code`` will be written to ``status``.

``.Gather()``
+++++++++++++

Available to ``Texture2D``, ``Texture2DArray``, ``TextureCube``, and
``TextureCubeArray``.

The translation is similar to ``.Sample()``, but the ``OpImageGather``
instruction is used, with component setting to 0.

If an output unsigned integer ``status`` argument is present,
``OpImageSparseGather`` is used instead. The resulting SPIR-V
``Residency Code`` will be written to ``status``.

``.GatherRed()``, ``.GatherGreen()``, ``.GatherBlue()``, ``.GatherAlpha()``
+++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++

Available to ``Texture2D``, ``Texture2DArray``, ``TextureCube``, and
``TextureCubeArray``.

The ``OpImageGather`` instruction is used to translate these functions, with
component setting to 0, 1, 2, and 3 respectively.

There are a few overloads for these functions:

- For those overloads taking 4 offset parameters, those offset parameters will
  be conveyed as an additional ``ConstOffsets`` image operands to the
  instruction if those offset parameters are all constants. Otherwise,
  4 separate ``OpImageGather`` instructions will be emitted to get each texel
  from each offset, using the ``Offset`` image operands.
- For those overloads with the ``status`` parameter, ``OpImageSparseGather``
  is used instead, and the resulting SPIR-V ``Residency Code`` will be
  written to ``status``.

``.GatherCmp()``
++++++++++++++++

Available to ``Texture2D``, ``Texture2DArray``, ``TextureCube``, and
``TextureCubeArray``.

The translation is similar to ``.Sample()``, but the ``OpImageDrefGather``
instruction is used.

For the overload with the output unsigned integer ``status`` argument,
``OpImageSparseDrefGather`` is used instead. The resulting SPIR-V
``Residency Code`` will be written to ``status``.


``.GatherCmpRed()``
+++++++++++++++++++

Available to ``Texture2D``, ``Texture2DArray``, ``TextureCube``, and
``TextureCubeArray``.

The translation is the same as ``.GatherCmp()``.

``.Load(location[, sampleIndex][, offset])``
++++++++++++++++++++++++++++++++++++++++++++

The ``OpImageFetch`` instruction is used for translation because texture types
are represented as ``OpTypeImage``. The last element in the ``location``
parameter will be used as arguments to the ``Lod`` SPIR-V image operand attached
to the ``OpImageFetch`` instruction, and the rest are used as the coordinate
argument to the instruction. ``offset`` is handled similarly to ``.Sample()``.
The return value of ``OpImageFetch`` is always a four-component vector; so
proper additional instructions are generated to truncate the vector and return
the desired number of elements.

For the overload with the output unsigned integer ``status`` argument,
``OpImageSparseFetch`` is used instead. The resulting SPIR-V
``Residency Code`` will be written to ``status``.

``operator[]``
++++++++++++++
Handled similarly as ``.Load()``.

``.mips[lod][position]``
++++++++++++++++++++++++

Not available to ``TextureCube``, ``TextureCubeArray``, ``Texture2DMS``, and
``Texture2DMSArray``.

This method is translated into the ``OpImageFetch`` instruction. The ``lod``
parameter is attached to the instruction as the parameter to the ``Lod`` SPIR-V
image operands. The ``position`` parameter are used as the coordinate to the
instruction directly.

``.CalculateLevelOfDetail()`` and ``.CalculateLevelOfDetailUnclamped()``
++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++

Not available to ``Texture2DMS`` and ``Texture2DMSArray``.

Since texture types are represented as ``OpTypeImage``, the ``OpImageQueryLod``
instruction is used for translation. An ``OpSampledImage`` is created based on
the ``SamplerState`` or ``SamplerComparisonState`` passed to the function. The
resulting sampled image and the coordinate passed to the function are used to
invoke ``OpImageQueryLod``. The result of ``OpImageQueryLod`` is a ``float2``.
The first element contains the mipmap array layer. The second element contains
the unclamped level of detail.

``Texture1D``
~~~~~~~~~~~~~

``.GetDimensions(width)`` or ``.GetDimensions(MipLevel, width, NumLevels)``
+++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
Since Texture1D is represented as ``OpTypeImage``, the ``OpImageQuerySizeLod`` instruction
is used for translation. If a ``MipLevel`` argument is passed to ``GetDimensions``, it will
be used as the ``Lod`` parameter of the query instruction. Otherwise, ``Lod`` of ``0`` be used.

``Texture1DArray``
~~~~~~~~~~~~~~~~~~

``.GetDimensions(width, elements)`` or ``.GetDimensions(MipLevel, width, elements, NumLevels)``
+++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
Since Texture1DArray is represented as ``OpTypeImage``, the ``OpImageQuerySizeLod`` instruction
is used for translation. If a ``MipLevel`` argument is present, it will be used as the
``Lod`` parameter of the query instruction. Otherwise, ``Lod`` of ``0`` be used.

``Texture2D``
~~~~~~~~~~~~~

``.GetDimensions(width, height)`` or ``.GetDimensions(MipLevel, width, height, NumLevels)``
+++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
Since Texture2D is represented as ``OpTypeImage``, the ``OpImageQuerySizeLod`` instruction
is used for translation. If a ``MipLevel`` argument is present, it will be used as the
``Lod`` parameter of the query instruction. Otherwise, ``Lod`` of ``0`` be used.

``Texture2DArray``
~~~~~~~~~~~~~~~~~~

``.GetDimensions(width, height, elements)`` or ``.GetDimensions(MipLevel, width, height, elements, NumLevels)``
+++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
Since Texture2DArray is represented as ``OpTypeImage``, the ``OpImageQuerySizeLod`` instruction
is used for translation. If a ``MipLevel`` argument is present, it will be used as the
``Lod`` parameter of the query instruction. Otherwise, ``Lod`` of ``0`` be used.

``Texture3D``
~~~~~~~~~~~~~

``.GetDimensions(width, height, depth)`` or ``.GetDimensions(MipLevel, width, height, depth, NumLevels)``
+++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
Since Texture3D is represented as ``OpTypeImage``, the ``OpImageQuerySizeLod`` instruction
is used for translation. If a ``MipLevel`` argument is present, it will be used as the
``Lod`` parameter of the query instruction. Otherwise, ``Lod`` of ``0`` be used.

``Texture2DMS``
~~~~~~~~~~~~~~~

``.sample[sample][position]``
+++++++++++++++++++++++++++++
This method is translated into the ``OpImageFetch`` instruction. The ``sample``
parameter is attached to the instruction as the parameter to the ``Sample``
SPIR-V image operands. The ``position`` parameter are used as the coordinate to
the instruction directly.

``.GetDimensions(width, height, numSamples)``
+++++++++++++++++++++++++++++++++++++++++++++
Since Texture2DMS is represented as ``OpTypeImage`` with ``MS`` of ``1``, the ``OpImageQuerySize`` instruction
is used to get the width and the height. Furthermore, ``OpImageQuerySamples`` is used to get the numSamples.

``.GetSamplePosition(index)``
+++++++++++++++++++++++++++++
There are no direct mapping SPIR-V instructions for this method. Right now, it
is translated into the SPIR-V code for the following HLSL source code:

.. code:: hlsl

  // count is the number of samples in the Texture2DMS(Array)
  // index is the index of the sample we are trying to get the position

  static const float2 pos2[] = {
      { 4.0/16.0,  4.0/16.0 }, {-4.0/16.0, -4.0/16.0 },
  };

  static const float2 pos4[] = {
      {-2.0/16.0, -6.0/16.0 }, { 6.0/16.0, -2.0/16.0 }, {-6.0/16.0,  2.0/16.0 }, { 2.0/16.0,  6.0/16.0 },
  };

  static const float2 pos8[] = {
      { 1.0/16.0, -3.0/16.0 }, {-1.0/16.0,  3.0/16.0 }, { 5.0/16.0,  1.0/16.0 }, {-3.0/16.0, -5.0/16.0 },
      {-5.0/16.0,  5.0/16.0 }, {-7.0/16.0, -1.0/16.0 }, { 3.0/16.0,  7.0/16.0 }, { 7.0/16.0, -7.0/16.0 },
  };

  static const float2 pos16[] = {
      { 1.0/16.0,  1.0/16.0 }, {-1.0/16.0, -3.0/16.0 }, {-3.0/16.0,  2.0/16.0 }, { 4.0/16.0, -1.0/16.0 },
      {-5.0/16.0, -2.0/16.0 }, { 2.0/16.0,  5.0/16.0 }, { 5.0/16.0,  3.0/16.0 }, { 3.0/16.0, -5.0/16.0 },
      {-2.0/16.0,  6.0/16.0 }, { 0.0/16.0, -7.0/16.0 }, {-4.0/16.0, -6.0/16.0 }, {-6.0/16.0,  4.0/16.0 },
      {-8.0/16.0,  0.0/16.0 }, { 7.0/16.0, -4.0/16.0 }, { 6.0/16.0,  7.0/16.0 }, {-7.0/16.0, -8.0/16.0 },
  };

  float2 position = float2(0.0f, 0.0f);

  if (count == 2) {
      position = pos2[index];
  } else if (count == 4) {
      position = pos4[index];
  } else if (count == 8) {
      position = pos8[index];
  } else if (count == 16) {
      position = pos16[index];
  }

From the above, it's clear that the current implementation only supports standard
sample settings, i.e., with 1, 2, 4, 8, or 16 samples. For other cases, the
implementation will just return `(float2)0`.

``Texture2DMSArray``
~~~~~~~~~~~~~~~~~~~~

``.sample[sample][position]``
+++++++++++++++++++++++++++++
This method is translated into the ``OpImageFetch`` instruction. The ``sample``
parameter is attached to the instruction as the parameter to the ``Sample``
SPIR-V image operands. The ``position`` parameter are used as the coordinate to
the instruction directly.

``.GetDimensions(width, height, elements, numSamples)``
+++++++++++++++++++++++++++++++++++++++++++++++++++++++
Since Texture2DMS is represented as ``OpTypeImage`` with ``MS`` of ``1``, the ``OpImageQuerySize`` instruction
is used to get the width, the height, and the elements. Furthermore, ``OpImageQuerySamples`` is used to get the numSamples.

``.GetSamplePosition(index)``
+++++++++++++++++++++++++++++
Similar to Texture2D.

``TextureCube``
~~~~~~~~~~~~~~~

``TextureCubeArray``
~~~~~~~~~~~~~~~~~~~~

Read-write textures
-------------------

Methods common to all texture types are explained in the "common texture methods"
section. Methods unique to a specific texture type is explained in the section
for that texture type.

Common texture methods
~~~~~~~~~~~~~~~~~~~~~~

``.Load()``
+++++++++++
Since read-write texture types are represented as ``OpTypeImage`` with
``Sampled`` set to 2 (meaning to be used without a sampler), ``OpImageRead`` is
used to perform this operation.

For the overload with the output unsigned integer ``status`` argument,
``OpImageSparseRead`` is used instead. The resulting SPIR-V
``Residency Code`` will be written to ``status``.

``operator[]``
++++++++++++++
Using ``operator[]`` for reading is handled similarly as ``.Load()``, while for
writing, the ``OpImageWrite`` instruction is generated.

``RWTexture1D``
~~~~~~~~~~~~~~~

``.GetDimensions(width)``
+++++++++++++++++++++++++
The ``OpImageQuerySize`` instruction is used to find the width.

``RWTexture1DArray``
~~~~~~~~~~~~~~~~~~~~

``.GetDimensions(width, elements)``
+++++++++++++++++++++++++++++++++++
The ``OpImageQuerySize`` instruction is used to get a uint2. The first element
is the width, and the second is the elements.

``RWTexture2D``
~~~~~~~~~~~~~~~

``.GetDimensions(width, height)``
+++++++++++++++++++++++++++++++++
The ``OpImageQuerySize`` instruction is used to get a uint2. The first element is the width, and the second
element is the height.

``RWTexture2DArray``
~~~~~~~~~~~~~~~~~~~~

``.GetDimensions(width, height, elements)``
+++++++++++++++++++++++++++++++++++++++++++
The ``OpImageQuerySize`` instruction is used to get a uint3. The first element is the width, the second
element is the height, and the third is the elements.

``RWTexture3D``
~~~~~~~~~~~~~~~

``.GetDimensions(width, height, depth)``
++++++++++++++++++++++++++++++++++++++++
The ``OpImageQuerySize`` instruction is used to get a uint3. The first element is the width, the second
element is the height, and the third element is the depth.

HLSL Shader Stages
==================

Hull Shaders
------------

Hull shaders corresponds to Tessellation Control Shaders (TCS) in Vulkan.
This section describes how Hull shaders are translated to SPIR-V for Vulkan.

Hull Entry Point Attributes
~~~~~~~~~~~~~~~~~~~~~~~~~~~
The following HLSL attributes are attached to the main entry point of hull shaders
and are translated to SPIR-V execution modes according to the table below:

.. table:: Mapping from HLSL attribute to SPIR-V execution mode

+-------------------------+---------------------+--------------------------+
| HLSL Attribute          |   value             | SPIR-V Execution Mode    |
+=========================+=====================+==========================+
|                         | ``quad``            | ``Quads``                |
|                         +---------------------+--------------------------+
|    ``domain``           | ``tri``             | ``Triangles``            |
|                         +---------------------+--------------------------+
|                         | ``isoline``         | ``Isoline``              |
+-------------------------+---------------------+--------------------------+
|                         | ``integer``         | ``SpacingEqual``         |
|                         +---------------------+--------------------------+
|                         | ``fractional_even`` | ``SpacingFractionalEven``|
|    ``partitioning``     +---------------------+--------------------------+
|                         | ``fractional_odd``  | ``SpacingFractionalOdd`` |
|                         +---------------------+--------------------------+
|                         | ``pow2``            |           N/A            |
+-------------------------+---------------------+--------------------------+
|                         | ``point``           | ``PointMode``            |
|                         +---------------------+--------------------------+
|                         | ``line``            |           N/A            |
|  ``outputtopology``     +---------------------+--------------------------+
|                         | ``triangle_cw``     | ``VertexOrderCw``        |
|                         +---------------------+--------------------------+
|                         | ``triangle_ccw``    | ``VertexOrderCcw``       |
+-------------------------+---------------------+--------------------------+
|``outputcontrolpoints``  | ``n``               | ``OutputVertices n``     |
+-------------------------+---------------------+--------------------------+

The ``patchconstfunc`` attribute does not have a direct equivalent in SPIR-V.
It specifies the name of the Patch Constant Function. This function is run only
once per patch. This is further described below.

InputPatch and OutputPatch
~~~~~~~~~~~~~~~~~~~~~~~~~~
Both of ``InputPatch<T, N>`` and ``OutputPatch<T, N>`` are translated to an array
of constant size ``N`` where each element is of type ``T``.

InputPatch can be passed to the Hull shader main entry function as well as the
patch constant function. This would include information about each of the ``N``
vertices that are input to the tessellation control shader.

OutputPatch is an array containing ``N`` elements (where ``N`` is the number of
output vertices). Each element of the array is the hull shader output for each
output vertex. For example, each element of ``OutputPatch<HSOutput, 3>`` is each
output value of the hull shader function for each ``SV_OutputControlPointID``.
It is shared between threads i.e., in the patch constant function, threads for
the same patch must see the same values for the elements of
``OutputPatch<HSOutput, 3>``.

The SPIR-V ``InvocationID`` (``SV_OutputControlPointID`` in HLSL) is used to index
into the InputPatch and OutputPatch arrays to read/write information for the given
vertex.

The hull main entry function in HLSL returns only one value (say, of type ``T``), but
that function is in fact executed once for each control point. The Vulkan spec requires that
"Tessellation control shader per-vertex output variables and blocks, and tessellation control,
tessellation evaluation, and geometry shader per-vertex input variables and blocks are required
to be declared as arrays, with each element representing input or output values for a single vertex
of a multi-vertex primitive". Therefore, we need to create a stage output variable that is an array
with elements of type ``T``. The number of elements of the array is equal to the number of
output control points. Each final output control point is written into the corresponding element in
the array using SV_OutputControlPointID as the index.

Patch Constant Function
~~~~~~~~~~~~~~~~~~~~~~~
As mentioned above, the patch constant function is to be invoked only once per patch.
As a result, in the SPIR-V module, the `entry function wrapper`_ will first invoke the
main entry function, and then use an ``OpControlBarrier`` to wait for all vertex
processing to finish. After the barrier, *only* the first thread (with InvocationID of 0)
will invoke the patch constant function. Since the first thread has to see the
OutputPatch that contains output of the hull shader function for other threads,
we have to use the output stage variable (with Output storage class) of the
hull shader function for OutputPatch that can be an input to the patch constant
function.

The information resulting from the patch constant function will also be returned
as stage output variables. The output struct of the patch constant function must include
``SV_TessFactor`` and ``SV_InsideTessFactor`` fields which will translate to
``TessLevelOuter`` and ``TessLevelInner`` builtin variables, respectively. And the rest
will be flattened and translated into normal stage output variables, one for each field.

Geometry Shaders
----------------

This section describes how geometry shaders are translated to SPIR-V for Vulkan.

Geometry Shader Entry Point Attributes
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
The following HLSL attribute is attached to the main entry point of geometry shaders
and is translated to SPIR-V execution mode as follows:

.. table:: Mapping from geometry shader HLSL attribute to SPIR-V execution mode

+-------------------------+---------------------+--------------------------+
| HLSL Attribute          |   value             | SPIR-V Execution Mode    |
+=========================+=====================+==========================+
|``maxvertexcount``       | ``n``               | ``OutputVertices n``     |
+-------------------------+---------------------+--------------------------+
|``instance``             | ``n``               | ``Invocations n``        |
+-------------------------+---------------------+--------------------------+

Translation for Primitive Types
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
Geometry shader vertex inputs may be qualified with primitive types. Only one primitive type
is allowed to be used in a given geometry shader. The following table shows the SPIR-V execution
mode that is used in order to represent the given primitive type.

.. table:: Mapping from geometry shader primitive type to SPIR-V execution mode

+---------------------+-----------------------------+
| HLSL Primitive Type | SPIR-V Execution Mode       |
+=====================+=============================+
|``point``            | ``InputPoints``             |
+---------------------+-----------------------------+
|``line``             | ``InputLines``              |
+---------------------+-----------------------------+
|``triangle``         | ``Triangles``               |
+---------------------+-----------------------------+
|``lineadj``          | ``InputLinesAdjacency``     |
+---------------------+-----------------------------+
|``triangleadj``      | ``InputTrianglesAdjacency`` |
+---------------------+-----------------------------+

Translation of Output Stream Types
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
Supported output stream types in geometry shaders are: ``PointStream<T>``,
``LineStream<T>``, and ``TriangleStream<T>``. These types are translated as the underlying
type ``T``, which is recursively flattened into stand-alone variables for each field.

Furthermore, output stream objects passed to geometry shader entry points are
required to be annotated with ``inout``, but the generated SPIR-V only contains
stage output variables for them.

The following table shows the SPIR-V execution mode that is used in order to represent the
given output stream.

.. table:: Mapping from geometry shader output stream type to SPIR-V execution mode

+---------------------+-----------------------------+
| HLSL Output Stream  | SPIR-V Execution Mode       |
+=====================+=============================+
|``PointStream``      | ``OutputPoints``            |
+---------------------+-----------------------------+
|``LineStream``       | ``OutputLineStrip``         |
+---------------------+-----------------------------+
|``TriangleStream``   | ``OutputTriangleStrip``     |
+---------------------+-----------------------------+

In other shader stages, stage output variables are only written in the `entry
function wrapper`_ after calling the source code entry function. However,
geometry shaders can output as many vertices as they wish, by calling the
``.Append()`` method on the output stream object. Therefore, it is incorrect to
have only one flush in the entry function wrapper like other stages. Instead,
each time a ``*Stream<T>::Append()`` is encountered, all stage output variables
behind ``T`` will be flushed before SPIR-V ``OpEmitVertex`` instruction is
generated. ``.RestartStrip()`` method calls will be translated into the SPIR-V
``OpEndPrimitive`` instruction.

Raytracing Shader Stages
------------------------

DirectX Raytracing adds six new shader stages for raytracing namely ray generation, intersection, closest-hit,
any-hit, miss and callable.

| Refer to following pages for details:
| https://docs.microsoft.com/en-us/windows/desktop/direct3d12/direct3d-12-raytracing
| https://docs.microsoft.com/en-us/windows/desktop/direct3d12/direct3d-12-raytracing-hlsl-reference


Flow chart for various stages in a raytracing pipeline is as follows:
::

          +---------------------+
          |   Ray generation    |
          +---------------------+
                     |
          TraceRay() |                      +--------------+
                     |      _ _ _ _ _ _ _ _ |   Any Hit    |
                     |     |                +--------------+
                     V     V                       ^
          +---------------------+                  |
          |    Acceleration     |           +--------------+
          |     Structure       |           | Intersection |
          |     Traversal       |           +--------------+
          +---------------------+                  ^
                    |        |                     |
                    |        |_ _ _ _ _ _ _ _ _ _ _|
                    |
                    |
                    V
          +--------------------+            +-------------+
          |      Is Hit ?      |            |  Callable   |
          +--------------------+            +-------------+
              |            |
          Yes |            | No
              V            V
         +---------+    +------+
         | Closest |    | Miss |
         |   Hit   |    |      |
         +---------+    +------+


| *Note : DXC does not add special shader profiles for raytracing under -T option.*
| *All raytracing shaders must be compiled as library using lib_6_3/lib_6_4 profile option.*
| *Note : DXC now targets SPV_KHR_ray_tracing extension by default.*
| *This extension is provisional and subject to change*.
| *To compile for NV extension use -fspv-extension=SPV_NV_ray_tracing.*

Ray Generation Stage
~~~~~~~~~~~~~~~~~~~~

| Ray generation shaders start ray tracing work and work on a compute-like 3D grid of threads.
| Entry functions of this stage type are annotated with **[shader("raygeneration")]** in HLSL source.
| Such entry functions must return void and do not accept any arguments.

| For example:

.. code:: hlsl

  RaytracingAccelerationStructure rs;
  struct Payload
  {
  float4 color;
  };
  [shader("raygeneration")]
  void main() {
    Payload myPayload = { float4(0.0f,0.0f,0.0f,0.0f) };
    RayDesc rayDesc;
    rayDesc.Origin = float3(0.0f, 0.0f, 0.0f);
    rayDesc.Direction = float3(0.0f, 0.0f, -1.0f);
    rayDesc.TMin = 0.0f;
    rayDesc.TMax = 1000.0f;
    TraceRay(rs, 0x0, 0xff, 0, 1, 0, rayDesc, myPayload);
  }

Intersection Stage
~~~~~~~~~~~~~~~~~~

| Intersection shader stage is used to implement arbitrary ray-primitive intersections such spheres or axis-aligned bounding boxes (AABB). Triangle primitives do not require a custom intersection shader.
| Entry functions of this stage are annotated with **[shader("intersection")]** in HLSL source.
| Such entry functions must return void and do not accept any arguments.

| For example:

.. code:: hlsl

  struct Attribute
  {
    float2 bary;
  };

  [shader("intersection")]
  void main() {
  Attribute myHitAttribute = { float2(0.0f,0.0f) };
  ReportHit(0.0f, 0U, myHitAttribute);
  }


Closest-Hit Stage
~~~~~~~~~~~~~~~~~

| Hit shaders are invoked when a ray primitive intersection is found. A closest-hit shader
| is invoked for the closest intersection point along a ray and can be used to compute interactions
| at intersection point or spawn secondary rays.
| Entry functions of this stage are annotated with **[shader("closesthit")]** in HLSL source.
| Such entry functions must return void and accept exactly two arguments. First argument must be an inout
| variable of user defined structure type and second argument must be a in variable of user defined structure type.

| For example:

.. code:: hlsl

  struct Attribute
  {
    float2 bary;
  };
  struct Payload {
    float4 color;
  };
  [shader("closesthit")]
  void main(inout Payload a, in Attribute b) {
    a.color = float4(0.0f,1.0f,0.0f,0.0f);
  }

Any-Hit Stage
~~~~~~~~~~~~~~~~~

| Hit shaders are invoked when a ray primitive intersection is found. An any-hit shader
| is invoked for all intersections along a ray with a primitive.
| Entry functions of this stage are annotated with **[shader("anyhit")]** in HLSL source.
| Such entry functions must return void and accept exactly two arguments. First argument must be an inout
| variable of user defined structure type and second argument must be an in variable of user defined structure type.

| For example:

.. code:: hlsl

  struct Attribute
  {
    float2 bary;
  };
  struct Payload {
    float4 color;
  };
  [shader("anyhit")]
  void main(inout Payload a, in Attribute b) {
    a.color = float4(0.0f,1.0f,0.0f,0.0f);
  }

Miss Stage
~~~~~~~~~~

| Miss shaders are invoked when no intersection is found.
| Entry functions of this stage are annotated with **[shader("miss")]** in HLSL source.
| Such entry functions return void and accept exactly one argument. First argument must be an inout variable of user defined structure type.

| For example:

.. code:: hlsl

  struct Payload {
    float4 color;
  };
  [shader("miss")]
  void main(inout Payload a) {
    a.color = float4(0.0f,1.0f,0.0f,0.0f);
  }

Callable Stage
~~~~~~~~~~~~~~

| Callables are generic function calls which can be invoked from either raygeneration, closest-hit,
| miss or callable shader stages.
| Entry functions of this stage are annotated with **[shader("callable")]** in HLSL source.
| Such entry functions must return void and accept exactly one argument. First argument must be an inout
| variable of user defined structure type.

| For example:

.. code:: hlsl

  struct CallData {
    float4 data;
  };
  [shader("callable")]
  void main(inout CallData a) {
    a.color = float4(0.0f,1.0f,0.0f,0.0f);
  }

Mesh and Amplification Shaders
------------------------------

| DirectX adds 2 new shader stages for using MeshShading pipeline namely Mesh and Amplification.
| Amplification shaders corresponds to Task Shaders in Vulkan.
|
| Refer to following HLSL and SPIR-V specs for details:
| https://microsoft.github.io/DirectX-Specs/d3d/MeshShader.html
| https://github.com/KhronosGroup/SPIRV-Registry/blob/main/extensions/NV/SPV_NV_mesh_shader.asciidoc
|
| This section describes how Mesh and Amplification shaders are translated to SPIR-V for Vulkan.

Entry Point Attributes
~~~~~~~~~~~~~~~~~~~~~~
The following HLSL attributes are attached to the main entry point of Mesh and/or Amplification
shaders and are translated to SPIR-V execution modes according to the table below:

.. table:: Mapping from HLSL attribute to SPIR-V execution mode

+-----------------------+--------------------+-------------------------+
|  HLSL Attribute       |   Value            | SPIR-V Execution Mode   |
+=======================+====================+=========================+
|``outputtopology``     | ``point``          | ``OutputPoints``        |
|                       +--------------------+-------------------------+
| (SPV_NV_mesh_shader)  | ``line``           | ``OutputLinesNV``       |
|                       |                    |                         |
|                       +--------------------+-------------------------+
|                       | ``triangle``       | ``OutputTrianglesNV``   |
+-----------------------+--------------------+-------------------------+
|``outputtopology``     | ``point``          | ``OutputPoints``        |
|                       +--------------------+-------------------------+
| (SPV_EXT_mesh_shader) | ``line``           | ``OutputLinesEXT``      |
|                       |                    |                         |
|                       +--------------------+-------------------------+
|                       | ``triangle``       | ``OutputTrianglesEXT``  |
+-----------------------+--------------------+-------------------------+
| ``numthreads``        | ``X, Y, Z``        | ``LocalSize X, Y, Z``   |
|                       |                    |                         |
|                       | ``(X*Y*Z <= 128)`` |                         |
+-----------------------+--------------------+-------------------------+

Intrinsics
~~~~~~~~~~
The following HLSL intrinsics are used in Mesh or Amplification shaders
and are translated to SPIR-V intrinsics according to the table below:

.. table:: Mapping from HLSL intrinsics to SPIR-V intrinsics for SPV_NV_mesh_shader

+---------------------------+--------------------+-----------------------------------------+
|  HLSL Intrinsic           |  Parameters        | SPIR-V Intrinsic                        |
+===========================+====================+=========================================+
| ``SetMeshOutputCounts``   | ``numVertices``    | ``PrimitiveCountNV numPrimitives``      |
|                           |                    |                                         |
| ``(Mesh shader)``         | ``numPrimitives``  |                                         |
+---------------------------+--------------------+-----------------------------------------+
| ``DispatchMesh``          | ``ThreadX``        | ``OpControlBarrier``                    |
|                           |                    |                                         |
| ``(Amplification shader)``| ``ThreadY``        | ``TaskCountNV ThreadX*ThreadY*ThreadZ`` |
|                           |                    |                                         |
|                           | ``ThreadZ``        |                                         |
|                           |                    |                                         |
|                           | ``MeshPayload``    |                                         |
+---------------------------+--------------------+-----------------------------------------+

.. table:: Mapping from HLSL intrinsics to SPIR-V intrinsics for SPV_EXT_mesh_shader

+---------------------------+--------------------+--------------------------------------------------------------+
|  HLSL Intrinsic           |  Parameters        | SPIR-V Intrinsic                                             |
+===========================+====================+==============================================================+
| ``SetMeshOutputCounts``   | ``numVertices``    | ``OpSetMeshOutputsEXT``                                      |
|                           |                    |                                                              |
| ``(Mesh shader)``         | ``numPrimitives``  |                                                              |
+---------------------------+--------------------+--------------------------------------------------------------+
| ``DispatchMesh``          | ``ThreadX``        | ``OpEmitMeshTasksEXT ThreadX ThreadY ThreadZ MeshPayload``   |
|                           |                    |                                                              |
| ``(Amplification shader)``| ``ThreadY``        | ``TaskCountNV ThreadX*ThreadY*ThreadZ``                      |
|                           |                    |                                                              |
|                           | ``ThreadZ``        |                                                              |
|                           |                    |                                                              |
|                           | ``MeshPayload``    |                                                              |
+---------------------------+--------------------+--------------------------------------------------------------+

| Note : For ``DispatchMesh`` intrinsic, we also emit ``MeshPayload`` as output block with ``PerTaskNV`` decoration

Mesh Interface Variables
~~~~~~~~~~~~~~~~~~~~~~~~
| Interface variables are defined for Mesh shaders using HLSL modifiers.
| Following table gives high level overview of the mapping:
|

.. table:: Mapping from HLSL modifiers to SPIR-V definitions

+-----------------+-------------------------------------------------------------------------+
|  HLSL modifier  | SPIR-V definition                                                       |
+=================+=========================================================================+
| ``indices``     | Maps to SPIR-V intrinsic ``PrimitiveIndicesNV``                         |
|                 |                                                                         |
|                 | Defines SPIR-V Execution Mode ``OutputPrimitivesNV <array-size>``       |
+-----------------+-------------------------------------------------------------------------+
| ``vertices``    | Maps to per-vertex out attributes                                       |
|                 |                                                                         |
|                 | Defines existing SPIR-V Execution Mode ``OutputVertices <array-size>``  |
+-----------------+-------------------------------------------------------------------------+
| ``primitives``  | Maps to per-primitive out attributes with ``PerPrimitiveNV`` decoration |
+-----------------+-------------------------------------------------------------------------+
| ``payload``     | Maps to per-task in attributes with ``PerTaskNV`` decoration            |
+-----------------+-------------------------------------------------------------------------+


Raytracing in Vulkan and SPIRV
==============================

| SPIR-V codegen is currently supported for NVIDIA platforms via SPV_NV_ray_tracing extension or
| on other platforms via provisional cross vendor SPV_KHR_ray_tracing extension.
| SPIR-V specification for reference:
| https://github.com/KhronosGroup/SPIRV-Registry/blob/main/extensions/NV/SPV_NV_ray_tracing.asciidoc
| https://github.com/KhronosGroup/SPIRV-Registry/blob/main/extensions/KHR/SPV_KHR_ray_tracing.asciidoc

| Vulkan ray tracing samples:
| https://developer.nvidia.com/rtx/raytracing/vkray


Raytracing Mapping to SPIR-V
----------------------------

Intrinsics
~~~~~~~~~~


| Following table provides mapping for system value intrinsics along with supported shader stages.

============================    ===============================    ====== ============ =========== ======= ======== ========
        HLSL                               SPIR-V                               HLSL Shader Stage
----------------------------    -------------------------------    ---------------------------------------------------------
  System Value Intrinsic               Builtin                     Raygen Intersection Closest Hit Any Hit   Miss   Callable
============================    ===============================    ====== ============ =========== ======= ======== ========
``DispatchRaysIndex()``         ``LaunchId{NV/KHR}``               ✓       ✓             ✓          ✓       ✓       ✓
``DispatchRaysDimensions()``    ``LaunchSize{NV/KHR}``             ✓       ✓             ✓          ✓       ✓       ✓
``WorldRayOrigin()``            ``WorldRayOrigin{NV/KHR}``                 ✓             ✓          ✓       ✓
``WorldRayDirection()``         ``WorldRayDirection{NV/KHR}``              ✓             ✓          ✓       ✓
``RayTMin()``                   ``RayTmin{NV/KHR}``                        ✓             ✓          ✓       ✓
``RayTCurrent()``               ``RayTmax{NV/KHR}``                        ✓             ✓          ✓       ✓
``RayFlags()``                  ``IncomingRayFlags{NV/KHR}``               ✓             ✓          ✓       ✓
``InstanceIndex()``             ``InstanceId``                             ✓             ✓          ✓
``GeometryIndex()``             ``RayGeometryIndexKHR``                    ✓             ✓          ✓
``InstanceID()``                ``InstanceCustomIndex{NV/KHR}``            ✓             ✓          ✓
``PrimitiveIndex()``            ``PrimitiveId``                            ✓             ✓          ✓
``ObjectRayOrigin()``           ``ObjectRayOrigin{NV/KHR}``                ✓             ✓          ✓
``ObjectRayDirection()``        ``ObjectRayDirection{NV/KHR}``             ✓             ✓          ✓
``ObjectToWorld3x4()``          ``ObjectToWorld{NV/KHR}``                  ✓             ✓          ✓
``ObjectToWorld4x3()``          ``ObjectToWorld{NV/KHR}``                  ✓             ✓          ✓
``WorldToObject3x4()``          ``WorldToObject{NV/KHR}``                  ✓             ✓          ✓
``WorldToObject4x3()``          ``WorldToObject{NV/KHR}``                  ✓             ✓          ✓
``HitKind()``                   ``HitKind{NV/KHR}``                        ✓             ✓          ✓
============================    ===============================    ====== ============ =========== ======= ======== ========

| *There is no separate builtin for transposed matrices ObjectToWorld3x4 and WorldToObject3x4 in SPIR-V hence we internally transpose during translation*
| *GeometryIndex() is only supported under SPV_KHR_ray_tracing extension.*

| Following table provides mapping for other intrinsics along with supported shader stages.


===========================     =================================     ====== ============ =========== ======= ===== ========
        HLSL                               SPIR-V                                 HLSL Shader Stage
---------------------------     ---------------------------------     ------------------------------------------------------
   Intrinsic                              Opcode                      Raygen Intersection Closest Hit Any Hit  Miss Callable
===========================     =================================     ====== ============ =========== ======= ===== ========
``TraceRay``                    ``OpTrace{NV/KHR}``                     ✓                    ✓                    ✓
``ReportHit``                   ``OpReportIntersection{NV/KHR}``        ✓         ✓
``IgnoreHit``                   ``OpIgnoreIntersection{NV/KHR}``        ✓                             ✓
``AcceptHitAndEndSearch``       ``OpTerminateRay{NV/KHR}``              ✓                             ✓
``CallShader``                  ``OpExecuteCallable{NV/KHR}``           ✓                    ✓             ✓     ✓
===========================     =================================     ====== ============ =========== ======= ===== ========


Resource Types
~~~~~~~~~~~~~~

| Following table provides mapping for new resource types supported in all raytracing shaders.


===================================     =======================================
        HLSL Type                                   SPIR-V Opcode
-----------------------------------     ---------------------------------------
``RaytracingAccelerationStructure``     ``OpTypeAccelerationStructure{NV/KHR}``
===================================     =======================================

Interface Variables
~~~~~~~~~~~~~~~~~~~

| Interface variables are created for various ray tracing storage classes based on intrinsic/shader stage
| Following table gives high level overview of the mapping.


=================================       ===========================================================
   SPIR-V Storage Class                        Created For
---------------------------------       -----------------------------------------------------------
``RayPayload{NV/KHR}``                  Last argument to TraceRay
``IncomingRayPayload{NV/KHR}``          First argument of entry for AnyHit/ClosestHit & Miss stage
``HitAttribute{NV/KHR}``                Last argument to ReportHit
``CallableData{NV/KHR}``                Last argument to CallShader
``IncomingCallableData{NV/KHR}``        First argument of entry for Callable stage
=================================       ===========================================================

RayQuery
--------

Ray Query is subfeature of the DirectX ray tracing and belongs to the DirectX ray tracing spec 1.1 (DXR 1.1).
DirectX add RayQuery object type and its member TraceRayInline() to do the TraceRay() that doesn't
use any seperate ray-tracing shader stages.
Shaders can instantiate RayQuery objects as local variables, the RayQuery object acts as a state
machine for ray query. The shader interacts with the RayQuery object's methods to advance the
query through an acceleration structure and query traversal information

Refer to following pages for details:
https://microsoft.github.io/DirectX-Specs/d3d/Raytracing.html

A flow chart for a simple ray query process

::

          +------------------------------+
          |   RayQuery<RAY_FLAG_NONE> q  |
          +------------------------------+
                         |
                         V
          +------------------------------+
          |      q.TraceRayInline()      |
          +------------------------------+
                  |               — — — — — — — — — — — — —
                  |              |                         |
                  |              |              +------------------------+
                  |              |              | Your intersection code |
                  |              |              +------------------------+
                  |              |                         ^
                  V              V                         |
          +------------------------------+      +---------------------+
          |  q.Proceed() // AS traversal |      |  q.CandidateType()  |
          +------------------------------+      +---------------------+
               |                   |                       ^
           No  |                   | Yes                   |
               |                   |_ _ _ _ _ _ _ _ _ _ _ _|
               V
         +------------------------------+
         |     q.CommittedStatus()      |
         +------------------------------+
                       |
                       V
        +----------------------------------+
        | Your Intersection/shader code    |
        +----------------------------------+


Example:

.. code:: hlsl

  void main() {
    RayQuery<RAY_FLAG_CULL_NON_OPAQUE | RAY_FLAG_ACCEPT_FIRST_HIT_AND_END_SEARCH> q;
    q.TraceRayInline(myAccelerationStructure, 0 , 0xff, myRay);

    // Proceed() is AccelerationStructure traversal loop take places
    while(q.Proceed()) {
      switch(q.CandidateType()) {
        // retrieve intersection information/Do the shadering
      }
    }

    // AccelerationStructure traversal end
    // Get the Committed status
    switch(q.CommittedStatus()) {
      // retrieve intersection information/ Do the shadering
    }
  }

Ray Query in SPIRV
~~~~~~~~~~~~~~~~~~
RayQuery SPIR-V codegen is currently supported via SPV_KHR_ray_query extension
SPIR-V specification for reference:
https://github.com/KhronosGroup/SPIRV-Registry/blob/main/extensions/KHR/SPV_KHR_ray_query.asciidoc

Object Type
~~~~~~~~~~~
RayQuery<RAY_FLAGS>

RayQuery represents the state of an inline ray tracing call into an acceleration structure.


============ ================================
 HLSL Type            SPIR-V Opcode
------------ --------------------------------
``RayQuery`` ``OpTypeRayQueryKHR``
============ ================================

RayQuery Mapping to SPIR-V
~~~~~~~~~~~~~~~~~~~~~~~~~~

+---------------------------------------------------+-------------------------------------------------------------------------+
|      HLSL  RayQuery member Intrinsic              |             SPIR-V Opcode                                               |
+===================================================+=========================================================================+
|``.Abort``                                         | ``OpRayQueryTerminateKHR``                                              |
+---------------------------------------------------+-------------------------------------------------------------------------+
|``.CandidateType``                                 | ``OpRayQueryGetIntersectionTypeKHR``                                    |
+---------------------------------------------------+-------------------------------------------------------------------------+
|``.CandidateProceduralPrimitiveNonOpaque``         | ``OpRayQueryGetIntersectionCandidateAABBOpaqueKHR``                     |
+---------------------------------------------------+-------------------------------------------------------------------------+
|``.CandidateInstanceIndex``                        | ``OpRayQueryGetIntersectionInstanceIdKHR``                              |
+---------------------------------------------------+-------------------------------------------------------------------------+
|``.CandidateInstanceID``                           | ``OpRayQueryGetIntersectionInstanceCustomIndexKHR``                     |
+---------------------------------------------------+-------------------------------------------------------------------------+
| ``.CandidateInstanceContributionToHitGroupIndex`` | ``OpRayQueryGetIntersectionInstanceShaderBindingTableRecordOffsetKHR``  |
+---------------------------------------------------+-------------------------------------------------------------------------+
|``.CandidateGeometryIndex``                        | ``OpRayQueryGetIntersectionGeometryIndexKHR``                           |
+---------------------------------------------------+-------------------------------------------------------------------------+
|``.CandidatePrimitiveIndex``                       | ``OpRayQueryGetIntersectionPrimitiveIndexKHR``                          |
+---------------------------------------------------+-------------------------------------------------------------------------+
|``.CandidateObjectRayOrigin``                      | ``OpRayQueryGetIntersectionObjectRayOriginKHR``                         |
+---------------------------------------------------+-------------------------------------------------------------------------+
|``.CandidateObjectRayDirection``                   | ``OpRayQueryGetIntersectionObjectRayDirectionKHR``                      |
+---------------------------------------------------+-------------------------------------------------------------------------+
|``.CandidateObjectToWorld3x4``                     | ``OpRayQueryGetIntersectionObjectToWorldKHR``                           |
+---------------------------------------------------+-------------------------------------------------------------------------+
|``.CandidateObjectToWorld4x3``                     | ``OpRayQueryGetIntersectionObjectToWorldKHR``                           |
+---------------------------------------------------+-------------------------------------------------------------------------+
|``.CandidateWorldToObject3x4``                     | ``OpRayQueryGetIntersectionWorldToObjectKHR``                           |
+---------------------------------------------------+-------------------------------------------------------------------------+
|``.CandidateWorldToObject4x3``                     | ``OpRayQueryGetIntersectionWorldToObjectKHR``                           |
+---------------------------------------------------+-------------------------------------------------------------------------+
|``.CandidateTriangleBarycentrics``                 | ``OpRayQueryGetIntersectionBarycentricsKHR``                            |
+---------------------------------------------------+-------------------------------------------------------------------------+
|``.CandidateTriangleFrontFace``                    | ``OpRayQueryGetIntersectionFrontFaceKHR``                               |
+---------------------------------------------------+-------------------------------------------------------------------------+
|``.CommittedStatus``                               | ``OpRayQueryGetIntersectionTypeKHR``                                    |
+---------------------------------------------------+-------------------------------------------------------------------------+
|``.CommittedInstanceIndex``                        | ``OpRayQueryGetIntersectionInstanceIdKHR``                              |
+---------------------------------------------------+-------------------------------------------------------------------------+
|``.CommittedInstanceID``                           | ``OpRayQueryGetIntersectionInstanceCustomIndexKHR``                     |
+---------------------------------------------------+-------------------------------------------------------------------------+
| ``.CommittedInstanceContributionToHitGroupIndex`` |  ``OpRayQueryGetIntersectionInstanceShaderBindingTableRecordOffsetKHR`` |
+---------------------------------------------------+-------------------------------------------------------------------------+
|``.CommittedGeometryIndex``                        | ``OpRayQueryGetIntersectionGeometryIndexKHR``                           |
+---------------------------------------------------+-------------------------------------------------------------------------+
|``.CommittedPrimitiveIndex``                       | ``OpRayQueryGetIntersectionPrimitiveIndexKHR``                          |
+---------------------------------------------------+-------------------------------------------------------------------------+
|``.CommittedRayT``                                 | ``OpRayQueryGetIntersectionTKHR``                                       |
+---------------------------------------------------+-------------------------------------------------------------------------+
|``.CommittedObjectRayOrigin``                      | ``OpRayQueryGetIntersectionObjectRayOriginKHR``                         |
+---------------------------------------------------+-------------------------------------------------------------------------+
|``.CommittedObjectRayDirection``                   | ``OpRayQueryGetIntersectionObjectRayDirectionKHR``                      |
+---------------------------------------------------+-------------------------------------------------------------------------+
|``.CommittedObjectToWorld3x4``                     | ``OpRayQueryGetIntersectionObjectToWorldKHR``                           |
+---------------------------------------------------+-------------------------------------------------------------------------+
|``.CommittedObjectToWorld4x3``                     | ``OpRayQueryGetIntersectionObjectToWorldKHR``                           |
+---------------------------------------------------+-------------------------------------------------------------------------+
|``.CommittedWorldToObject3x4``                     | ``OpRayQueryGetIntersectionWorldToObjectKHR``                           |
+---------------------------------------------------+-------------------------------------------------------------------------+
|``.CommittedWorldToObject4x3``                     | ``OpRayQueryGetIntersectionWorldToObjectKHR``                           |
+---------------------------------------------------+-------------------------------------------------------------------------+
|``.CommittedTriangleBarycentrics``                 | ``OpRayQueryGetIntersectionBarycentricsKHR``                            |
+---------------------------------------------------+-------------------------------------------------------------------------+
|``.CommittedTriangleFrontFace``                    | ``OpRayQueryGetIntersectionFrontFaceKHR``                               |
+---------------------------------------------------+-------------------------------------------------------------------------+
|``.CommitNonOpaqueTriangleHit``                    | ``OpRayQueryConfirmIntersectionKHR``                                    |
+---------------------------------------------------+-------------------------------------------------------------------------+
|``.CommitProceduralPrimitiveHit``                  | ``OpRayQueryGenerateIntersectionKHR``                                   |
+---------------------------------------------------+-------------------------------------------------------------------------+
|``.Proceed``                                       | ``OpRayQueryProceedKHR``                                                |
+---------------------------------------------------+-------------------------------------------------------------------------+
|``.RayFlags``                                      | ``OpRayQueryGetRayFlagsKHR``                                            |
+---------------------------------------------------+-------------------------------------------------------------------------+
|``.RayTMin``                                       | ``OpRayQueryGetRayTMinKHR``                                             |
+---------------------------------------------------+-------------------------------------------------------------------------+
|``.TraceRayInline``                                | ``OpRayQueryInitializeKHR``                                             |
+---------------------------------------------------+-------------------------------------------------------------------------+
|``.WorldRayDirection``                             | ``OpRayQueryGetWorldRayDirectionKHR``                                   |
+---------------------------------------------------+-------------------------------------------------------------------------+
|``.WorldRayOrigin``                                | ``OpRayQueryGetWorldRayOriginKHR``                                      |
+---------------------------------------------------+-------------------------------------------------------------------------+

Shader Model 6.0+ Wave Intrinsics
=================================


Note that Wave intrinsics requires SPIR-V 1.3, which is supported by Vulkan 1.1.
If you use wave intrinsics in your source code, you will need to specify
-fspv-target-env=vulkan1.1 via the command line to target Vulkan 1.1.

Shader model 6.0 introduces a set of wave operations. Apart from
``WaveGetLaneCount()`` and ``WaveGetLaneIndex()``, which are translated into
loading from SPIR-V builtin variable ``SubgroupSize`` and
``SubgroupLocalInvocationId`` respectively, the rest are translated into SPIR-V
group operations with ``Subgroup`` scope according to the following chart:

============= ============================ =================================== ==============================
Wave Category       Wave Intrinsics               SPIR-V Opcode                SPIR-V Group Operation
============= ============================ =================================== ==============================
Query         ``WaveIsFirstLane()``        ``OpGroupNonUniformElect``
Vote          ``WaveActiveAnyTrue()``      ``OpGroupNonUniformAny``
Vote          ``WaveActiveAllTrue()``      ``OpGroupNonUniformAll``
Vote          ``WaveActiveBallot()``       ``OpGroupNonUniformBallot``
Reduction     ``WaveActiveAllEqual()``     ``OpGroupNonUniformAllEqual``       ``Reduction``
Reduction     ``WaveActiveCountBits()``    ``OpGroupNonUniformBallotBitCount`` ``Reduction``
Reduction     ``WaveActiveSum()``          ``OpGroupNonUniform*Add``           ``Reduction``
Reduction     ``WaveActiveProduct()``      ``OpGroupNonUniform*Mul``           ``Reduction``
Reduction     ``WaveActiveBitAdd()``       ``OpGroupNonUniformBitwiseAnd``     ``Reduction``
Reduction     ``WaveActiveBitOr()``        ``OpGroupNonUniformBitwiseOr``      ``Reduction``
Reduction     ``WaveActiveBitXor()``       ``OpGroupNonUniformBitwiseXor``     ``Reduction``
Reduction     ``WaveActiveMin()``          ``OpGroupNonUniform*Min``           ``Reduction``
Reduction     ``WaveActiveMax()``          ``OpGroupNonUniform*Max``           ``Reduction``
Scan/Prefix   ``WavePrefixSum()``          ``OpGroupNonUniform*Add``           ``ExclusiveScan``
Scan/Prefix   ``WavePrefixProduct()``      ``OpGroupNonUniform*Mul``           ``ExclusiveScan``
Scan/Prefix   ``WavePrefixCountBits()``    ``OpGroupNonUniformBallotBitCount`` ``ExclusiveScan``
Broadcast     ``WaveReadLaneAt()``         ``OpGroupNonUniformBroadcast``
Broadcast     ``WaveReadLaneFirst()``      ``OpGroupNonUniformBroadcastFirst``
Quad          ``QuadReadAcrossX()``        ``OpGroupNonUniformQuadSwap``
Quad          ``QuadReadAcrossY()``        ``OpGroupNonUniformQuadSwap``
Quad          ``QuadReadAcrossDiagonal()`` ``OpGroupNonUniformQuadSwap``
Quad          ``QuadReadLaneAt()``         ``OpGroupNonUniformQuadBroadcast``
Quad          ``QuadAny()``                ``OpGroupNonUniformQuadAnyKHR``
Quad          ``QuadAll()``                ``OpGroupNonUniformQuadAllKHR``
N/A           ``WaveMatch()``              ``OpGroupNonUniformPartitionNV``
Multiprefix   ``WaveMultiPrefixSum()``     ``OpGroupNonUniform*Add``           ``PartitionedExclusiveScanNV``
Multiprefix   ``WaveMultiPrefixProduct()`` ``OpGroupNonUniform*Mul``           ``PartitionedExclusiveScanNV``
Multiprefix   ``WaveMultiPrefixBitAnd()``  ``OpGroupNonUniformLogicalAnd``     ``PartitionedExclusiveScanNV``
Multiprefix   ``WaveMultiPrefixBitOr()``   ``OpGroupNonUniformLogicalOr``      ``PartitionedExclusiveScanNV``
Multiprefix   ``WaveMultiPrefixBitXor()``  ``OpGroupNonUniformLogicalXor``     ``PartitionedExclusiveScanNV``
============= ============================ =================================== ==============================

``QuadAny`` and ``QuadAll`` will use the ``OpGroupNonUniformQuadAnyKHR`` and
``OpGroupNonUniformQuadAllKHR`` instructions if the ``SPV_KHR_quad_control``
extension is enabled. If it is not, they will fall back to constructing the
value using multiple calls to ``OpGroupNonUniformQuadBroadcast``.

Partitioned wave operations
~~~~~~~~~~~~~~~~~~~~~~~~~~~

``WaveMatch()`` partitions the wave into groups of lanes that hold the same
value and returns the bitmasks of those groups; the ``WaveMultiPrefixSum()``,
``WaveMultiPrefixProduct()``, ``WaveMultiPrefixBitAnd()``,
``WaveMultiPrefixBitOr()`` and ``WaveMultiPrefixBitXor()`` intrinsics take such a
mask back and evaluate an exclusive scan restricted to the lanes it selects.
``WaveMatch()`` becomes ``OpGroupNonUniformPartitionEXT`` and each
``WaveMultiPrefix*()`` becomes an ``OpGroupNonUniform*`` with the
``PartitionedExclusiveScanEXT`` group operation.

That functionality is specified twice:

* ``SPV_NV_shader_subgroup_partitioned`` -- the original NVIDIA spelling. It is
  what DXC has always emitted and it is still what DXC emits by default.
* ``SPV_EXT_shader_subgroup_partitioned`` -- the standardised spelling. It is
  selected with ``-fspv-extension=SPV_EXT_shader_subgroup_partitioned``.

The two extensions are two names for one capability:
``GroupNonUniformPartitionedEXT`` and ``GroupNonUniformPartitionedNV`` are both
SPIR-V capability 5297, and ``OpGroupNonUniformPartitionEXT`` (5296) and
``OpGroupNonUniformPartitionNV`` are the same opcode. The instruction stream
therefore does not depend on the selection at all -- the differences are the
string in ``OpExtension`` and the fact that a module must declare at most one of
the two. Because the capability id is shared, a disassembler prints the
canonical EXT spelling (``OpCapability GroupNonUniformPartitionedEXT``,
``OpGroupNonUniformPartitionEXT``, ``PartitionedExclusiveScanEXT``) for a module
that declares either extension, so only ``OpExtension`` distinguishes them.

Selection rules (``FeatureManager::getShaderSubgroupPartitionedProvider``):

* No ``-fspv-extension`` option: only ``SPV_NV_shader_subgroup_partitioned`` is
  enabled, so the generated module is unchanged from previous releases.
* ``-fspv-extension=SPV_EXT_shader_subgroup_partitioned``: the module declares
  ``OpExtension "SPV_EXT_shader_subgroup_partitioned"`` and not the NV string.
  Note that ``-fspv-extension`` is a whitelist: this also disables every
  extension that is otherwise enabled by default, so list the ones the shader
  needs explicitly.
* ``-fspv-extension=SPV_NV_shader_subgroup_partitioned``: keeps the NV string,
  for drivers and tools that only know the NV name.
* If both are listed, the standardised EXT spelling is emitted.

The partitioned operations require SPIR-V 1.3, hence Vulkan 1.1 or a later
``-fspv-target-env``; without one DXC reports ``Vulkan 1.1 is required for Wave
Operation but not permitted to use``. When an explicit ``-fspv-extension`` list
names neither spelling, ``WaveMatch()`` and the ``WaveMultiPrefix*()`` intrinsics
are compile errors: the alternative would be a module that contains
``OpGroupNonUniformPartitionEXT`` while no declared extension provides the
capability, which the validator rejects.

A host must enable ``VK_EXT_shader_subgroup_partitioned`` and its
``shaderSubgroupPartitioned`` feature, or ``VK_NV_shader_subgroup_partitioned``
for the NV spelling; the compiler cannot check either.

The Implicit ``vk`` Namespace
=============================

Overview
--------
We have introduced an implicit namepace (called ``vk``) that will be home to all
Vulkan-specific functions, enums, etc. Given the similarity between HLSL and
C++, developers are likely familiar with namespaces -- and implicit namespaces
(e.g. ``std::`` in C++). The ``vk`` namespace provides an interface for expressing
Vulkan-specific features (core spec and KHR extensions).

**The compiler will generate the proper error message (** ``unknown 'vk' identifier`` **)
if** ``vk::`` **is used for compiling to DXIL.**

Any intrinsic function or enum in the vk namespace will be deprecated if an
equivalent one is added to the default namepsace.

Current Features
----------------
The following intrinsic functions and constants are currently defined in the
implicit ``vk`` namepsace.

.. code:: hlsl

  // Implicitly defined when compiling to SPIR-V.
  namespace vk {

    const uint CrossDeviceScope = 0;
    const uint DeviceScope      = 1;
    const uint WorkgroupScope   = 2;
    const uint SubgroupScope    = 3;
    const uint InvocationScope  = 4;
    const uint QueueFamilyScope = 5;

    uint64_t ReadClock(in uint scope);
    T        RawBufferLoad<T = uint>(in uint64_t deviceAddress,
                                     in uint alignment = 4);
  } // end namespace


Intrinsic Constants
-------------------
The following constants are currently defined:

========================  ============================================
  Constant                value   (SPIR-V constant equivalent, if any)
========================  ============================================
``vk::CrossDeviceScope``    ``0`` (``CrossDevice``)
``vk::DeviceScope``         ``1`` (``Device``)
``vk::WorkgroupScope``      ``2`` (``Workgroup``)
``vk::SubgroupScope``       ``3`` (``Subgroup``)
``vk::InvocationScope``     ``4`` (``Invocation``)
``vk::QueueFamilyScope``    ``5`` (``QueueFamily``)
========================  ============================================

Intrinsic Functions
-------------------

ReadClock
~~~~~~~~~
This intrinsic funcion has the following signature:

.. code:: hlsl

  uint64_t ReadClock(in uint scope);

It translates to performing ``OpReadClockKHR`` defined in `VK_KHR_shader_clock <https://registry.khronos.org/vulkan/specs/latest/man/html/VK_KHR_shader_clock.html>`_.
One can use the predefined scopes in the ``vk`` namepsace to specify the scope argument.
For example:

.. code:: hlsl

  uint64_t clock = vk::ReadClock(vk::SubgroupScope);

RawBufferLoad and RawBufferStore
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
The Vulkan extension `VK_KHR_buffer_device_address <https://registry.khronos.org/vulkan/specs/latest/man/html/VK_KHR_buffer_device_address.html>`_
supports getting the 64-bit address of a buffer and passing it to SPIR-V as a
Uniform buffer. SPIR-V can use the address to load and store data without a descriptor.
We add the following intrinsic functions to expose a subset of the
`VK_KHR_buffer_device_address <https://registry.khronos.org/vulkan/specs/latest/man/html/VK_KHR_buffer_device_address.html>`_
and `SPV_KHR_physical_storage_buffer <https://github.com/KhronosGroup/SPIRV-Registry/blob/main/extensions/KHR/SPV_KHR_physical_storage_buffer.asciidoc>`_
functionality to HLSL:

.. code:: hlsl

  // RawBufferLoad and RawBufferStore use 'uint' for the default template argument.
  // The default alignment is 4. Note that 'alignment' must be a constant integer.
  T RawBufferLoad<T = uint>(in uint64_t deviceAddress, in uint alignment = 4);
  void RawBufferStore<T = uint>(in uint64_t deviceAddress, in T value, in uint alignment = 4);


These intrinsics allow the shader program to load and store a single value with type T (int, float2, struct, etc...)
from GPU accessible memory at given address, similar to ``ByteAddressBuffer.Load()``.
Additionally, these intrinsics allow users to set the memory alignment for the underlying data.
We assume a 'uint' type when the template argument is missing, and we use a value of '4' for the default alignment.
Note that the alignment argument must be a constant integer if it is given.

Though we do support setting the `alignment` of the data load and store, we do not currently
support setting the memory layout for the data. Since these intrinsics are supposed to load
"arbitrary" data to or from a random device address, we assume that the program loads/stores some "bytes of data",
but that its format or layout is unknown. Therefore, keep in mind that these intrinsics
load or store ``sizeof(T)`` bytes of data, and that loading/storing data with a struct
with a custom memory alignment may yield undefined behavior due to the missing custom memory layout support.
Loading data with customized memory layouts is future work.

Using either of these intrinsics adds ``PhysicalStorageBufferAddresses`` capability and
``SPV_KHR_physical_storage_buffer`` extension requirements as well as changing
the addressing model to ``PhysicalStorageBuffer64``.

Example:

.. code:: hlsl

  uint64_t address;
  [numthreads(32, 1, 1)]
  void main(uint3 tid : SV_DispatchThreadID) {
    double foo = vk::RawBufferLoad<double>(address, 8);
    uint bar = vk::RawBufferLoad(address + 8);
    ...
    vk::RawBufferStore<uint>(address + tid.x, bar + tid.x);
  }

Inline SPIR-V (HLSL version of GL_EXT_spirv_intrinsics)
=======================================================

GL_EXT_spirv_intrinsics is an extension of GLSL that allows users to embed
arbitrary SPIR-V instructions in the GLSL code similar to the concept of
inline assembly in the C code. We support the HLSL version of
GL_EXT_spirv_intrinsics. See
`wiki <https://github.com/microsoft/DirectXShaderCompiler/wiki/Inline-SPIR%E2%80%90V>`_
for the details.

Supported Command-line Options
==============================

Command-line options supported by SPIR-V CodeGen are listed below. They are
also recognized by the library API calls.

General options
---------------

- ``-T``: specifies shader profile
- ``-E``: specifies entry point
- ``-D``: Defines macro
- ``-I``: Adds directory to include search path
- ``-O{|0|1|2|3}``: Specifies optimization level
- ``-enable-16bit-types``: enables 16-bit types and disables min precision types
- ``-Zpc``: Packs matrices in column-major order by deafult
- ``-Zpr``: Packs matrices in row-major order by deafult
- ``-Fc``: outputs SPIR-V disassembly to the given file
- ``-Fe``: outputs warnings and errors to the given file
- ``-Fo``: outputs SPIR-V code to the given file
- ``-Fh``: outputs SPIR-V code as a header file
- ``-Vn``: specifies the variable name for SPIR-V code in generated header file
- ``-Zi``: Emits more debug information (see `Debugging`_)
- ``-Cc``: colorizes SPIR-V disassembly
- ``-No``: adds instruction byte offsets to SPIR-V disassembly
- ``-H``:  Shows header includes and nesting depth
- ``-Vi``: Shows details about the include process
- ``-Vd``: Disables SPIR-V verification
- ``-WX``: Treats warnings as errors
- ``-no-warnings``: Suppresses all warnings
- ``-flegacy-macro-expansion``: expands the operands before performing
  token-pasting operation (fxc behavior)

Vulkan-specific options
-----------------------

The following command line options are added into ``dxc`` to support SPIR-V
codegen for Vulkan:

- ``-spirv``: Generates SPIR-V code.
- ``-fvk-b-shift N M``: Shifts by ``N`` the inferred binding numbers for all
  resources in b-type registers of space ``M``. Specifically, for a resouce
  attached with ``:register(bX, spaceM)`` but not ``[vk::binding(...)]``,
  sets its Vulkan descriptor set to ``M`` and binding number to ``X + N``. If
  you need to shift the inferred binding numbers for more than one space,
  provide more than one such option. If more than one such option is provided
  for the same space, the last one takes effect. If you need to shift the
  inferred binding numbers for all sets, use ``all`` as ``M``.
  See `HLSL register and Vulkan binding`_ for explanation and examples.
- ``-fvk-t-shift N M``, similar to ``-fvk-b-shift``, but for t-type registers.
- ``-fvk-s-shift N M``, similar to ``-fvk-b-shift``, but for s-type registers.
- ``-fvk-u-shift N M``, similar to ``-fvk-b-shift``, but for u-type registers.
- ``-fvk-auto-shift-bindings``: Automatically detects the register type for
  resources that are missing the ``:register`` assignment, so the above shifts
  can be applied to them if needed.
- ``-fvk-bind-register xX Y N M`` (short alias: ``-vkbr``): Binds the resouce
  at ``register(xX, spaceY)`` to descriptor set ``M`` and binding ``N``. This
  option cannot be used together with other binding assignment options.
  It requires all source code resources have ``:register()`` attribute and
  all registers have corresponding Vulkan descriptors specified using this
  option. If the ``$Globals`` cbuffer resource is used, it must also be bound
  with ``-fvk-bind-globals``.
- ``-fvk-bind-globals N M``: Places the ``$Globals`` cbuffer at
  descriptor set #M and binding #N. See `HLSL global variables and Vulkan binding`_
  for explanation and examples.
- ``-fvk-use-gl-layout``: Uses strict OpenGL ``std140``/``std430``
  layout rules for resources.
- ``-fvk-use-dx-layout``: Uses DirectX layout rules for resources.
- ``-fvk-invert-y``: Negates (additively inverts) SV_Position.y before writing
  to stage output. Used to accommodate the difference between Vulkan's
  coordinate system and DirectX's. Only allowed in VS/DS/GS/MS/Lib.
- ``-fvk-use-dx-position-w``: Reciprocates (multiplicatively inverts)
  SV_Position.w after reading from stage input. Used to accommodate the
  difference between Vulkan DirectX: the w component of SV_Position in PS is
  stored as 1/w in Vulkan. Only recognized in PS; applying to other stages
  is no-op.
- ``-fvk-stage-io-order={alpha|decl}``: Assigns the stage input/output variable
  location number according to alphabetical order or declaration order. See
  `HLSL semantic and Vulkan Location`_ for more details.
- ``-fspv-reflect``: Emits additional SPIR-V instructions to aid reflection.
- ``-fspv-debug=<category>``: Controls what category of debug information
  should be emitted. Accepted values are ``file``, ``source``, ``line``, and
  ``tool``. See `Debugging`_ for more details.
- ``-fspv-extension=<extension>``: Only allows using ``<extension>`` in CodeGen.
  If you want to allow multiple extensions, provide more than one such option. If you
  want to allow *all* KHR extensions, use ``-fspv-extension=KHR``.
- ``-fspv-target-env=<env>``: Specifies the target environment for this compilation.
  The current valid options are ``vulkan1.0`` and ``vulkan1.1``. If no target
  environment is provided, ``vulkan1.0`` is used as default.
- ``-fspv-flatten-resource-arrays``: Flattens arrays of textures and samplers
  into individual resources, each taking one binding number. For example, an
  array of 3 textures will become 3 texture resources taking 3 binding numbers.
  This makes the behavior similar to DX. Without this option, you would get 1
  array object taking 1 binding number. Note that arrays of
  {RW|Append|Consume}StructuredBuffers are currently not supported in the
  SPIR-V backend. Also note that this requires the optimizer to be able to
  resolve all array accesses with constant indeces. Therefore, all loops using
  the resource arrays must be marked with ``[unroll]``.
- ``-fspv-entrypoint-name=<name>``: Specify the SPIR-V entry point name. Defaults
  to the HLSL entry point name.
- ``-fspv-use-legacy-buffer-matrix-order``: Assumes the legacy matrix order (row
  major) when accessing raw buffers (e.g., ByteAdddressBuffer).
- ``-fspv-preserve-interface``: Preserves all interface variables in the entry
  point, even when those variables are unused.
- ``-Wno-vk-ignored-features``: Does not emit warnings on ignored features
  resulting from no Vulkan support, e.g., cbuffer member initializer.

Unsupported HLSL Features
=========================

The following HLSL language features are not supported in SPIR-V codegen,
either because of no Vulkan equivalents at the moment, or because of deprecation.

* Literal/immediate sampler state: deprecated feature. The compiler will
  emit a warning and ignore it.
* ``abort()`` intrinsic function: no Vulkan equivalent. The compiler will emit
  an error.
* ``GetRenderTargetSampleCount()`` intrinsic function: no Vulkan equivalent.
  (Its GLSL counterpart is ``gl_NumSamples``, which is not available in GLSL for
  Vulkan.) The compiler will emit an error.
* ``GetRenderTargetSamplePosition()`` intrinsic function: no Vulkan equivalent.
  (``gl_SamplePosition`` provides similar functionality but it's only for the
  sample currently being processed.) The compiler will emit an error.
* ``tex*()`` intrinsic functions: deprecated features. The compiler will
  emit errors.
* ``.GatherCmpGreen()``, ``.GatherCmpBlue()``, ``.GatherCmpAlpha()`` intrinsic
  method: no Vulkan equivalent. (SPIR-V ``OpImageDrefGather`` instruction does
  not take component as input.) The compiler will emit an error.
* Since ``StructuredBuffer``, ``RWStructuredBuffer``, ``ByteAddressBuffer``, and
  ``RWByteAddressBuffer`` are not represented as image types in SPIR-V, using the
  output unsigned integer ``status`` argument in their ``Load*`` methods is not
  supported. Using these methods with the ``status`` argument will cause a compiler error.
* Applying ``row_major`` or ``column_major`` attributes to a stand-alone matrix will be
  ignored by the compiler because ``RowMajor`` and ``ColMajor`` decorations in SPIR-V are
  only allowed to be applied to members of structures. A warning will be issued by the compiler.
* The Hull shader ``partitioning`` attribute may not have the ``pow2`` value. The compiler
  will emit an error. Other attribute values are supported and described in the
  `Hull Entry Point Attributes`_ section.
* ``cbuffer``/``tbuffer`` member initializer: no Vulkan equivalent. The compiler
  will emit an warning and ignore it.

Appendix
==========

Appendix A. Matrix Representation
---------------------------------
Consider a matrix in HLSL defined as ``float2x3 m;``. Conceptually, this is a matrix with 2 rows and 3 columns.
This means that you can access its elements via expressions such as ``m[i][j]``, where ``i`` can be ``{0, 1}`` and ``j`` can be ``{0, 1, 2}``.

Now let's look how matrices are defined in SPIR-V:

.. code:: spirv

  %columnType = OpTypeVector %float      <number of rows>
     %matType = OpTypeMatrix %columnType <number of columns>

As you can see, SPIR-V conceptually represents matrices as a collection of vectors where each vector is a *column*.

Now, let's represent our float2x3 matrix in SPIR-V. If we choose a naive translation (3 columns, each of which is a vector of size 2), we get:

.. code:: spirv

      %v2float = OpTypeVector %float 2
  %mat3v2float = OpTypeMatrix %v2float 3

Now, let's use this naive translation to access into the matrix (e.g. ``m[0][2]``). This is evaluated by first finding ``n = m[0]``, and then finding ``n[2]``.
Notice that in HLSL, ``m[0]`` represents a row, which is a vector of size 3. But accessing the first dimension of the SPIR-V matrix give us
the first column which is a vector of size 2.

.. code:: spirv

  ; n is a vector of size 2
  %n = OpAccessChain %v2float %m %int_0

Notice that in HLSL access ``m[i][j]``, ``i`` can be ``{0, 1}`` and ``j`` can be ``{0, 1, 2}``.
But in SPIR-V OpAccessChain access, the first index (``i``) can be ``{0, 1, 2}`` and the second index (``j``) can be ``{1, 0}``.
Therefore, the naive translation does not work well with indexing.

As a result, we must translate a given HLSL float2x3 matrix (with 2 rows and 3 columns) as a SPIR-V matrix with 3 rows and 2 columns:

.. code:: spirv

      %v3float = OpTypeVector %float 3
  %mat2v3float = OpTypeMatrix %v3float 2

This way, all accesses into the matrix can be naturally handled correctly.

Packing
~~~~~~~
The HLSL ``row_major`` and ``column_major`` type modifiers change the way packing is done.
The following table provides an example which should make our translation more clear:

+------------------+---------------------------+---------------------------+-----------------------------+-------------------+
| Host CPU Data    | HLSL Variable             | GPU (HLSL Representation) | GPU (SPIR-V Representation) | SPIR-V Decoration |
+==================+===========================+===========================+=============================+===================+
|``{1,2,3,4,5,6}`` |          ``float2x3``     |  ``[1 3 5]``              |  ``[1 2]``                  |                   |
|                  |                           |                           |                             |                   |
|                  |                           |  ``[2 4 6]``              |  ``[3 4]``                  |  ``RowMajor``     |
|                  |                           |                           |                             |                   |
|                  |                           |                           |  ``[5 6]``                  |                   |
+------------------+---------------------------+---------------------------+-----------------------------+-------------------+
|``{1,2,3,4,5,6}`` | ``column_major float2x3`` |  ``[1 3 5]``              |  ``[1 2]``                  |                   |
|                  |                           |                           |                             |                   |
|                  |                           |  ``[2 4 6]``              |  ``[3 4]``                  | ``RowMajor``      |
|                  |                           |                           |                             |                   |
|                  |                           |                           |  ``[5 6]``                  |                   |
+------------------+---------------------------+---------------------------+-----------------------------+-------------------+
|``{1,2,3,4,5,6}`` |    ``row_major float2x3`` |  ``[1 2 3]``              |  ``[1 4]``                  |                   |
|                  |                           |                           |                             |                   |
|                  |                           |  ``[4 5 6]``              |  ``[2 5]``                  | ``ColMajor``      |
|                  |                           |                           |                             |                   |
|                  |                           |                           |  ``[3 6]``                  |                   |
+------------------+---------------------------+---------------------------+-----------------------------+-------------------+
