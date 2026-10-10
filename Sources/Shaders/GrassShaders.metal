#include "ShaderCommon.h"

// GRAS path: same material/lighting model as cutout static meshes, with one
// placement per GPU instance. LAND tint is per instance. Weather wind bends
// only upper vertices; wave period + stable phase keep neighboring blades
// asynchronous. Distance fade multiplies alpha before cutoff.

typedef struct
{
    float4 position [[position]];
    float3 normal;
    float3 worldPosition;
    float2 texcoord;
    float4 color;
    float distanceFade;
} GrassVertexOut;

/// Wind, tint, and fade of one grass vertex; the vertex and mesh paths share it.
static GrassVertexOut grassVertexOut(
    float3 position,
    float3 normal,
    float2 texcoord,
    float4 color,
    const device InstanceTransform &instance,
    constant FrameUniforms &frame,
    constant GrassDrawUniforms &draw)
{
    float4 world = instance.modelMatrix * float4(position, 1.0);
    float height = saturate((position.z - draw.modelMinimumZ) * draw.inverseModelHeight);
    float wavePeriod = max(instance.grassParameters.x, 0.1);
    float phase = frame.animationTime / wavePeriod + instance.grassParameters.y;
    float oscillation = sin(phase * 6.28318530718);
    float bend = height * height * (72.0 + 24.0 * oscillation);
    world.xy += frame.grassWind * bend;

    GrassVertexOut out;
    out.position = frame.viewProjectionMatrix * world;
    out.normal = (instance.normalMatrix * float4(normal, 0.0)).xyz;
    out.worldPosition = world.xyz;
    out.texcoord = texcoord * draw.uvScale + draw.uvOffset;
    out.color = color * instance.instanceColor;
    float fadeWidth = max(frame.grassFadeDistances.y - frame.grassFadeDistances.x, 1.0);
    out.distanceFade = saturate(
        (frame.grassFadeDistances.y - distance(world.xyz, frame.cameraPosition)) / fadeWidth);
    return out;
}

vertex GrassVertexOut grassVertex(
    StaticVertexIn in [[stage_in]],
    uint instanceID [[instance_id]],
    constant FrameUniforms &frame [[buffer(BufferIndexFrameUniforms)]],
    constant GrassDrawUniforms &draw [[buffer(BufferIndexDrawUniforms)]],
    const device InstanceTransform *instances [[buffer(BufferIndexInstanceTransforms)]])
{
    return grassVertexOut(
        in.position, in.normal, in.texcoord, in.color, instances[instanceID], frame, draw);
}

// Mesh-shader grass (docs/rendering/mesh-shader-grass.md). One object threadgroup is one
// SIMD group: each lane tests one instance-meshlet pair and the group launches a mesh
// threadgroup per pair it keeps. The mesh threadgroup writes that meshlet's triangles.

constant uint kGrassMeshletsPerObjectGroup = 32;
constant uint kGrassMeshletMaxVertices = 64;
constant uint kGrassMeshletMaxTriangles = 64;

/// Kept pairs, as `instance * meshletCount + meshlet`.
typedef struct
{
    uint pairs[kGrassMeshletsPerObjectGroup];
} GrassMeshletPayload;

/// The interleaved static vertex (StaticVertexLayout, 48 bytes), read without stage_in.
typedef struct
{
    packed_float3 position;
    packed_float3 normal;
    float2 texcoord;
    float4 color;
} GrassMeshVertex;

static bool grassMeshletVisible(
    MeshletBounds meshlet,
    const device InstanceTransform &instance,
    constant FrameUniforms &frame,
    constant GrassMeshUniforms &mesh)
{
    float3 center = (instance.modelMatrix * float4(meshlet.centerRadius.xyz, 1.0)).xyz;
    float scale =
        max(length(instance.modelMatrix[0].xyz),
            max(length(instance.modelMatrix[1].xyz), length(instance.modelMatrix[2].xyz)));
    float radius = meshlet.centerRadius.w * scale + mesh.swayPadding;
    for (uint plane = 0; plane < 6; plane++) {
        float4 p = mesh.frustumPlanes[plane];
        if (dot(p.xyz, center) + p.w < -radius) {
            return false;
        }
    }
    if (mesh.cullBackfaces == 0 || meshlet.coneAxisCutoff.w <= -1.0) {
        return true;
    }
    float3 axis = normalize((instance.normalMatrix * float4(meshlet.coneAxisCutoff.xyz, 0)).xyz);
    float3 toCenter = center - frame.cameraPosition;
    return dot(toCenter, axis) < meshlet.coneAxisCutoff.w * length(toCenter) + radius;
}

