#include <metal_stdlib>
using namespace metal;

struct GlideFragmentInput {
    float4 position [[position]];
    float2 textureCoordinate;
};

struct GlideEffectUniforms {
    float2 resolution;
    float progress;
    float time;
    float seed;
    float padding0;
    float padding1;
    float padding2;
};

fragment float4 glideEffectFragment(
    GlideFragmentInput input [[stage_in]],
    texture2d<float> sourceTexture [[texture(0)]],
    constant GlideEffectUniforms& uniforms [[buffer(0)]]
) {
    constexpr sampler sourceSampler(coord::normalized, address::clamp_to_edge, filter::linear);
    const float progress = smoothstep(0.0, 1.0, clamp(uniforms.progress, 0.0, 1.0));
    const float scale = mix(1.0, 0.945, progress);
    const float downwardOffset = 22.0 * progress / max(uniforms.resolution.y, 1.0);
    float2 sourceCoordinate = input.textureCoordinate;
    sourceCoordinate.y -= downwardOffset;
    sourceCoordinate = (sourceCoordinate - 0.5) / scale + 0.5;
    sourceCoordinate.x += (sourceCoordinate.y - 0.5) * 0.032 * progress;

    const bool inside = all(sourceCoordinate >= 0.0) && all(sourceCoordinate <= 1.0);
    if (!inside) {
        return float4(0.0);
    }

    float4 color = sourceTexture.sample(sourceSampler, sourceCoordinate);
    color.a *= 1.0 - progress;
    return color;
}
