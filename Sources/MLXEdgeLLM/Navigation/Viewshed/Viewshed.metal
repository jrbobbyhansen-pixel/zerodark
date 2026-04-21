// Viewshed.metal — GPU viewshed compute kernel.
//
// Input:
//   dem[W*H]     — Float elevation grid (meters) laid out row-major (y * W + x)
//   params       — observer, grid geometry, earth-curvature constants
// Output:
//   visibility[W*H] — 1.0 where LoS from observer to that cell is clear, 0.0 blocked
//
// Algorithm per thread:
//   1. Compute the target cell's (x, y) from thread position.
//   2. Walk N intermediate samples between observer and target cell using linear
//      interpolation in grid space; for each, interpolate DEM elevation.
//   3. Compute the expected altitude of the LoS line at each step (linear
//      observerZ → targetZ). Subtract the earth-curvature drop at range r:
//          drop = r² / (2R)   with R = 6_371_000 m
//   4. If any intermediate DEM sample sits above the adjusted LoS altitude,
//      target is blocked; exit early.

#include <metal_stdlib>
using namespace metal;

struct ViewshedParams {
    int width;              // DEM width in cells
    int height;             // DEM height in cells
    int observerX;          // observer cell column
    int observerY;          // observer cell row
    float cellSizeMeters;   // meters per cell edge
    float observerElevation;// absolute elevation of observer point (DEM + eye height)
    float targetHeight;     // height above ground to test at target
    float earthRadius;      // meters (usually 6371000)
    int maxSteps;           // intermediate samples along each ray
};

inline float interpolateDEM(device const float* dem, int W, int H, float fx, float fy) {
    int x0 = clamp(int(floor(fx)), 0, W - 1);
    int y0 = clamp(int(floor(fy)), 0, H - 1);
    int x1 = min(x0 + 1, W - 1);
    int y1 = min(y0 + 1, H - 1);
    float tx = fx - float(x0);
    float ty = fy - float(y0);
    float v00 = dem[y0 * W + x0];
    float v10 = dem[y0 * W + x1];
    float v01 = dem[y1 * W + x0];
    float v11 = dem[y1 * W + x1];
    float v0  = mix(v00, v10, tx);
    float v1  = mix(v01, v11, tx);
    return mix(v0, v1, ty);
}

kernel void viewshed(
    device const float* dem             [[ buffer(0) ]],
    constant ViewshedParams& p          [[ buffer(1) ]],
    device float* visibility            [[ buffer(2) ]],
    uint2 gid                           [[ thread_position_in_grid ]]
) {
    int x = int(gid.x);
    int y = int(gid.y);
    if (x >= p.width || y >= p.height) { return; }

    int idx = y * p.width + x;

    // Observer sees its own cell.
    if (x == p.observerX && y == p.observerY) {
        visibility[idx] = 1.0;
        return;
    }

    float targetDEM = dem[idx];
    float targetZ   = targetDEM + p.targetHeight;

    // Ray in grid space from observer to target.
    float2 src = float2(float(p.observerX), float(p.observerY));
    float2 dst = float2(float(x), float(y));
    float2 delta = dst - src;
    float dx = delta.x;
    float dy = delta.y;
    float cellsDist = length(delta);
    if (cellsDist < 0.5) {
        visibility[idx] = 1.0;
        return;
    }

    int steps = clamp(int(cellsDist), 2, p.maxSteps);
    float invSteps = 1.0 / float(steps);

    bool blocked = false;
    for (int i = 1; i < steps; ++i) {
        float t = float(i) * invSteps;   // 0..1
        float fx = src.x + dx * t;
        float fy = src.y + dy * t;

        // DEM elevation at this step
        float terrainZ = interpolateDEM(dem, p.width, p.height, fx, fy);

        // LoS altitude: linear between observerElevation and targetZ
        float losZ = mix(p.observerElevation, targetZ, t);

        // Earth-curvature drop at range r = t * cellsDist * cellSize
        float rangeM = t * cellsDist * p.cellSizeMeters;
        float drop   = (rangeM * rangeM) / (2.0 * p.earthRadius);
        float losAdj = losZ - drop;

        if (terrainZ > losAdj) {
            blocked = true;
            break;
        }
    }

    visibility[idx] = blocked ? 0.0 : 1.0;
}
