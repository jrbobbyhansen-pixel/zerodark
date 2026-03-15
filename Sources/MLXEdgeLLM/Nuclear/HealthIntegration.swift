import Foundation
import HealthKit

// MARK: - Health Integration

/// On-device health data analysis using HealthKit
@MainActor
public final class HealthIntegration: ObservableObject {
    
    public static let shared = HealthIntegration()
    
    // MARK: - State
    
    @Published public var isAvailable: Bool = false
    @Published public var isAuthorized: Bool = false
    @Published public var lastSummary: HealthSummary?
    
    private let healthStore = HKHealthStore()
    
    // MARK: - Types
    
    public struct HealthSummary {
        public let steps: Int
        public let activeCalories: Double
        public let exerciseMinutes: Int
        public let standHours: Int
        public let heartRateAvg: Double?
        public let heartRateResting: Double?
        public let sleepHours: Double?
        public let weight: Double?
        public let date: Date
        
        public var asPromptContext: String {
            var lines: [String] = []
            lines.append("Health Summary for \(date.formatted(date: .abbreviated, time: .omitted)):")
            lines.append("- Steps: \(steps.formatted())")
            lines.append("- Active Calories: \(Int(activeCalories)) kcal")
            lines.append("- Exercise: \(exerciseMinutes) minutes")
            lines.append("- Stand Hours: \(standHours)")
            
            if let hr = heartRateAvg {
                lines.append("- Average Heart Rate: \(Int(hr)) bpm")
            }
            if let rhr = heartRateResting {
                lines.append("- Resting Heart Rate: \(Int(rhr)) bpm")
            }
            if let sleep = sleepHours {
                lines.append("- Sleep: \(String(format: "%.1f", sleep)) hours")
            }
            if let wt = weight {
                lines.append("- Weight: \(String(format: "%.1f", wt)) kg")
            }
            
            return lines.joined(separator: "\n")
        }
    }
    
    public struct WorkoutSummary {
        public let workoutType: String
        public let duration: TimeInterval
        public let calories: Double
        public let distance: Double?
        public let heartRateAvg: Double?
        public let date: Date
    }
    
    // MARK: - Init
    
    private init() {
        isAvailable = HKHealthStore.isHealthDataAvailable()
    }
    
    // MARK: - Authorization
    
    public func requestAuthorization() async throws {
        guard isAvailable else {
            throw HealthError.notAvailable
        }
        
        let readTypes: Set<HKObjectType> = [
            HKQuantityType(.stepCount),
            HKQuantityType(.activeEnergyBurned),
            HKQuantityType(.appleExerciseTime),
            HKQuantityType(.appleStandTime),
            HKQuantityType(.heartRate),
            HKQuantityType(.restingHeartRate),
            HKQuantityType(.bodyMass),
            HKCategoryType(.sleepAnalysis),
            HKWorkoutType.workoutType()
        ]
        
        try await healthStore.requestAuthorization(toShare: [], read: readTypes)
        
        await MainActor.run {
            isAuthorized = true
        }
    }
    
    // MARK: - Fetch Summary
    
    public func fetchTodaySummary() async throws -> HealthSummary {
        guard isAuthorized else {
            throw HealthError.notAuthorized
        }
        
        let calendar = Calendar.current
        let now = Date()
        let startOfDay = calendar.startOfDay(for: now)
        let predicate = HKQuery.predicateForSamples(withStart: startOfDay, end: now)
        
        async let steps = fetchSum(.stepCount, predicate: predicate)
        async let calories = fetchSum(.activeEnergyBurned, predicate: predicate)
        async let exercise = fetchSum(.appleExerciseTime, predicate: predicate)
        async let stand = fetchSum(.appleStandTime, predicate: predicate)
        async let heartRateAvg = fetchAverage(.heartRate, predicate: predicate)
        async let restingHR = fetchLatest(.restingHeartRate)
        async let sleep = fetchSleep(for: now)
        async let weight = fetchLatest(.bodyMass)
        
        let summary = try await HealthSummary(
            steps: Int(steps),
            activeCalories: calories,
            exerciseMinutes: Int(exercise),
            standHours: Int(stand / 60), // Convert minutes to hours
            heartRateAvg: heartRateAvg,
            heartRateResting: restingHR,
            sleepHours: sleep,
            weight: weight,
            date: now
        )
        
        await MainActor.run {
            lastSummary = summary
        }
        
        return summary
    }
    
    // MARK: - Query Helpers
    
    private func fetchSum(_ type: HKQuantityTypeIdentifier, predicate: NSPredicate) async throws -> Double {
        let quantityType = HKQuantityType(type)
        
        return try await withCheckedThrowingContinuation { continuation in
            let query = HKStatisticsQuery(
                quantityType: quantityType,
                quantitySamplePredicate: predicate,
                options: .cumulativeSum
            ) { _, statistics, error in
                if let error = error {
                    continuation.resume(throwing: error)
                    return
                }
                
                let unit: HKUnit
                switch type {
                case .stepCount: unit = .count()
                case .activeEnergyBurned: unit = .kilocalorie()
                case .appleExerciseTime, .appleStandTime: unit = .minute()
                default: unit = .count()
                }
                
                let value = statistics?.sumQuantity()?.doubleValue(for: unit) ?? 0
                continuation.resume(returning: value)
            }
            
            healthStore.execute(query)
        }
    }
    
