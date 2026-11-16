#pragma once

// The turn of a rigid shape below an NiBillboardNode, done per vertex, so every reference
// of a mesh shares one GPU mesh. It matches NIFBillboard.rotation on the CPU; the modes
// and axes are in docs/formats/nif-sequences.md#billboard-nodes.

#include "ShaderCommon.h"
#include "SurfaceShading.h"

struct BillboardTurn
{
    /// The world-space rotation about `pivot`.
    float3x3 rotation;
    float3 pivot;
};

static inline float3x3 billboardQuaternionMatrix(float4 q)
{
    return float3x3(
        float3(
            1.0 - 2.0 * (q.y * q.y + q.z * q.z), 2.0 * (q.x * q.y + q.z * q.w),
            2.0 * (q.x * q.z - q.y * q.w)),
        float3(
            2.0 * (q.x * q.y - q.z * q.w), 1.0 - 2.0 * (q.x * q.x + q.z * q.z),
            2.0 * (q.y * q.z + q.x * q.w)),
        float3(
            2.0 * (q.x * q.z + q.y * q.w), 2.0 * (q.y * q.z - q.x * q.w),
            1.0 - 2.0 * (q.x * q.x + q.y * q.y)));
}

/// `vector` without its part along the unit `axis`, made unit length; false when too short.
static inline bool billboardFlattened(float3 vector, float3 axis, thread float3 &flat)
{
    float3 rest = vector - dot(vector, axis) * axis;
    float size = length(rest);
    if (size <= 1e-6) {
        return false;
    }
    flat = rest / size;
    return true;
}

/// The shortest turn that takes the node's +Z to `front`, so it keeps its authored roll.
static inline bool billboardMinimised(float3x3 authored, float3 front, thread float3x3 &turned)
{
    if (length(front) <= 1e-6) {
        return false;
    }
    float3 from = authored[2];
    float3 to = normalize(front);
    float cosine = dot(from, to);
    float3x3 turn;
    if (cosine < -0.9999) {
        // Opposite: half a turn about the node's +Y.
        float3 axis = authored[1];
        turn = float3x3(axis * (2.0 * axis.x), axis * (2.0 * axis.y), axis * (2.0 * axis.z)) -
               float3x3(1.0);
    } else {
        float3 v = cross(from, to);
        float3x3 skew =
            float3x3(float3(0.0, v.z, -v.y), float3(-v.z, 0.0, v.x), float3(v.y, -v.x, 0.0));
        turn = float3x3(1.0) + skew + skew * skew * (1.0 / (1.0 + cosine));
    }
    turned = turn * authored;
    return true;
}

/// +Z along `front`, +Y as near `up` as the turn allows.
static inline bool billboardFacing(float3 front, float3 up, thread float3x3 &turned)
{
    if (length(front) <= 1e-6) {
        return false;
    }
    float3 z = normalize(front);
    float3 y;
    if (!billboardFlattened(up, z, y)) {
        return false;
    }
    turned = float3x3(cross(y, z), y, z);
    return true;
}

/// The turn of this draw's billboard for the instance at `model`. A draw without one, or
/// a degenerate view, keeps the shape at rest.
static inline BillboardTurn
billboardTurn(constant DrawUniforms &draw, float4x4 model, constant FrameUniforms &frame)
{
    BillboardTurn rest = {float3x3(1.0), float3(0.0)};
    if (draw.billboardPivot.w < 0.5) {
        return rest;
    }
    uint mode = uint(draw.billboardPivot.w - 0.5) & 0x7;
    float3x3 placed = upper3x3(model);
    placed = float3x3(normalize(placed[0]), normalize(placed[1]), normalize(placed[2]));
    float3x3 authored = placed * billboardQuaternionMatrix(draw.billboardRotation);
    float3 pivot = (model * float4(draw.billboardPivot.xyz, 1.0)).xyz;
    float3 toEye = frame.cameraPosition - pivot;
    float3x3 turned;
    bool valid;
    if (mode == 1 || mode == 5) {
        // Mode 1 turns about its own +Y with +Z to the eye; mode 5 about +Z with -Y to it.
        float3 axis = mode == 1 ? authored[1] : authored[2];
        float3 front;
        valid = billboardFlattened(toEye, axis, front);
        turned = mode == 1 ? float3x3(cross(axis, front), axis, front)
                           : float3x3(cross(-front, axis), -front, axis);
    } else if (mode == 0) {
        valid = billboardMinimised(authored, -frame.cameraForward, turned);
    } else if (mode == 2) {
        valid = billboardFacing(-frame.cameraForward, frame.cameraUp, turned);
    } else if (mode == 3) {
        valid = billboardMinimised(authored, toEye, turned);
    } else {
        valid = billboardFacing(toEye, frame.cameraUp, turned);
    }
    if (!valid) {
        return rest;
    }
    BillboardTurn turn = {turned * transpose(authored), pivot};
    return turn;
}
