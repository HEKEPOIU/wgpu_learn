import "predefine/global";

struct VertexInput {
  uint instanceIndex : SV_VulkanInstanceID;
  [vk_location(0)]
  float2 position : POSITION;
  [vk_location(1)]
  float4 color : COLOR;
};

struct VertexOutput {
  float4 position : SV_Position;
  float4 color : COLOR;
};

[shader("vertex")]
VertexOutput vs_main(VertexInput input) {
  VertexOutput output;
  float3 clipPos = mul(MVP(input.instanceIndex), float3(input.position, 1));
  output.position = float4(clipPos, 1);
  output.color = input.color;

  return output;
}

[shader("fragment")]
float4 fs_main(VertexOutput input) : SV_Target { return input.color; }

