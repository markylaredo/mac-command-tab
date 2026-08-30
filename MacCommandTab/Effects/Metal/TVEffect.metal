#include <metal_stdlib>
using namespace metal;

struct TVFragmentInput {
    float4 position [[position]];
    float2 textureCoordinate;
};

struct TVEffectUniforms {
    float2 resolution;
    float progress;
    float time;
    float seed;
    float padding0;
    float padding1;
    float padding2;
};

fragment float4 tvEffectFragment(
    TVFragmentInput input [[stage_in]],
    texture2d<float> sourceTexture [[texture(0)]],
    constant TVEffectUniforms& uniforms [[buffer(0)]]
) {
    constexpr sampler sourceSampler(coord::normalized, address::clamp_to_edge, filter::linear);
    const float progress = clamp(uniforms.progress, 0.0, 1.0);
    const float verticalPhase = smoothstep(0.0, 0.62, progress);
    const float horizontalPhase = smoothstep(0.58, 0.90, progress);
    const float visibleHeight = max(1.0 - verticalPhase * 0.985, 0.015);
    const float visibleWidth = max(1.0 - horizontalPhase * 0.99, 0.01);
    const float2 centered = input.textureCoordinate - 0.5;
    const float2 sourceCoordinate = centered / float2(visibleWidth, visibleHeight) + 0.5;
    const bool inside = all(sourceCoordinate >= 0.0) && all(sourceCoordinate <= 1.0);
    if (!inside) {
        return float4(0.0);
    }

    float4 color = sourceTexture.sample(sourceSampler, sourceCoordinate);
    const float lineDistance = abs(input.textureCoordinate.y - 0.5) * max(uniforms.resolution.y, 1.0);
    const float line = exp(-lineDistance * lineDistance / 9.0);
    const float linePhase = smoothstep(0.72, 0.88, progress) * (1.0 - smoothstep(0.94, 1.0, progress));
    color.rgb += line * linePhase * float3(1.15, 1.15, 1.08);
    color.a *= 1.0 - smoothstep(0.91, 1.0, progress);
    return color;
}
