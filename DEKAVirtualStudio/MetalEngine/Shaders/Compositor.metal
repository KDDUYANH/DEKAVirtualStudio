//
//  Compositor.metal — the master pipeline.
//
//  Pass 1  prepareForeground : camera YCbCr -> spill -> grade -> LUT  (+ raw matte from chroma / AI)
//  Pass 2  gaussianBlur (H,V) : matte feather (Blur.metal)
//  Pass 3  compositeProgram  : background + shadow + light wrap + person + graphics + ticker -> MASTER
//  Pass 4  packNV12          : MASTER -> encoder-native NV12 (Output.metal)
//
//  Everything runs at output resolution in one command buffer. No CPU touches pixels.
//

#include "ShaderCommon.h"
#include "ColorGrade.h"
#include "LUT.h"
#include "ChromaKey.h"

kernel void prepareForeground(texture2d<float, access::sample> yTex       [[texture(0)]],
                              texture2d<float, access::sample> cTex       [[texture(1)]],
                              texture2d<float, access::sample> aiMask     [[texture(2)]],
                              texture2d<float, access::sample> blurLuma   [[texture(3)]],
                              texture3d<float, access::sample> lut        [[texture(4)]],
                              texture2d<half,  access::write>  fgOut      [[texture(5)]],
                              texture2d<half,  access::write>  matteOut   [[texture(6)]],
                              constant DEKAFrameUniforms& u               [[buffer(0)]],
                              uint2 gid [[thread_position_in_grid]])
{
    if (gid.x >= fgOut.get_width() || gid.y >= fgOut.get_height()) { return; }

    float2 uv  = (float2(gid) + 0.5) / u.outputSize;
    float2 src = outputToSourceUV(uv, u);

    if (!insideUnit(src)) {
        // Camera scaled/moved away from this pixel: transparent foreground.
        fgOut.write(half4(0.0h), gid);
        matteOut.write(half4(0.0h), gid);
        return;
    }

    float3 rgb = decodeYCbCr(yTex, cTex, src, u);

    // ---- Matte (computed on the UNGRADED source so grading never changes the key) ----
    float matte = 1.0;
    if (u.keyMode == DEKA_KEY_CHROMA) {
        float2 cbcr = rgbToCbCr709(rgb);
        matte = chromaMatte(cbcr, u);
        rgb   = spillSuppress(rgb, cbcr, u);
    } else if (u.keyMode == DEKA_KEY_AI) {
        matte = aiMask.sample(kLinearClamp, src).r;
    }

    // ---- Grade + LUT ----
    float srcY  = (yTex.sample(kLinearClamp, src).r - u.yuvOffset.x) * u.yuvScale.x;
    float blurY = (blurLuma.sample(kLinearClamp, src).r - u.yuvOffset.x) * u.yuvScale.x;
    rgb = colorGrade(rgb, srcY, blurY, u);
    rgb = applyLUT(rgb, lut, u);

    fgOut.write(half4(half3(rgb), 1.0h), gid);
    matteOut.write(half4(half(matte), 0.0h, 0.0h, 1.0h), gid);
}

inline float3 backgroundColor(float2 uv, texture2d<float, access::sample> bgTex, constant DEKAFrameUniforms& u) {
    float3 c = float3(0.0);
    if (u.bgType == DEKA_BG_SOLID) {
        c = u.bgColorA.rgb;
    } else if (u.bgType == DEKA_BG_GRADIENT) {
        float2 dir = float2(cos(u.bgGradientAngle), sin(u.bgGradientAngle));
        float t = saturate(dot(uv - 0.5, dir) + 0.5);
        c = mix(u.bgColorA.rgb, u.bgColorB.rgb, t);
    } else if (u.bgType == DEKA_BG_TEXTURE) {
        float2 p = (uv - 0.5 - u.bgOffset) / max(u.bgScale, float2(1e-3));
        p = p * u.bgAspectFix + 0.5;
        c = bgTex.sample(kLinearClamp, p).rgb;
    }
    c = (c - 0.5) * (1.0 + u.bgContrast) + 0.5 + 0.5 * u.bgBrightness;
    return saturate(c) * u.bgOpacity;
}

