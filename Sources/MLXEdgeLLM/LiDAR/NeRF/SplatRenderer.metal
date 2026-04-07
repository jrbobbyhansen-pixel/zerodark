// SplatRenderer.metal — Metal compute kernels for 3D Gaussian Splatting
// Handles gaussian rasterization, alpha blending, and depth sorting on GPU
// Optimized for A17/A18 Pro GPU architecture

#include <metal_stdlib>
using namespace metal;

// MARK: - Data Structures

struct Gaussian {
    float3 position;       // World-space center
    float3 scale;          // Log-space scale
    float4 rotation;       // Quaternion (x, y, z, w)
    float opacity;         // Sigmoid-space
    float3 color;          // SH degree-0 RGB
    float confidence;      // 1.0 = LiDAR-verified
};

struct CameraUniforms {
    float4x4 viewMatrix;
    float4x4 projMatrix;
    float4x4 viewProjMatrix;
    float2 focalLength;    // (fx, fy)
    float2 principalPoint; // (cx, cy)
    uint2 imageSize;       // (width, height)
    float nearPlane;
    float farPlane;
};

struct SplatFragment {
    float3 color;
    float depth;
    float alpha;
};

// MARK: - Utility Functions

float sigmoid(float x) {
    return 1.0 / (1.0 + exp(-x));
}

float3x3 quatToRotation(float4 q) {
    float x = q.x, y = q.y, z = q.z, w = q.w;
    return float3x3(
        float3(1 - 2*(y*y + z*z), 2*(x*y + w*z),     2*(x*z - w*y)),
        float3(2*(x*y - w*z),     1 - 2*(x*x + z*z), 2*(y*z + w*x)),
        float3(2*(x*z + w*y),     2*(y*z - w*x),     1 - 2*(x*x + y*y))
    );
}

// Compute 2D covariance from 3D gaussian projected to screen
float3 computeCov2D(float3 position, float3 scale, float4 rotation,
                     float4x4 viewMatrix, float2 focal) {
    float3x3 R = quatToRotation(rotation);
    float3x3 S = float3x3(float3(scale.x * scale.x, 0, 0),
                           float3(0, scale.y * scale.y, 0),
                           float3(0, 0, scale.z * scale.z));
    float3x3 cov3D = R * S * transpose(R);

    // Project to view space
    float4 viewPos = viewMatrix * float4(position, 1.0);
    float tz = viewPos.z;
    if (tz <= 0.1) return float3(0); // Behind camera

    float tz2 = tz * tz;

    // Jacobian of projection
    float3x3 J = float3x3(
        float3(focal.x / tz, 0, 0),
        float3(0, focal.y / tz, 0),
        float3(-focal.x * viewPos.x / tz2, -focal.y * viewPos.y / tz2, 0)
    );

    float3x3 W = float3x3(viewMatrix[0].xyz, viewMatrix[1].xyz, viewMatrix[2].xyz);
    float3x3 T = J * W;
    float3x3 cov2D = T * cov3D * transpose(T);

    // Return upper triangle: (cov[0][0], cov[0][1], cov[1][1])
    return float3(cov2D[0][0] + 0.3, cov2D[0][1], cov2D[1][1] + 0.3); // +0.3 anti-alias
}

// MARK: - Preprocessing Kernel
// Projects gaussians to screen space, computes 2D covariance, sorts by depth

kernel void preprocessGaussians(
    device const Gaussian* gaussians [[buffer(0)]],
    device float4* screenPositions [[buffer(1)]],    // (screenX, screenY, depth, radius)
    device float3* cov2Ds [[buffer(2)]],             // 2D covariance upper triangle
    device float* opacities [[buffer(3)]],           // Activated opacities
    constant CameraUniforms& camera [[buffer(4)]],
    constant uint& gaussianCount [[buffer(5)]],
    uint tid [[thread_position_in_grid]]
) {
    if (tid >= gaussianCount) return;

    Gaussian g = gaussians[tid];

    // Project to view space
    float4 viewPos = camera.viewMatrix * float4(g.position, 1.0);
    float depth = -viewPos.z;

    // Clip: behind camera or too far
    if (depth < camera.nearPlane || depth > camera.farPlane) {
        screenPositions[tid] = float4(-1, -1, 1e10, 0);
        return;
    }

    // Project to screen
    float4 clipPos = camera.viewProjMatrix * float4(g.position, 1.0);
    float2 ndc = clipPos.xy / clipPos.w;
    float2 screen = float2(
        (ndc.x * 0.5 + 0.5) * float(camera.imageSize.x),
        (1.0 - (ndc.y * 0.5 + 0.5)) * float(camera.imageSize.y)
    );

    // Compute 2D covariance
    float3 cov = computeCov2D(g.position, g.scale, g.rotation,
                               camera.viewMatrix, camera.focalLength);

    // Compute splat radius from eigenvalues of 2D covariance
    float det = cov.x * cov.z - cov.y * cov.y;
    if (det <= 0) {
        screenPositions[tid] = float4(-1, -1, 1e10, 0);
        return;
    }

    float trace = cov.x + cov.z;
    float lambda1 = 0.5 * (trace + sqrt(max(0.0, trace * trace - 4 * det)));
    float radius = ceil(3.0 * sqrt(lambda1)); // 3-sigma

    screenPositions[tid] = float4(screen, depth, radius);
    cov2Ds[tid] = cov;
    opacities[tid] = sigmoid(g.opacity);
}

