// RUN: %dxc -T cs_6_0 -E main -spirv -HV 2021 -fspv-target-env=vulkan1.3 %s

// VK_EXT_shader_float8 (SPV_EXT_float8).
//
// Two 8-bit floating point formats, each stored in one byte:
//
//   float8_e4m3_t - 1 sign bit, 4 exponent bits (bias 7), 3 mantissa bits.
//                   Normal range 2^-6 (0.015625) .. 448, subnormals down to
//                   2^-9 (0.001953125). No infinity; the single NaN pattern is
//                   0x7F/0xFF, and values above 448 saturate to 448. Roughly
//                   three significant decimal digits of precision, so it is the
//                   format for weights and activations whose scale is known.
//   float8_e5m2_t - 1 sign bit, 5 exponent bits (bias 15), 2 mantissa bits.
//                   Normal range 2^-14 .. 57344, subnormals down to 2^-16, and
//                   it does have infinities and NaNs like IEEE. Two significant
//                   decimal digits, but the exponent range of half - the format
//                   for gradients, where range matters more than precision.
//
// HLSL surface: float8_e4m3_t and float8_e5m2_t, real builtin types
// (float8_e4m3_t2 .. float8_e4m3_t4, float8_e4m3_t2x2, structs and arrays of
// them). They are SPIR-V only, they need HLSL 2018 or later, and they do not need
// -enable-16bit-types: the type is always 8 bits wide.
//
// The extension defines no arithmetic, comparison or bitwise operation on the
// types. They are storage and conversion types:
//   * OpTypeFloat 8 with the Float8E4M3EXT / Float8E5M2EXT encoding operand,
//     declared with OpCapability Float8EXT (4212) and
//     OpExtension "SPV_EXT_float8";
//   * OpFConvert to and from other floating point types, plus the ordinary
//     integer conversions;
//   * storage in buffers and constants.
// A float8 value that has to take part in a computation is converted to float
// first, and the result is converted back when it is stored - which is what the
// shader below does.
//
// The conversion model is widening only: a float8 type converts implicitly to
// float / float64 (scalars, vectors and matrices) and every other conversion -
// narrowing to a float8 type, to or from integer types, to or from
// bfloat16_t / float16_t, and between the two float8 formats - needs an explicit
// constructor. E4M3 and E5M2 never mix implicitly, so a format mix-up is a
// compile error instead of a silent rounding.
//
// VK_EXT_shader_float8 also forbids the Float8E4M3EXT / Float8E5M2EXT encodings
// in the Input and Output storage classes, so a float8 type cannot be a stage
// input or output; pass values between stages as float.
//
// Required from the host:
//   * Vulkan device extension VK_EXT_shader_float8 (add
//     VK_EXT_SHADER_FLOAT8_EXTENSION_NAME at vkCreateDevice),
//   * feature bit VkPhysicalDeviceShaderFloat8FeaturesEXT::shaderFloat8 (query
//     with vkGetPhysicalDeviceFeatures2, chain the struct with the bit set to
//     VK_TRUE into VkDeviceCreateInfo::pNext),
//   * the module declares OpCapability Float8EXT and
//     OpExtension "SPV_EXT_float8".
// A driver without the feature bit rejects a module that declares the
// capability, which is why the compiler cannot paper over the host half.
//
// Cooperative-matrix float8 (OpCapability Float8CooperativeMatrixEXT) is not
// supported by this compiler yet.
//
// See docs/SPIR-V.rst for the full description.

// One float8 block of weights and one float result array. A float8 member keeps
// its one-byte size and one-byte alignment inside a structured buffer, so the
// buffer of float8_e4m3_t has an array stride of 1.
RWStructuredBuffer<float8_e4m3_t> Weights;
RWStructuredBuffer<float8_e5m2_t> Gradients;
RWStructuredBuffer<float> Result;

// A float8 tile as it is stored: 4x4 E4M3 values, 16 bytes in total.
struct Tile {
  float8_e4m3_t v[16];
};

// The values are loaded from the buffer and converted to float for the
// arithmetic, which is the only way SPV_EXT_float8 allows a float8 value to take
// part in a computation: one OpLoad %float8_e4m3 plus one OpFConvert %float per
// element.
float loadE4M3(uint index) {
  return float(Weights[index]);
}

[numthreads(64, 1, 1)]
void main(uint3 id : SV_DispatchThreadID) {
  uint index = id.x;

  // Storage -> register: the load keeps the 8-bit encoded type, the conversion
  // to float is explicit here (the implicit widening form `float f = w;` is
  // equivalent) and lowers to OpFConvert %float.
  float8_e4m3_t w = Weights[index];
  float widened = w;

  // float -> float8 needs an explicit constructor, which lowers to
  // OpFConvert %float8_e4m3. A float8 value that is out of range saturates to
  // the largest finite value of the format (448 for E4M3), it does not become
  // infinite.
  float scaled = widened * 0.5;
  float8_e4m3_t stored = float8_e4m3_t(scaled);

  // The two formats are distinct types: converting E4M3 to E5M2 is an explicit
  // cast and still an OpFConvert, because the encodings differ even though both
  // are 8 bits wide.
  float8_e5m2_t gradient = float8_e5m2_t(w);
  float back = float(gradient);

  // float8 vectors and matrices work like any other element type.
  Tile t;
  for (int i = 0; i < 16; ++i)
    t.v[i] = float8_e4m3_t(back + float(i));

  // The buffer write converts back to the stored format.
  Weights[index] = t.v[index % 16];
  Gradients[index] = gradient;
  Result[index] = widened + back + loadE4M3(index) + float(stored);
}
