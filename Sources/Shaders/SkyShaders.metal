#include "ShaderCommon.h"

// Exterior sky: fullscreen triangle. With weather active the sky uses the
// CPU-blended WTHR palette in FrameUniforms; otherwise the procedural
// time-of-day palette below.

vertex SkyVertexOut skyVertex(uint vertexID [[vertex_id]])
{
    float2 positions[3] = {float2(-1.0, -1.0), float2(3.0, -1.0), float2(-1.0, 3.0)};
    SkyVertexOut out;
    out.position = float4(positions[vertexID], 1.0, 1.0);
    out.uv = positions[vertexID] * 0.5 + 0.5;
    return out;
}

// The sun sits along the same direction that lights the scene. The pixel's
// view ray is rebuilt from the camera basis, so the disc stays round at any
// aspect ratio. Returns (disc, glow), both zero once the sun is below the horizon.
static float2 skySunDiscAndGlow(SkyVertexOut in, constant FrameUniforms &frame)
{
    float4 rightClip =
        frame.viewProjectionMatrix * float4(frame.cameraForward + frame.cameraRight, 0.0);
    float4 upClip = frame.viewProjectionMatrix * float4(frame.cameraForward + frame.cameraUp, 0.0);
    float2 ndc = in.uv * 2.0 - 1.0;
    float tanX = abs(rightClip.x) > 1e-5 ? rightClip.w / rightClip.x : 1.0;
    float tanY = abs(upClip.y) > 1e-5 ? upClip.w / upClip.y : 1.0;
    float3 ray = normalize(
        frame.cameraForward + frame.cameraRight * (ndc.x * tanX) + frame.cameraUp * (ndc.y * tanY));
    float3 towardSun = -normalize(frame.sunDirection);
    float aboveHorizon = smoothstep(-0.05, 0.05, towardSun.z);
    float angle = acos(clamp(dot(ray, towardSun), -1.0, 1.0));
    float disc = (1.0 - smoothstep(0.016, 0.02, angle)) * aboveHorizon;
    float glow = exp(-angle * 12.0) * aboveHorizon;
    return float2(disc, glow);
}

// Weather sky: horizon -> sky-lower -> sky-upper vertical gradient, with the
// sun disc and glow tinted by the weather sun and sun-glare colours.
static float4 weatherSky(SkyVertexOut in, constant FrameUniforms &frame)
{
    float3 lower =
        mix(frame.weatherHorizonColor, frame.weatherSkyLowerColor, smoothstep(0.0, 0.5, in.uv.y));
    float3 upper =
        mix(frame.weatherSkyLowerColor, frame.weatherSkyUpperColor, smoothstep(0.5, 1.0, in.uv.y));
    float3 color = in.uv.y < 0.5 ? lower : upper;

    float2 sun = skySunDiscAndGlow(in, frame);
    float3 tint =
        frame.weatherSunColor /
        max(max3(frame.weatherSunColor.r, frame.weatherSunColor.g, frame.weatherSunColor.b), 1e-3);
    color += frame.weatherGlareColor * sun.y * 0.5;
    color = mix(color, mix(tint, float3(1.0), 0.6), sun.x);
    return float4(color, 1.0);
}

fragment float4 skyFragment(
    SkyVertexOut in [[stage_in]],
    constant FrameUniforms &frame [[buffer(BufferIndexFrameUniforms)]])
{
    float hour = fmod(frame.timeOfDayHours + 24.0, 24.0);
    if (frame.weatherSkyEnabled != 0) {
        return weatherSky(in, frame);
    }
    float sunrise = smoothstep(5.0, 8.0, hour);
    float sunset = 1.0 - smoothstep(18.0, 21.0, hour);
    float daylight = sunrise * sunset;
    float dawnDistance = min(abs(hour - 6.0), abs(hour - 19.0));
    float twilight = exp(-0.5 * pow(dawnDistance / 1.2, 2.0));

    float3 nightUpper = float3(0.008, 0.015, 0.045);
    float3 dayUpper = float3(0.10, 0.34, 0.72);
    float3 nightHorizon = float3(0.025, 0.035, 0.075);
    float3 dayHorizon = float3(0.58, 0.74, 0.88);
    float3 warmHorizon = float3(0.95, 0.33, 0.12);
    float3 upper = mix(nightUpper, dayUpper, daylight);
    float3 horizon = mix(nightHorizon, dayHorizon, daylight);
    horizon = mix(horizon, warmHorizon, saturate(twilight * 0.7));
    float height = smoothstep(0.05, 0.92, in.uv.y);
    float3 color = mix(horizon, upper, height);

    float2 sun = skySunDiscAndGlow(in, frame);
    color += float3(1.0, 0.72, 0.36) * sun.y * 0.22;
    color = mix(color, float3(1.0, 0.95, 0.82), sun.x);
    return float4(color, 1.0);
}

// Weather cloud layers on the dome shapes of meshes\sky\clouds.nif. The dome
// follows the camera and draws behind everything, after the sky gradient.

typedef struct
{
    float4 position [[position]];
    float4 color;
    float2 texcoord;
} CloudVertexOut;

vertex CloudVertexOut cloudVertex(
    uint vertexID [[vertex_id]],
    const device CloudVertex *vertices [[buffer(BufferIndexVertices)]],
    constant FrameUniforms &frame [[buffer(BufferIndexFrameUniforms)]],
    constant CloudLayerUniforms &layer [[buffer(BufferIndexDrawUniforms)]])
{
    CloudVertex source = vertices[vertexID];
    float4 clip =
        frame.viewProjectionMatrix * float4(frame.cameraPosition + source.position.xyz, 1.0);
    // Any depth inside the clip range: the dome draws with no depth test.
    clip.z = clip.w * 0.5;
    CloudVertexOut out;
    out.position = clip;
    out.color = source.color;
    out.texcoord = source.texcoord + layer.uvOffset;
    return out;
}

fragment float4 cloudFragment(
    CloudVertexOut in [[stage_in]],
    constant CloudLayerUniforms &layer [[buffer(BufferIndexDrawUniforms)]],
    texture2d<float> cloudMap [[texture(TextureIndexDiffuse)]],
    sampler trilinear [[sampler(SamplerIndexTrilinear)]])
{
    float4 texel = cloudMap.sample(trilinear, in.texcoord);
    // The dome's vertex colours are (1, 0, 0, a): only the alpha, an edge fade, is used.
    float alpha = texel.a * layer.colorAlpha.a * in.color.a;
    return float4(texel.rgb * layer.colorAlpha.rgb, alpha);
}
