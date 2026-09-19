//
//  Preview.metal — operator monitor. Draws PROGRAM / MATTE / ORIGINAL into the on-screen
//  CAMetalLayer. The monitor mode never changes what goes to air or to the recorder.
//
#include "ShaderCommon.h"
#include "ChromaKey.h"

struct PreviewVOut {
    float4 position [[position]];
    float2 uv;
};

vertex PreviewVOut previewVertex(uint vid [[vertex_id]],
                                 constant DEKAPreviewUniforms& p [[buffer(0)]])
{
    const float2 pos[4] = { float2(-1, -1), float2(1, -1), float2(-1, 1), float2(1, 1) };
    PreviewVOut o;
    o.position = float4(pos[vid] * p.scale, 0.0, 1.0);
    o.uv = float2((pos[vid].x + 1.0) * 0.5, 1.0 - (pos[vid].y + 1.0) * 0.5);
    return o;
}

fragment float4 previewFragment(PreviewVOut in [[stage_in]],
                                texture2d<float, access::sample> program [[texture(0)]],
                                texture2d<float, access::sample> matte   [[texture(1)]],
                                texture2d<float, access::sample> yTex    [[texture(2)]],
                                texture2d<float, access::sample> cTex    [[texture(3)]],
                                constant DEKAPreviewUniforms& p          [[buffer(0)]],
                                constant DEKAFrameUniforms& u            [[buffer(1)]])
{
    if (p.mode == DEKA_PREVIEW_MATTE) {
        float m = refineEdge(matte.sample(kLinearClamp, in.uv).r, u.keyEdge);
        return float4(float3(m), 1.0);
    }
    if (p.mode == DEKA_PREVIEW_ORIGINAL) {
        float2 src = outputToSourceUV(in.uv, u);
        if (!insideUnit(src)) { return float4(0, 0, 0, 1); }
        return float4(decodeYCbCr(yTex, cTex, src, u), 1.0);
    }
    return float4(program.sample(kLinearClamp, in.uv).rgb, 1.0);
}
