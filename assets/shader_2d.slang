struct Transform2D {
  float3x3 model;
  float3x3 view;
  float3x3 projection;
};

[vk_binding(0, 0)]
ConstantBuffer<Transform2D> transform;

struct VertexInput {
  [vk_location(0)]
  float2 position : POSITION;
  // float4 color : COLOR;
};

struct VertexOutput {
  float4 position : SV_Position;
  // float4 color : COLOR;
};

[shader("vertex")]
VertexOutput vs_main(VertexInput input) {
  VertexOutput output;
  float3 clipPos =
      mul(transform.projection,
          mul(transform.view, mul(transform.model, float3(input.position, 1))));
  // output.position = float4(clipPos.xy, 0.0, 1.0);
  output.position = float4(clipPos, 1);
  // output.color = input.color;

  return output;
}

[shader("fragment")]
float4 fs_main(VertexOutput input) : SV_Target {
  return float4(0, 0, 0, 1);
}