    private func fetchAverage(_ type: HKQuantityTypeIdentifier, predicate: NSPredicate) async throws -> Double? {
        let quantityType = HKQuantityType(type)
        
        return try await withCheckedThrowingContinuation { continuation in
            let query = HKStatisticsQuery(
                quantityType: quantityType,
                quantitySamplePredicate: predicate,
                options: .discreteAverage
            ) { _, statistics, error in
                if let error = error {
                    continuation.resume(throwing: error)
                    return
                }
                
                let unit: HKUnit
                switch type {
                case .heartRate: unit = HKUnit.count().unitDivided(by: .minute())
                default: unit = .count()
                }
                
                let value = statistics?.averageQuantity()?.doubleValue(for: unit)
                continuation.resume(returning: value)
            }
            
            healthStore.execute(query)
        }
    }
    
    private func fetchLatest(_ type: HKQuantityTypeIdentifier) async throws -> Double? {
        let quantityType = HKQuantityType(type)
        
        return try await withCheckedThrowingContinuation { continuation in
            let sortDescriptor = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: false)
            
            let query = HKSampleQuery(
                sampleType: quantityType,
                predicate: nil,
                limit: 1,
                sortDescriptors: [sortDescriptor]
            ) { _, samples, error in
                if let error = error {
                    continuation.resume(throwing: error)
                    return
                }
                
                guard let sample = samples?.first as? HKQuantitySample else {
                    continuation.resume(returning: nil)
                    return
                }
                
                let unit: HKUnit
                switch type {
                case .bodyMass: unit = .gramUnit(with: .kilo)
                case .restingHeartRate: unit = HKUnit.count().unitDivided(by: .minute())
                default: unit = .count()
                }
                
                let value = sample.quantity.doubleValue(for: unit)
                continuation.resume(returning: value)
            }
            
            healthStore.execute(query)
        }
    }
    
    private func fetchSleep(for date: Date) async throws -> Double? {
        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: date)
        let startOfYesterday = calendar.date(byAdding: .day, value: -1, to: startOfDay)!
        
        let predicate = HKQuery.predicateForSamples(withStart: startOfYesterday, end: startOfDay)
        let sleepType = HKCategoryType(.sleepAnalysis)
        
        return try await withCheckedThrowingContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: sleepType,
                predicate: predicate,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: nil
            ) { _, samples, error in
                if let error = error {
                    continuation.resume(throwing: error)
                    return
                }
                
                guard let sleepSamples = samples as? [HKCategorySample] else {
                    continuation.resume(returning: nil)
                    return
                }
                
                // Sum up asleep time
                var totalSleep: TimeInterval = 0
                for sample in sleepSamples {
                    if sample.value != HKCategoryValueSleepAnalysis.awake.rawValue {
                        totalSleep += sample.endDate.timeIntervalSince(sample.startDate)
                    }
                }
                
                let hours = totalSleep / 3600
                continuation.resume(returning: hours > 0 ? hours : nil)
            }
            
            healthStore.execute(query)
        }
    }
    
    // MARK: - Workouts
    
    public func fetchRecentWorkouts(limit: Int = 10) async throws -> [WorkoutSummary] {
        guard isAuthorized else {
            throw HealthError.notAuthorized
        }
        
        return try await withCheckedThrowingContinuation { continuation in
            let sortDescriptor = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: false)
            
            let query = HKSampleQuery(
                sampleType: HKWorkoutType.workoutType(),
                predicate: nil,
                limit: limit,
                sortDescriptors: [sortDescriptor]
            ) { _, samples, error in
                if let error = error {
                    continuation.resume(throwing: error)
                    return
                }
                
                guard let workouts = samples as? [HKWorkout] else {
                    continuation.resume(returning: [])
                    return
                }
                
                let summaries = workouts.map { workout in
                    WorkoutSummary(
                        workoutType: workout.workoutActivityType.name,
                        duration: workout.duration,
                        calories: workout.totalEnergyBurned?.doubleValue(for: .kilocalorie()) ?? 0,
                        distance: workout.totalDistance?.doubleValue(for: .meter()),
                        heartRateAvg: nil, // Would need separate query
                        date: workout.startDate
                    )
                }
                
                continuation.resume(returning: summaries)
            }
            
            healthStore.execute(query)
        }
    }
    
    // MARK: - Errors
    
    public enum HealthError: Error, LocalizedError {
        case notAvailable
        case notAuthorized
        
        public var errorDescription: String? {
            switch self {
            case .notAvailable: return "HealthKit not available on this device"
            case .notAuthorized: return "HealthKit access not authorized"
            }
        }
    }
}

// MARK: - Workout Type Names

extension HKWorkoutActivityType {
    var name: String {
        switch self {
        case .running: return "Running"
        case .cycling: return "Cycling"
        case .walking: return "Walking"
        case .swimming: return "Swimming"
        case .yoga: return "Yoga"
        case .functionalStrengthTraining: return "Strength Training"
        case .traditionalStrengthTraining: return "Weight Training"
        case .hiking: return "Hiking"
        case .elliptical: return "Elliptical"
        case .rowing: return "Rowing"
        case .stairClimbing: return "Stair Climbing"
        case .highIntensityIntervalTraining: return "HIIT"
        case .dance: return "Dance"
        case .pilates: return "Pilates"
        case .kickboxing: return "Kickboxing"
        case .basketball: return "Basketball"
        case .soccer: return "Soccer"
        case .tennis: return "Tennis"
        case .golf: return "Golf"
        default: return "Workout"
        }
    }
}
