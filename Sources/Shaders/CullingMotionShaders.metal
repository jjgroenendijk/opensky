#include "ShaderCommon.h"

// GPU frustum culling (docs/rendering/gpu-culling.md). The p-vertex test matches
// `Frustum.intersects`, so the CPU and GPU paths keep the same instances.
static bool cullPlaneKeeps(float4 plane, float3 lower, float3 upper)
{
    float3 farthest = select(lower, upper, plane.xyz >= 0.0);
    return !(dot(plane.xyz, farthest) + plane.w < 0.0);
}

kernel void cullInstances(
    device const CullInstance *instances [[buffer(CullBufferIndexInstances)]],
    constant CullParameters &parameters [[buffer(CullBufferIndexParameters)]],
    device InstanceTransform *output [[buffer(CullBufferIndexOutput)]],
    device atomic_uint *arguments [[buffer(CullBufferIndexArguments)]],
    device atomic_uint *rooms [[buffer(CullBufferIndexRooms)]],
    uint index [[thread_position_in_grid]])
{
    if (index >= parameters.instanceCount) {
        return;
    }
    device const CullInstance &instance = instances[index];
    if (parameters.roomWordCount > 0 && instance.room != 0xFFFFFFFFu) {
        uint word = instance.room / 32;
        uint bits = word < parameters.roomWordCount
                        ? atomic_load_explicit(&rooms[1 + word], memory_order_relaxed)
                        : 0u;
        if ((bits & (1u << (instance.room % 32))) == 0) {
            atomic_fetch_add_explicit(&rooms[0], 1, memory_order_relaxed);
            return;
        }
    }
    if (instance.boundsMax.w > 0.0) {
        for (uint plane = 0; plane < 6; plane++) {
            if (!cullPlaneKeeps(
                    parameters.planes[plane], instance.boundsMin.xyz, instance.boundsMax.xyz)) {
                return;
            }
        }
    }
    uint countWord = instance.group * CullConstantArgumentWords + 1;
    uint slot = atomic_fetch_add_explicit(&arguments[countWord], 1, memory_order_relaxed);
    output[instance.outputBase + slot] = instance.transform;
}

// Temporal upscaling motion (docs/rendering/upscaling.md). Motion is last frame's
// texture coordinate minus this frame's, both without the jitter.
static float2 textureCoordinate(float4 clip)
{
    return clip.xy / clip.w * float2(0.5, -0.5) + 0.5;
}

static float2 motionBetween(float4 currentClip, float4 previousClip)
{
    return textureCoordinate(previousClip) - textureCoordinate(currentClip);
}

// Every pixel moved only by the camera: reproject its depth with last frame's camera.
fragment float2 cameraMotionFragment(
    TextureReadbackVertexOut in [[stage_in]],
    constant UpscaleMotionUniforms &motion [[buffer(BufferIndexMotionUniforms)]],
    depth2d<float, access::read> depth [[texture(TextureIndexDiffuse)]])
{
    uint2 pixel = uint2(in.position.xy);
    float sceneDepth = depth.read(pixel);
    if (sceneDepth < motion.nearDepthLimit) {
        return float2(0.0);
    }
    float2 size = float2(depth.get_width(), depth.get_height());
    float2 ndc = in.position.xy / size * float2(2.0, -2.0) + float2(-1.0, 1.0);
    float4 world = motion.inverseJitteredViewProjection * float4(ndc, sceneDepth, 1.0);
    world /= world.w;
    return motionBetween(motion.viewProjection * world, motion.previousViewProjection * world);
}

struct MotionVertexOut
{
    float4 position [[position]];
    float4 currentClip;
    float4 previousClip;
};

static MotionVertexOut motionVertex(
    float4 world,
    float4 previousWorld,
    constant FrameUniforms &frame,
    constant UpscaleMotionUniforms &motion)
{
    MotionVertexOut out;
    // The jittered matrix the scene pass used, so the depth test matches its surface.
    out.position = frame.viewProjectionMatrix * world;
    out.currentClip = motion.viewProjection * world;
    out.previousClip = motion.previousViewProjection * previousWorld;
    return out;
}

vertex MotionVertexOut staticMotionVertex(
    StaticVertexIn in [[stage_in]],
    uint instanceID [[instance_id]],
    constant FrameUniforms &frame [[buffer(BufferIndexFrameUniforms)]],
    constant UpscaleMotionUniforms &motion [[buffer(BufferIndexMotionUniforms)]],
    const device MotionInstance *instances [[buffer(BufferIndexMotionInstances)]])
{
    const device MotionInstance &instance = instances[instanceID];
    float4 local = float4(in.position, 1.0);
    return motionVertex(instance.current * local, instance.previous * local, frame, motion);
}

vertex MotionVertexOut skinnedMotionVertex(
    SkinnedVertexIn in [[stage_in]],
    uint instanceID [[instance_id]],
    constant FrameUniforms &frame [[buffer(BufferIndexFrameUniforms)]],
    constant UpscaleMotionUniforms &motion [[buffer(BufferIndexMotionUniforms)]],
    const device MotionInstance *instances [[buffer(BufferIndexMotionInstances)]],
    const device matrix_float4x4 *bones [[buffer(BufferIndexBoneMatrices)]],
    const device matrix_float4x4 *previousBones [[buffer(BufferIndexPreviousBoneMatrices)]])
{
    float4 local = float4(in.position, 1.0);
    float4 skinned = 0.0;
    float4 previousSkinned = 0.0;
    for (uint influence = 0; influence < 4; ++influence) {
        float weight = in.boneWeights[influence];
        ushort bone = in.boneIndices[influence];
        skinned += weight * (bones[bone] * local);
        previousSkinned += weight * (previousBones[bone] * local);
    }
    const device MotionInstance &instance = instances[instanceID];
    return motionVertex(
        instance.current * skinned, instance.previous * previousSkinned, frame, motion);
}

fragment float2 objectMotionFragment(MotionVertexOut in [[stage_in]])
{
    return motionBetween(in.currentClip, in.previousClip);
}
