#include <metal_stdlib>
#include <SwiftUI/SwiftUI_Metal.h>
using namespace metal;

[[ stitchable ]] half4 Ripple(
    float2 position,
    SwiftUI::Layer layer,
    float2 origin,
    float time,
    float amplitude,
    float frequency,
    float decay,
    float speed
) {
    float distance = length(position - origin);
    float delay = distance / speed;
    time -= delay;
    time = max(0.0, time);
    
    float rippleAmount = amplitude * sin(frequency * time) * exp(-decay * time);
    float2 n = distance > 0.001 ? normalize(position - origin) : float2(0.0);
    float2 newPosition = position + rippleAmount * n;
    
    half4 color = layer.sample(newPosition);
    
    // Safety guard to prevent Divide By Zero crash
    if (amplitude > 0.001) {
        color.rgb += 0.3 * (rippleAmount / amplitude) * color.a;
    }
    
    return color;
}

[[ stitchable ]] half4 modernFluid(
    float2 position,
    SwiftUI::Layer layer,
    float t,
    float2 viewSize
) {
    // Safety guard to prevent NaN crash during SwiftUI layout transitions
    if (viewSize.x <= 0.1 || viewSize.y <= 0.1) {
        return layer.sample(position);
    }
    
    float2 uv = position / viewSize;
    float wave1 = sin(uv.x * 3.0 + t * 1.2) * 0.03;
    float wave2 = cos(uv.y * 2.5 + t * 0.8) * 0.03;
    
    float2 warpedUV = uv + float2(wave2, wave1);
    warpedUV = clamp(warpedUV, 0.0, 1.0);
    
    half4 color = layer.sample(warpedUV * viewSize);
    float sheen = sin(warpedUV.x * 5.0 + warpedUV.y * 5.0 - t * 1.5) * 0.03;
    color.rgb += half3(sheen);
    
    return color;
}