[[object]] void grassMeshletObject(
    object_data GrassMeshletPayload &payload [[payload]],
    mesh_grid_properties grid,
    uint group [[threadgroup_position_in_grid]],
    uint lane [[thread_index_in_threadgroup]],
    constant FrameUniforms &frame [[buffer(BufferIndexFrameUniforms)]],
    constant GrassMeshUniforms &mesh [[buffer(BufferIndexGrassMeshUniforms)]],
    const device InstanceTransform *instances [[buffer(BufferIndexInstanceTransforms)]],
    const device MeshletBounds *meshlets [[buffer(BufferIndexMeshlets)]],
    device atomic_uint *counters [[buffer(BufferIndexMeshletCounters)]])
{
    uint pair = group * kGrassMeshletsPerObjectGroup + lane;
    bool tested = pair < mesh.instanceCount * mesh.meshletCount;
    bool visible = tested && grassMeshletVisible(
                                 meshlets[pair % mesh.meshletCount],
                                 instances[pair / mesh.meshletCount], frame, mesh);
    uint slot = simd_prefix_exclusive_sum(uint(visible));
    uint kept = simd_sum(uint(visible));
    uint testedCount = simd_sum(uint(tested));
    if (visible) {
        payload.pairs[slot] = pair;
    }
    if (lane == 0) {
        grid.set_threadgroups_per_grid(uint3(kept, 1, 1));
        atomic_fetch_add_explicit(&counters[mesh.counterBase], testedCount, memory_order_relaxed);
        atomic_fetch_add_explicit(&counters[mesh.counterBase + 1], kept, memory_order_relaxed);
    }
}

using GrassMeshletOutput = metal::mesh<
    GrassVertexOut,
    void,
    kGrassMeshletMaxVertices,
    kGrassMeshletMaxTriangles,
    topology::triangle>;

[[mesh]] void grassMeshletMesh(
    GrassMeshletOutput output,
    const object_data GrassMeshletPayload &payload [[payload]],
    uint group [[threadgroup_position_in_grid]],
    uint lane [[thread_index_in_threadgroup]],
    constant FrameUniforms &frame [[buffer(BufferIndexFrameUniforms)]],
    constant GrassDrawUniforms &draw [[buffer(BufferIndexDrawUniforms)]],
    constant GrassMeshUniforms &mesh [[buffer(BufferIndexGrassMeshUniforms)]],
    const device InstanceTransform *instances [[buffer(BufferIndexInstanceTransforms)]],
    const device GrassMeshVertex *vertices [[buffer(BufferIndexVertices)]],
    const device MeshletBounds *meshlets [[buffer(BufferIndexMeshlets)]],
    const device uint *vertexIndices [[buffer(BufferIndexMeshletVertices)]],
    const device uchar *triangles [[buffer(BufferIndexMeshletTriangles)]])
{
    uint pair = payload.pairs[group];
    MeshletBounds meshlet = meshlets[pair % mesh.meshletCount];
    const device InstanceTransform &instance = instances[pair / mesh.meshletCount];
    if (lane == 0) {
        output.set_primitive_count(meshlet.triangleCount);
    }
    if (lane < meshlet.vertexCount) {
        uint vertexIndex = min(vertexIndices[meshlet.vertexOffset + lane], mesh.vertexCount - 1);
        GrassMeshVertex v = vertices[vertexIndex];
        output.set_vertex(
            lane,
            grassVertexOut(
                float3(v.position), float3(v.normal), v.texcoord, v.color, instance, frame, draw));
    }
    if (lane < meshlet.triangleCount) {
        uint base = (meshlet.triangleOffset + lane) * 3;
        output.set_index(lane * 3, triangles[base]);
        output.set_index(lane * 3 + 1, triangles[base + 1]);
        output.set_index(lane * 3 + 2, triangles[base + 2]);
    }
}

fragment float4 grassFragment(
    GrassVertexOut in [[stage_in]],
    constant FrameUniforms &frame [[buffer(BufferIndexFrameUniforms)]],
    constant GrassDrawUniforms &draw [[buffer(BufferIndexDrawUniforms)]],
    texture2d<float> diffuseMap [[texture(TextureIndexDiffuse)]],
    depth2d_array<float> shadowMap [[texture(TextureIndexShadowMap)]],
    sampler trilinear [[sampler(SamplerIndexTrilinear)]],
    sampler shadowSampler [[sampler(SamplerIndexShadowCompare)]])
{
    float4 diffuse = diffuseMap.sample(trilinear, in.texcoord);
    // Grass vertex alpha is the wind weight, 0 at the root, not opacity.
    float alpha = diffuse.a * draw.materialAlpha * in.distanceFade;
    if (alpha < draw.alphaThreshold) {
        discard_fragment();
    }
    if (debugViewActive) {
        DebugSurface surface = {
            in.worldPosition, in.normal, in.texcoord,
            diffuseMap.calculate_unclamped_lod(trilinear, in.texcoord), uint(RenderLayerBitGrass)};
        return debugViewColor(frame, surface);
    }
    float3 normal = normalize(in.normal);
    float lambert = saturate(dot(normal, -frame.sunDirection));
    float shadow = draw.receivesShadows != 0
                       ? sunShadowFactor(in.worldPosition, frame, shadowMap, shadowSampler)
                       : 1.0;
    float3 illumination =
        frame.sunColor * lambert * shadow + frame.ambientColor + directionalAmbient(normal, frame);
    float3 lit = diffuse.rgb * in.color.rgb * illumination;
    // Opaque: alpha only gates the test above. The frame is premultiplied, so
    // a lower alpha would show as white or black.
    return float4(applyFog(lit, in.worldPosition, frame), 1.0);
}