kernel void compositeProgram(texture2d<float, access::sample> fgTex      [[texture(0)]],
                             texture2d<float, access::sample> matteTex   [[texture(1)]],
                             texture2d<float, access::sample> bgTex      [[texture(2)]],
                             texture2d<float, access::sample> gfxTex     [[texture(3)]],
                             texture2d<float, access::sample> tickerTex  [[texture(4)]],
                             texture2d<float, access::write>  outTex     [[texture(5)]],
                             constant DEKAFrameUniforms& u               [[buffer(0)]],
                             uint2 gid [[thread_position_in_grid]])
{
    if (gid.x >= outTex.get_width() || gid.y >= outTex.get_height()) { return; }
    float2 uv = (float2(gid) + 0.5) / u.outputSize;

    float4 fg = fgTex.sample(kLinearClamp, uv);
    float3 color;

    if (u.keyMode == DEKA_KEY_OFF) {
        // No key: camera over black (areas outside a scaled camera stay black / background).
        float3 bg = backgroundColor(uv, bgTex, u);
        float a = matteTex.sample(kLinearClamp, uv).r; // 1 inside camera frame, 0 outside
        color = mix(bg, fg.rgb, a);
    } else {
        float soft = matteTex.sample(kLinearClamp, uv).r;
        float a = refineEdge(soft, u.keyEdge) * u.keyOpacity;

        float3 bg = backgroundColor(uv, bgTex, u);

        // Contact/drop shadow: the person's matte, offset, darkens the background only.
        if (u.shadowOpacity > 0.0) {
            float s = matteTex.sample(kLinearZero, uv - u.shadowOffset).r;
            bg *= 1.0 - u.shadowOpacity * s;
        }

        // Light wrap: background light bleeds onto the subject's edge — sells the composite.
        float3 person = fg.rgb;
        if (u.lightWrap > 0.0) {
            float edge = saturate(4.0 * soft * (1.0 - soft));
            person = mix(person, bg, u.lightWrap * edge);
        }
        color = mix(bg, person, a);
    }

    // Graphics layer (premultiplied alpha).
    if (u.graphicsEnabled != 0) {
        float4 g = gfxTex.sample(kLinearClamp, uv);
        color = g.rgb + color * (1.0 - g.a);
    }

    // Ticker text strip, scrolled in the shader (the text is rasterised only once).
    if (u.tickerEnabled != 0) {
        float2 local = (uv - u.tickerRect.xy) / max(u.tickerRect.zw, float2(1e-4));
        if (insideUnit(local)) {
            float rectAspect = (u.tickerRect.z * u.outputSize.x) / max(u.tickerRect.w * u.outputSize.y, 1.0);
            float su = fract(local.x * rectAspect / max(u.tickerStripAspect, 1e-3) + u.tickerScroll);
            float4 t = tickerTex.sample(kLinearRepeat, float2(su, local.y));
            color = t.rgb + color * (1.0 - t.a);
        }
    }

    outTex.write(float4(saturate(color), 1.0), gid);
}

/// FADE transition: the pipeline is rendered for both scenes, then mixed here.
kernel void mixPrograms(texture2d<float, access::read>  a     [[texture(0)]],
                        texture2d<float, access::read>  b     [[texture(1)]],
                        texture2d<float, access::write> out   [[texture(2)]],
                        constant DEKAFrameUniforms& u         [[buffer(0)]],
                        uint2 gid [[thread_position_in_grid]])
{
    if (gid.x >= out.get_width() || gid.y >= out.get_height()) { return; }
    out.write(mix(a.read(gid), b.read(gid), saturate(u.transitionMix)), gid);
}