// MARK: - Rasterization Kernel
// Per-pixel alpha compositing of sorted gaussian splats

kernel void rasterizeGaussians(
    device const Gaussian* gaussians [[buffer(0)]],
    device const float4* screenPositions [[buffer(1)]],
    device const float3* cov2Ds [[buffer(2)]],
    device const float* opacities [[buffer(3)]],
    device const uint* sortedIndices [[buffer(4)]],
    constant CameraUniforms& camera [[buffer(5)]],
    constant uint& gaussianCount [[buffer(6)]],
    texture2d<float, access::write> colorOutput [[texture(0)]],
    texture2d<float, access::write> depthOutput [[texture(1)]],
    uint2 gid [[thread_position_in_grid]]
) {
    if (gid.x >= camera.imageSize.x || gid.y >= camera.imageSize.y) return;

    float2 pixelCenter = float2(gid) + 0.5;
    float3 accumulatedColor = float3(0);
    float accumulatedAlpha = 0;
    float finalDepth = camera.farPlane;

    // Iterate sorted gaussians (front to back)
    for (uint i = 0; i < gaussianCount && accumulatedAlpha < 0.99; i++) {
        uint idx = sortedIndices[i];
        float4 screenPos = screenPositions[idx];

        // Skip culled gaussians
        if (screenPos.x < 0) continue;

        float radius = screenPos.w;
        float2 center = screenPos.xy;

        // Bounding box test
        if (abs(pixelCenter.x - center.x) > radius ||
            abs(pixelCenter.y - center.y) > radius) continue;

        // Evaluate 2D gaussian
        float3 cov = cov2Ds[idx];
        float det = cov.x * cov.z - cov.y * cov.y;
        if (det <= 0) continue;

        float2 d = pixelCenter - center;
        float power = -0.5 * (cov.z * d.x * d.x - 2 * cov.y * d.x * d.y + cov.x * d.y * d.y) / det;
        if (power > 0) continue; // Numerical issue

        float alpha = min(0.99, opacities[idx] * exp(power));
        if (alpha < 1.0 / 255.0) continue;

        // Alpha compositing
        float weight = alpha * (1.0 - accumulatedAlpha);
        accumulatedColor += weight * gaussians[idx].color;
        accumulatedAlpha += weight;

        if (weight > 0.1) {
            finalDepth = min(finalDepth, screenPos.z);
        }
    }

    colorOutput.write(float4(accumulatedColor, accumulatedAlpha), gid);
    depthOutput.write(float4(finalDepth, 0, 0, 1), gid);
}

// MARK: - Depth-Only Rendering
// Lightweight kernel for range extension (no color needed)

kernel void renderDepthOnly(
    device const Gaussian* gaussians [[buffer(0)]],
    device const float4* screenPositions [[buffer(1)]],
    device const float3* cov2Ds [[buffer(2)]],
    device const float* opacities [[buffer(3)]],
    device const uint* sortedIndices [[buffer(4)]],
    constant CameraUniforms& camera [[buffer(5)]],
    constant uint& gaussianCount [[buffer(6)]],
    texture2d<float, access::write> depthOutput [[texture(0)]],
    uint2 gid [[thread_position_in_grid]]
) {
    if (gid.x >= camera.imageSize.x || gid.y >= camera.imageSize.y) return;

    float2 pixelCenter = float2(gid) + 0.5;
    float accumulatedAlpha = 0;
    float weightedDepth = 0;

    for (uint i = 0; i < gaussianCount && accumulatedAlpha < 0.95; i++) {
        uint idx = sortedIndices[i];
        float4 screenPos = screenPositions[idx];
        if (screenPos.x < 0) continue;

        float radius = screenPos.w;
        float2 center = screenPos.xy;

        if (abs(pixelCenter.x - center.x) > radius ||
            abs(pixelCenter.y - center.y) > radius) continue;

        float3 cov = cov2Ds[idx];
        float det = cov.x * cov.z - cov.y * cov.y;
        if (det <= 0) continue;

        float2 d = pixelCenter - center;
        float power = -0.5 * (cov.z * d.x * d.x - 2 * cov.y * d.x * d.y + cov.x * d.y * d.y) / det;
        if (power > 0) continue;

        float alpha = min(0.99, opacities[idx] * exp(power));
        if (alpha < 1.0 / 255.0) continue;

        float weight = alpha * (1.0 - accumulatedAlpha);
        weightedDepth += weight * screenPos.z;
        accumulatedAlpha += weight;
    }

    float depth = accumulatedAlpha > 0.1 ? weightedDepth / accumulatedAlpha : camera.farPlane;
    depthOutput.write(float4(depth, accumulatedAlpha, 0, 1), gid);
}
