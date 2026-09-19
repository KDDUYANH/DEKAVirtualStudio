//
//  Blur.metal — separable Gaussian (weights computed on the CPU once per radius) + resample.
//  Used for matte feather, background blur and midtone-detail luma.
//
#include "ShaderCommon.h"

kernel void gaussianBlur(texture2d<float, access::sample> src     [[texture(0)]],
                         texture2d<float, access::write>  dst     [[texture(1)]],
                         constant DEKABlurParams& p               [[buffer(0)]],
                         constant float* weights                  [[buffer(1)]],
                         uint2 gid [[thread_position_in_grid]])
{
    if (gid.x >= dst.get_width() || gid.y >= dst.get_height()) { return; }
    float2 size = float2(dst.get_width(), dst.get_height());
    float2 uv = (float2(gid) + 0.5) / size;
    float2 stepUV = (p.horizontal != 0) ? float2(1.0 / size.x, 0.0) : float2(0.0, 1.0 / size.y);

    float4 acc = src.sample(kLinearClamp, uv) * weights[0];
    for (int i = 1; i <= p.radius; ++i) {
        float w = weights[i];
        acc += src.sample(kLinearClamp, uv + stepUV * float(i)) * w;
        acc += src.sample(kLinearClamp, uv - stepUV * float(i)) * w;
    }
    dst.write(acc, gid);
}

/// Bilinear resample (downscale for cheap large blurs, or any size change).
kernel void resampleTexture(texture2d<float, access::sample> src [[texture(0)]],
                            texture2d<float, access::write>  dst [[texture(1)]],
                            uint2 gid [[thread_position_in_grid]])
{
    if (gid.x >= dst.get_width() || gid.y >= dst.get_height()) { return; }
    float2 uv = (float2(gid) + 0.5) / float2(dst.get_width(), dst.get_height());
    dst.write(src.sample(kLinearClamp, uv), gid);
}
