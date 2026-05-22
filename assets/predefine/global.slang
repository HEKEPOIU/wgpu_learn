module global;

public struct Transform2D {
  float3x3 view;
  float3x3 projection;
};

[vk_binding(0, 0)]
public ConstantBuffer<Transform2D> transform;

// use dyncamic offset.
[vk_binding(0, 1)]
public StructuredBuffer<float3x3> model;

// not support in wgpu, sad
// [vk_push_constant]
// int objectId;

[ForceInline]
public float3x3 MVP(uint i) {
  return mul(transform.projection, mul(transform.view, model[i]));
}
