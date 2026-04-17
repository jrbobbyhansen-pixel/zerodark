// VoxelFusion.metal — Metal compute kernel for depth-image processing in LingBot-Map stack
// Handles per-pixel ray unprojection and compact depth statistics extraction.
// Used by VoxelStreamMap when enableMetalFusion = true for stride-gated acceleration.
//
// Note: The primary TSDF integration runs on CPU (StreamingVoxelMap.swift) where the
// Swift Dictionary hash-grid lives. This kernel handles the inner loop pixel work —
// unprojecting depth samples into world-space candidates that the CPU then integrates.

#include <metal_stdlib>
using namespace metal;

// MARK: - Shared Structures (must match VoxelCell layout in StreamingVoxelMap.swift)

struct VoxelCell {
    float3 normalSum;        // 12 bytes
    uint   hitCount;         // 4 bytes
    float  lastSeen;         // 4 bytes
    float  tsdfValue;        // 4 bytes
    float  tsdfWeight;       // 4 bytes
    float  occupancy;        // 4 bytes
    uint   keyframeId;       // 4 bytes
    ushort flags;            // 2 bytes
    ushort _pad;             // 2 bytes
    // total: 40 bytes, padded to 48 by compiler alignment — matches Swift struct
};

struct CameraIntrinsics {
    float fx;
    float fy;
    float cx;
    float cy;
    uint  imageWidth;
    uint  imageHeight;
    float nearPlane;
    float farPlane;
};

// 3D world point packed for CPU readback
struct WorldPoint {
    float x, y, z;
    float depth;         // original depth value
    uint  pixelX;
    uint  pixelY;
};

// MARK: - Depth Image Unprojection
// Extracts world-space 3D points from a depth image, applying stride-based
// subsampling to match the thermal throttle level set by LiDARPipeline.

kernel void unprojectDepth(
    device const float*          depthMap     [[buffer(0)]],   // ARDepthMap as float[]
    constant CameraIntrinsics&   intrinsics   [[buffer(1)]],
    constant float4x4&           cameraToWorld[[buffer(2)]],   // camera transform
    device WorldPoint*           outPoints    [[buffer(3)]],   // output array
    device atomic_uint*          outCount     [[buffer(4)]],   // written point count
    constant uint&               stride       [[buffer(5)]],   // 1/2/4 from throttle
    constant uint&               maxPoints    [[buffer(6)]],
    uint2 gid [[thread_position_in_grid]]
) {
    // Apply stride subsampling
    if (gid.x % stride != 0 || gid.y % stride != 0) return;
    if (gid.x >= intrinsics.imageWidth || gid.y >= intrinsics.imageHeight) return;

    uint pixelIdx = gid.y * intrinsics.imageWidth + gid.x;
    float depth = depthMap[pixelIdx];

    if (depth <= intrinsics.nearPlane || depth >= intrinsics.farPlane) return;
    if (isnan(depth) || isinf(depth)) return;

    // Unproject pixel to camera space
    float camX = (float(gid.x) - intrinsics.cx) * depth / intrinsics.fx;
    float camY = (float(gid.y) - intrinsics.cy) * depth / intrinsics.fy;
    float camZ = depth;

    // Transform to world space
    float4 camPoint = float4(camX, -camY, -camZ, 1.0);  // ARKit: Y-up, Z-backward
    float4 worldPoint = cameraToWorld * camPoint;

    // Atomic increment output counter and write
    uint idx = atomic_fetch_add_explicit(outCount, 1, memory_order_relaxed);
    if (idx >= maxPoints) return;

    outPoints[idx].x = worldPoint.x;
    outPoints[idx].y = worldPoint.y;
    outPoints[idx].z = worldPoint.z;
    outPoints[idx].depth = depth;
    outPoints[idx].pixelX = gid.x;
    outPoints[idx].pixelY = gid.y;
}

// MARK: - Cover Candidate Scan
// Scans a dense voxel region (encoded as flat array) and marks cover candidates.
// This handles the `hitCount > threshold && height > ground + minHeight` check
// in parallel instead of iterating the Swift Dictionary.

struct CoverCandidate {
    float3 position;
    float  protection;  // min(hitCount / 50, 1.0)
};

kernel void scanCoverCandidates(
    device const VoxelCell*    voxels     [[buffer(0)]],
    constant uint&             count      [[buffer(1)]],
    constant float&            voxelSize  [[buffer(2)]],
    constant float&            groundY    [[buffer(3)]],
    constant float&            minHeight  [[buffer(4)]],
    constant uint&             hitThresh  [[buffer(5)]],
    device CoverCandidate*     outCovers  [[buffer(6)]],
    device atomic_uint*        outCount   [[buffer(7)]],
    constant uint&             maxCovers  [[buffer(8)]],
    // Key array aligned with voxel array
    device const int3*         keys       [[buffer(9)]],
    uint tid [[thread_position_in_grid]]
) {
    if (tid >= count) return;

    VoxelCell cell = voxels[tid];
    if (cell.hitCount < hitThresh) return;
    if ((cell.flags & 0x02) == 0) return;  // flagCover bit

    int3 key = keys[tid];
    float3 pos = float3(
        (float(key.x) + 0.5) * voxelSize,
        (float(key.y) + 0.5) * voxelSize,
        (float(key.z) + 0.5) * voxelSize
    );

    if (pos.y < groundY + minHeight) return;

    uint idx = atomic_fetch_add_explicit(outCount, 1, memory_order_relaxed);
    if (idx >= maxCovers) return;

    float protection = min(float(cell.hitCount) / 50.0, 1.0);
    outCovers[idx] = { pos, protection };
}
