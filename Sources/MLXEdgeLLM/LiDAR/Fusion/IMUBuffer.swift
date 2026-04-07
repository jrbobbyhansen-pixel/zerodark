// IMUBuffer.swift — High-rate IMU ring buffer for Kalman fusion
// Captures accelerometer + gyroscope at 100Hz for EKF prediction steps

import Foundation
import CoreMotion
import simd

// MARK: - IMU Sample

struct IMUSample {
    let timestamp: TimeInterval
    let acceleration: SIMD3<Double>  // m/s^2 (user acceleration + gravity)
    let rotationRate: SIMD3<Double>  // rad/s
    let gravity: SIMD3<Double>       // gravity vector
}

// MARK: - IMUBuffer

final class IMUBuffer: @unchecked Sendable {
    private let motionManager = CMMotionManager()
    private let queue = OperationQueue()
    private var buffer: [IMUSample]
    private var writeIndex: Int = 0
    private let capacity: Int
    private let lock = NSLock()
    private(set) var isRunning = false
    private(set) var sampleCount: Int = 0

    /// Callback fired on each new IMU sample (called on motion queue)
    var onSample: ((IMUSample) -> Void)?

    init(capacity: Int = 1024) {
        self.capacity = capacity
        self.buffer = []
        self.buffer.reserveCapacity(capacity)
        queue.name = "ai.zerodark.imu-buffer"
        queue.maxConcurrentOperationCount = 1
        queue.qualityOfService = .userInitiated
    }

    func start(rate: Double = 100.0) {
        guard motionManager.isDeviceMotionAvailable, !isRunning else { return }

        motionManager.deviceMotionUpdateInterval = 1.0 / rate
        motionManager.startDeviceMotionUpdates(using: .xArbitraryZVertical, to: queue) { [weak self] motion, error in
            guard let self, let motion, error == nil else { return }

            let sample = IMUSample(
                timestamp: motion.timestamp,
                acceleration: SIMD3<Double>(
                    motion.userAcceleration.x + motion.gravity.x,
                    motion.userAcceleration.y + motion.gravity.y,
                    motion.userAcceleration.z + motion.gravity.z
                ),
                rotationRate: SIMD3<Double>(
                    motion.rotationRate.x,
                    motion.rotationRate.y,
                    motion.rotationRate.z
                ),
                gravity: SIMD3<Double>(
                    motion.gravity.x,
                    motion.gravity.y,
                    motion.gravity.z
                )
            )

            self.push(sample)
            self.onSample?(sample)
        }

        isRunning = true
    }

    func stop() {
        motionManager.stopDeviceMotionUpdates()
        isRunning = false
    }

    // MARK: - Ring Buffer Operations

    private func push(_ sample: IMUSample) {
        lock.lock()
        defer { lock.unlock() }

        if buffer.count < capacity {
            buffer.append(sample)
        } else {
            buffer[writeIndex] = sample
        }
        writeIndex = (writeIndex + 1) % capacity
        sampleCount += 1
    }

    /// Returns all samples between two timestamps, ordered chronologically
    func samples(from startTime: TimeInterval, to endTime: TimeInterval) -> [IMUSample] {
        lock.lock()
        defer { lock.unlock() }

        return buffer
            .filter { $0.timestamp >= startTime && $0.timestamp <= endTime }
            .sorted { $0.timestamp < $1.timestamp }
    }

    /// Returns the most recent N samples
    func recentSamples(_ count: Int) -> [IMUSample] {
        lock.lock()
        defer { lock.unlock() }

        let n = min(count, buffer.count)
        if buffer.count < capacity {
            return Array(buffer.suffix(n))
        }

        // Ring buffer is full — reconstruct chronological order
        var result: [IMUSample] = []
        result.reserveCapacity(n)
        for i in 0..<n {
            let idx = (writeIndex - n + i + capacity) % capacity
            result.append(buffer[idx])
        }
        return result
    }

    /// Latest sample timestamp
    var latestTimestamp: TimeInterval? {
        lock.lock()
        defer { lock.unlock() }
        guard !buffer.isEmpty else { return nil }
        let idx = (writeIndex - 1 + capacity) % capacity
        return buffer.count < capacity ? buffer.last?.timestamp : buffer[idx].timestamp
    }

    deinit {
        stop()
    }
}
