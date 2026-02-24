#include <metal_stdlib>
using namespace metal;

// -- Shared types (must match Swift GhostVertex) --

struct GhostVertex {
    float2 position;  // clip space [-1, 1]
    float4 color;     // RGBA
    float2 uv;        // distance from center line (u), along bone (v)
};

struct VertexOut {
    float4 position [[position]];
    float4 color;
    float2 uv;
};

// -- Uniforms --

struct GhostUniforms {
    float beatPulse;     // 0.0 - 1.0, pulses on beat
    float time;          // for animation
    float glowIntensity; // overall glow strength
    float padding;
};

// ========================================
// Capsule / Bone Shader
// ========================================

vertex VertexOut ghost_vertex(
    uint vid [[vertex_id]],
    constant GhostVertex* vertices [[buffer(0)]],
    constant GhostUniforms& uniforms [[buffer(1)]]
) {
    GhostVertex v = vertices[vid];
    VertexOut out;
    out.position = float4(v.position, 0.0, 1.0);
    out.color = v.color;
    out.uv = v.uv;
    return out;
}

fragment float4 ghost_fragment(
    VertexOut in [[stage_in]],
    constant GhostUniforms& uniforms [[buffer(1)]]
) {
    float4 color = in.color;

    // Capsule cross-section: soft glow falloff from center line
    // uv.x = 0 at center, 1 at edge
    float dist = abs(in.uv.x);
    float capsuleAlpha = smoothstep(1.0, 0.3, dist);

    // Emissive glow that pulses on beat
    float pulse = 1.0 + uniforms.beatPulse * 0.4;
    float glow = (1.0 - dist) * uniforms.glowIntensity * pulse;

    // Combine: base capsule + additive glow
    // Shift glow color from blue to gold as combo multiplier increases
    float comboBlend = saturate((uniforms.glowIntensity - 1.0) * 2.0);
    float3 baseColor = color.rgb * capsuleAlpha;
    float3 glowTint = mix(float3(0.6, 0.85, 1.0), float3(1.0, 0.85, 0.1), comboBlend);
    float3 glowColor = glowTint * glow * 0.5;
    float3 final = baseColor + glowColor;

    float alpha = color.a * capsuleAlpha;

    return float4(final, alpha);
}

// ========================================
// Joint Circle Shader
// ========================================

vertex VertexOut joint_vertex(
    uint vid [[vertex_id]],
    constant GhostVertex* vertices [[buffer(0)]],
    constant GhostUniforms& uniforms [[buffer(1)]]
) {
    GhostVertex v = vertices[vid];
    VertexOut out;
    out.position = float4(v.position, 0.0, 1.0);
    out.color = v.color;
    out.uv = v.uv;
    return out;
}

fragment float4 joint_fragment(
    VertexOut in [[stage_in]],
    constant GhostUniforms& uniforms [[buffer(1)]]
) {
    // uv is distance from joint center in normalized space
    float dist = length(in.uv);

    // Soft circle with glow
    float circleAlpha = smoothstep(1.0, 0.5, dist);

    float pulse = 1.0 + uniforms.beatPulse * 0.6;
    float glow = (1.0 - dist) * pulse;

    float3 baseColor = in.color.rgb * circleAlpha;
    float3 glowAdd = float3(0.7, 0.9, 1.0) * glow * 0.3;

    return float4(baseColor + glowAdd, in.color.a * circleAlpha);
}

// ========================================
// Particle Shader
// ========================================

vertex VertexOut particle_vertex(
    uint vid [[vertex_id]],
    constant GhostVertex* vertices [[buffer(0)]],
    constant GhostUniforms& uniforms [[buffer(1)]]
) {
    GhostVertex v = vertices[vid];
    VertexOut out;
    out.position = float4(v.position, 0.0, 1.0);
    out.color = v.color;
    out.uv = v.uv;
    return out;
}

fragment float4 particle_fragment(
    VertexOut in [[stage_in]],
    constant GhostUniforms& uniforms [[buffer(1)]]
) {
    // Circular particle with soft edge
    float dist = length(in.uv);
    float alpha = smoothstep(1.0, 0.0, dist) * in.color.a;

    // Bright center, fading edge
    float3 color = in.color.rgb * (1.0 + (1.0 - dist) * 0.5);

    return float4(color, alpha);
}

// ========================================
// Score Flash Overlay
// ========================================

vertex VertexOut flash_vertex(
    uint vid [[vertex_id]],
    constant GhostVertex* vertices [[buffer(0)]]
) {
    GhostVertex v = vertices[vid];
    VertexOut out;
    out.position = float4(v.position, 0.0, 1.0);
    out.color = v.color;
    out.uv = v.uv;
    return out;
}

fragment float4 flash_fragment(
    VertexOut in [[stage_in]]
) {
    // Simple fullscreen color flash
    return in.color;
}
