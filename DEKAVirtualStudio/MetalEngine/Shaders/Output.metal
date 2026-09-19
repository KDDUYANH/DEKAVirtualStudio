//
//  Output.metal — MASTER (RGB) -> NV12 BT.709 video range, written straight into the
//  IOSurface-backed CVPixelBuffer that WebRTC (VideoToolbox H.264) and AVAssetWriter consume.
//  One thread per 2x2 block: 4 luma samples + 1 chroma sample. Zero CPU conversion.
//
#include "ShaderCommon.h"

kernel void packNV12(texture2d<float, access::read>  master [[texture(0)]],
                     texture2d<float, access::write> yOut   [[texture(1)]],
                     texture2d<float, access::write> cOut   [[texture(2)]],
                     uint2 gid [[thread_position_in_grid]])
{
    if (gid.x >= cOut.get_width() || gid.y >= cOut.get_height()) { return; }
    const float3 kY = float3(0.2126, 0.7152, 0.0722);
    uint2 base = gid * 2;
    uint2 maxP = uint2(master.get_width() - 1, master.get_height() - 1);
    float3 sum = float3(0.0);
    for (uint dy = 0; dy < 2; ++dy) {
        for (uint dx = 0; dx < 2; ++dx) {
            uint2 p = min(base + uint2(dx, dy), maxP);
            float3 rgb = master.read(p).rgb;
            sum += rgb;
            float y = dot(rgb, kY);
            yOut.write(float4(16.0 / 255.0 + y * (219.0 / 255.0)), base + uint2(dx, dy));
        }
    }
    float3 avg = sum * 0.25;
    float y  = dot(avg, kY);
    float cb = (avg.b - y) / 1.8556;
    float cr = (avg.r - y) / 1.5748;
    cOut.write(float4(128.0 / 255.0 + cb * (224.0 / 255.0),
                      128.0 / 255.0 + cr * (224.0 / 255.0), 0.0, 1.0), gid);
}
