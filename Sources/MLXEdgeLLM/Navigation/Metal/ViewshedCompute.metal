// ViewshedCompute.metal — GPU viewshed kernel for 360-degree visibility analysis
// Each thread handles one radial direction, marching outward with elevation angle tracking
// Target: <100ms on A17 Pro for 360 radials x 200 samples

#include <metal_stdlib>
using namespace metal;

// MARK: - Uniforms

struct ViewshedUniforms {
    float2 observerLatLon;       // degrees
    float observerElevation;     // meters (terrain + observer height)
    float radius;                // meters
    uint resolution;             // number of radials (e.g. 360)
    uint samplesPerRadial;       // samples per ray (e.g. 200)
    float earthRadius;           // 6371000.0
    uint gridWidth;              // elevation grid width (columns)
    uint gridHeight;             // elevation grid height (rows)
    float2 gridOriginLatLon;     // SW corner of grid, degrees
    float gridCellSize;          // degrees per cell
};

// MARK: - Bilinear Interpolation

float bilinearSample(device const float* grid,
                     float row, float col,
                     uint gridWidth, uint gridHeight) {
    // Clamp to grid bounds
    float r = clamp(row, 0.0f, float(gridHeight - 1));
    float c = clamp(col, 0.0f, float(gridWidth - 1));

    uint r0 = uint(floor(r));
    uint c0 = uint(floor(c));
    uint r1 = min(r0 + 1, gridHeight - 1);
    uint c1 = min(c0 + 1, gridWidth - 1);

    float fr = r - float(r0);
    float fc = c - float(c0);

    float v00 = grid[r0 * gridWidth + c0];
    float v01 = grid[r0 * gridWidth + c1];
    float v10 = grid[r1 * gridWidth + c0];
    float v11 = grid[r1 * gridWidth + c1];

    return v00 * (1.0f - fr) * (1.0f - fc) +
           v01 * (1.0f - fr) * fc +
           v10 * fr * (1.0f - fc) +
           v11 * fr * fc;
}

// MARK: - Viewshed Compute Kernel

kernel void viewshedCompute(
    device const float* elevationGrid [[buffer(0)]],
    device float* visibilityOutput [[buffer(1)]],
    constant ViewshedUniforms& uniforms [[buffer(2)]],
    uint tid [[thread_position_in_grid]]
) {
    if (tid >= uniforms.resolution) return;

    float bearing = float(tid) * (360.0f / float(uniforms.resolution));
    float bearingRad = bearing * M_PI_F / 180.0f;

    float cosB = cos(bearingRad);
    float sinB = sin(bearingRad);

    // Observer lat in radians for longitude scale
    float obsLatRad = uniforms.observerLatLon.x * M_PI_F / 180.0f;
    float cosLat = cos(obsLatRad);

    float maxAngle = -INFINITY;

    for (uint s = 1; s <= uniforms.samplesPerRadial; s++) {
        float dist = uniforms.radius * float(s) / float(uniforms.samplesPerRadial);

        // Compute sample lat/lon (flat earth approximation valid for <5km radius)
        float dN = dist * cosB;  // meters north
        float dE = dist * sinB;  // meters east
        float sampleLat = uniforms.observerLatLon.x + dN / 111320.0f;
        float sampleLon = uniforms.observerLatLon.y + dE / (111320.0f * cosLat);

        // Grid lookup (bilinear interpolation)
        float gridRow = (sampleLat - uniforms.gridOriginLatLon.x) / uniforms.gridCellSize;
        float gridCol = (sampleLon - uniforms.gridOriginLatLon.y) / uniforms.gridCellSize;

        float terrainElev = bilinearSample(elevationGrid, gridRow, gridCol,
                                           uniforms.gridWidth, uniforms.gridHeight);

        // Earth curvature correction: drop = d^2 / (2R)
        float curvatureDrop = (dist * dist) / (2.0f * uniforms.earthRadius);
        float effectiveElev = terrainElev - curvatureDrop;

        // Elevation angle from observer to this point
        float elevAngle = atan2(effectiveElev - uniforms.observerElevation, dist);

        // Visible if this angle exceeds all previous maximum angles along this ray
        uint outputIdx = tid * uniforms.samplesPerRadial + (s - 1);
        if (elevAngle > maxAngle) {
            visibilityOutput[outputIdx] = 1.0f;
            maxAngle = elevAngle;
        } else {
            visibilityOutput[outputIdx] = 0.0f;
        }
    }
}
