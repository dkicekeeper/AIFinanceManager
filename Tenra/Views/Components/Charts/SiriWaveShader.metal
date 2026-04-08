//
//  SiriWaveShader.metal
//  Tenra
//
//  Apple Intelligence Siri glow — vivid blurred blobs orbit the screen edges.
//

#include <metal_stdlib>
using namespace metal;

struct VertexOut {
    float4 position [[position]];
    float2 uv;
};

struct WaveUniforms {
    float time;
    float amplitude;
    float resW;
    float resH;
    float cornerR;
};

vertex VertexOut waveVertex(
    uint vertexID [[vertex_id]],
    constant float2* positions [[buffer(0)]]
) {
    VertexOut out;
    out.position = float4(positions[vertexID], 0.0, 1.0);
    out.uv = positions[vertexID] * 0.5 + 0.5;
    out.uv.y = 1.0 - out.uv.y;
    return out;
}

static float hash21(float2 p) {
    p = fract(p * float2(127.1, 311.7));
    p += dot(p, p.yx + 19.19);
    return fract(p.x * p.y);
}

static float smoothNoise(float2 p) {
    float2 i = floor(p);
    float2 f = fract(p);
    float2 u = f * f * (3.0 - 2.0 * f);
    return mix(
        mix(hash21(i),               hash21(i + float2(1, 0)), u.x),
        mix(hash21(i + float2(0, 1)), hash21(i + float2(1, 1)), u.x),
        u.y
    );
}

static float fbm(float2 p) {
    float v = 0.0, a = 0.5;
    for (int i = 0; i < 3; i++) {
        v += a * smoothNoise(p);
        p *= 2.0;
        a *= 0.5;
    }
    return v;
}

static float2 perimeterPoint(float param) {
    float d = fract(param) * 4.0;
    if (d < 1.0) return float2(d, 1.0);
    d -= 1.0;
    if (d < 1.0) return float2(1.0, 1.0 - d);
    d -= 1.0;
    if (d < 1.0) return float2(1.0 - d, 0.0);
    d -= 1.0;
    return float2(0.0, d);
}

fragment float4 waveFragment(
    VertexOut in [[stage_in]],
    constant WaveUniforms& u [[buffer(0)]]
) {
    float2 uv = in.uv;
    float  t  = u.time;
    float  amp = clamp(u.amplitude, 0.05, 1.0);
    float  aspect = u.resW / u.resH;

    // ── Edge mask: smooth rounded-rect distance, no corner creases ──
    // Distance from center in UV space, scaled so edges are at 0.5
    float2 fromCenter = abs(uv - 0.5);
    // Rounded-rect SDF in UV space: smooth corners instead of min() crease
    float cornerR = 0.08;  // corner rounding in UV units
    float2 q = fromCenter - float2(0.5) + cornerR;
    float rectDist = length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - cornerR;
    // rectDist: negative inside, 0 at edge
    // Convert to edge proximity: 0 at edge, grows toward center
    float edgeDist = -rectDist;

    float glowWidth = 0.18 + amp * 0.12;
    float edgeMask = smoothstep(glowWidth, 0.0, edgeDist);
    if (edgeMask < 0.001) return float4(0.0);

    // ── 10 vivid blobs ──
    const float3 colors[10] = {
        float3(0.55, 0.10, 1.00),
        float3(0.00, 0.75, 1.00),
        float3(1.00, 0.30, 0.55),
        float3(1.00, 0.60, 0.10),
        float3(0.25, 0.45, 1.00),
        float3(0.90, 0.20, 0.80),
        float3(0.10, 0.85, 0.65),
        float3(1.00, 0.45, 0.70),
        float3(0.65, 0.25, 1.00),
        float3(0.15, 0.60, 1.00)
    };

    const float speeds[10] = {
        0.018, 0.025, 0.014, 0.030, 0.020,
        0.016, 0.027, 0.022, 0.012, 0.024
    };

    float3 totalColor = float3(0.0);

    for (int i = 0; i < 10; i++) {
        float fi = float(i);

        float phase = fi * 0.1;
        float drift = (fbm(float2(fi * 3.1 + t * 0.05, t * 0.04 + fi * 2.0)) - 0.5) * 0.04;
        float param = fract(phase + t * speeds[i] + drift);
        float2 center = perimeterPoint(param);

        float2 centerNext = perimeterPoint(param + 0.005);
        float2 tangent = normalize(centerNext - center + 0.0001);

        float2 delta = uv - center;
        delta.x *= aspect;
        float2 cTan = normalize(float2(tangent.x * aspect, tangent.y));
        float2 cNrm = float2(-cTan.y, cTan.x);

        float along = dot(delta, cTan);
        float perp  = dot(delta, cNrm);

        float lenNoise = fbm(float2(fi * 4.2 + t * 0.12, t * 0.08 + fi));
        float blobLen  = 0.14 + lenNoise * 0.06 + amp * 0.05;
        float blobWid  = 0.06 + amp * 0.03;

        float dx = along / blobLen;
        float dy = perp / blobWid;
        float mask = exp(-(dx * dx + dy * dy) * 1.2);

        float intensity = 0.7 + amp * 1.0;
        totalColor += colors[i] * mask * intensity;
    }

    // Apply edge mask
    float3 color = totalColor * edgeMask;

    // Clamp to preserve hue (no gray shift)
    float peak = max(color.r, max(color.g, color.b));
    if (peak > 1.0) color /= peak;

    // ── Alpha from PRE-gamma color to prevent dark tinting ──
    // Dark pixels (low color) get low alpha → no darkening of background
    float preGammaLuma = dot(color, float3(0.299, 0.587, 0.114));
    float opacity = 0.50 + amp * 0.30;
    float alpha = saturate(preGammaLuma * 3.0) * opacity;

    // Kill alpha when color is too dim — prevents any dark fringing
    if (preGammaLuma < 0.03) alpha = 0.0;

    // Gamma correction (after alpha computation)
    color = pow(max(color, 0.0), float3(1.0 / 2.2));

    return float4(color * alpha, alpha);
}
