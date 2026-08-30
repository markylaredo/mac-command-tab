#include <metal_stdlib>
using namespace metal;

struct PixelateFragmentInput {
    float4 position [[position]];
    float2 textureCoordinate;
};

struct PixelateEffectUniforms {
    float2 resolution;
    float progress;
    float time;
    float seed;
    float padding0;
    float padding1;
    float padding2;
};

static float stableNoise(float2 cell, float seed) {
    const float value = dot(cell + seed * 91.73, float2(12.9898, 78.233));
    return fract(sin(value) * 43758.5453);
}

fragment float4 pixelateEffectFragment(
    PixelateFragmentInput input [[stage_in]],
    texture2d<float> sourceTexture [[texture(0)]],
    constant PixelateEffectUniforms& uniforms [[buffer(0)]]
) {
    constexpr sampler sourceSampler(coord::normalized, address::clamp_to_edge, filter::linear);
    const float progress = clamp(uniforms.progress, 0.0, 1.0);
    const float eased = progress * progress * (3.0 - 2.0 * progress);
    const float blockSize = mix(1.0, 54.0, pow(eased, 1.25));
    const float2 sampleGrid = max(uniforms.resolution / blockSize, float2(1.0));
    const float2 sampleCoordinate = (floor(input.textureCoordinate * sampleGrid) + 0.5) / sampleGrid;

    float4 color = sourceTexture.sample(sourceSampler, sampleCoordinate);
    const float2 stableGrid = max(uniforms.resolution / 28.0, float2(1.0));
    const float2 stableCell = floor(input.textureCoordinate * stableGrid);
    const float noise = stableNoise(stableCell, uniforms.seed);
    const float removalThreshold = smoothstep(0.22, 0.94, progress);
    const float keepBlock = step(removalThreshold, noise);
    const float remainingAlpha = 1.0 - smoothstep(0.70, 1.0, progress);
    color.a *= keepBlock * remainingAlpha;
    return color;
}
