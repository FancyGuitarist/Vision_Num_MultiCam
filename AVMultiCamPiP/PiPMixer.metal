#include <metal_stdlib>
using namespace metal;

struct MixerParameters {
    float2 topPosition;
    float2 topSize;
    float2 bottomPosition;
    float2 bottomSize;
};

constant sampler kBilinearSampler(filter::linear, coord::pixel, address::clamp_to_edge);

// Compute kernel
kernel void splitScreenMixer(texture2d<half, access::read> topInput [[ texture(0) ]],
                             texture2d<half, access::read> bottomInput [[ texture(1) ]],
                             texture2d<half, access::write> outputTexture [[ texture(2) ]],
                             const device MixerParameters& mixerParameters [[ buffer(0) ]],
                             uint2 gid [[thread_position_in_grid]]) {
    half4 output;

    // Calculate normalized coordinates
    float2 uv = float2(gid) / float2(outputTexture.get_width(), outputTexture.get_height());

    if (uv.y < 0.5) {
        // Top half
        float aspectRatio = float(topInput.get_width()) / float(topInput.get_height());
        float2 topUV = uv * float2(1.0, 2.0);
        topUV.y = (topUV.y - 0.5) * aspectRatio + 0.5; // Adjust for aspect ratio
        output = topInput.read(uint2(topUV * float2(topInput.get_width(), topInput.get_height())));
    } else {
        // Bottom half
        float aspectRatio = float(bottomInput.get_width()) / float(bottomInput.get_height());
        float2 bottomUV = (uv - float2(0.0, 0.5)) * float2(1.0, 2.0);
        bottomUV.y = (bottomUV.y - 0.5) * aspectRatio + 0.5; // Adjust for aspect ratio
        output = bottomInput.read(uint2(bottomUV * float2(bottomInput.get_width(), bottomInput.get_height())));
    }

    outputTexture.write(output, gid);
}
