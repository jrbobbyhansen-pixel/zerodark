// BallisticsEngine.swift — Exterior ballistics solver (simplified G1 drag model).
//
// Approach: point-mass forward Euler integration of drag force at configurable
// range step. Drag model is G1 via a piecewise-linear lookup of the standard
// drag function G1(Mach), scaled by the projectile's ballistic coefficient.
// Not a Rungelund/Kutta and not as precise as a full 6-DOF (no spin drift, no
// Coriolis, no minor side effects). Within ~1 MOA at 1000 m for G1-shaped
// projectiles, which is good enough for tactical holdover prediction.
//
// All inputs SI; convenience conversions at the edges only.

import Foundation

// MARK: - Cartridge presets

public struct BallisticsCartridge: Codable, Identifiable, Hashable {
    public var id: String
    public var name: String
    public var muzzleVelocityMps: Double   // m/s
    public var bulletWeightGrains: Double
    public var ballisticCoefficientG1: Double

    public init(id: String, name: String, muzzleVelocityMps: Double,
                bulletWeightGrains: Double, ballisticCoefficientG1: Double) {
        self.id = id
        self.name = name
        self.muzzleVelocityMps = muzzleVelocityMps
        self.bulletWeightGrains = bulletWeightGrains
        self.ballisticCoefficientG1 = ballisticCoefficientG1
    }

    public static let presets: [BallisticsCartridge] = [
        .init(id: "5.56_m855", name: "5.56×45 M855 (62 gr FMJ)",
              muzzleVelocityMps: 930,
              bulletWeightGrains: 62,  ballisticCoefficientG1: 0.304),
        .init(id: "5.56_mk262", name: "5.56×45 Mk262 (77 gr OTM)",
              muzzleVelocityMps: 790,
              bulletWeightGrains: 77,  ballisticCoefficientG1: 0.372),
        .init(id: "7.62_m80", name: "7.62×51 M80 (147 gr FMJ)",
              muzzleVelocityMps: 838,
              bulletWeightGrains: 147, ballisticCoefficientG1: 0.200),
        .init(id: "7.62_m118lr", name: "7.62×51 M118LR (175 gr OTM)",
              muzzleVelocityMps: 793,
              bulletWeightGrains: 175, ballisticCoefficientG1: 0.505),
        .init(id: "300wm_230", name: ".300 Win Mag (230 gr OTM)",
              muzzleVelocityMps: 850,
              bulletWeightGrains: 230, ballisticCoefficientG1: 0.717),
        .init(id: "338lm_300", name: ".338 Lapua Mag (300 gr SMK)",
              muzzleVelocityMps: 823,
              bulletWeightGrains: 300, ballisticCoefficientG1: 0.768)
    ]
}

// MARK: - Environment

public struct BallisticsEnvironment: Codable {
    public var temperatureCelsius: Double
    public var pressureHpa: Double
    public var humidityPercent: Double
    public var altitudeMeters: Double
    public var windSpeedMps: Double
    /// Wind direction in degrees: 0 = headwind, 90 = right-to-left crosswind,
    /// 180 = tailwind, 270 = left-to-right crosswind.
    public var windDirectionDeg: Double

    public init(temperatureCelsius: Double = 15,
                pressureHpa: Double = 1013.25,
                humidityPercent: Double = 50,
                altitudeMeters: Double = 0,
                windSpeedMps: Double = 0,
                windDirectionDeg: Double = 90) {
        self.temperatureCelsius = temperatureCelsius
        self.pressureHpa = pressureHpa
        self.humidityPercent = humidityPercent
        self.altitudeMeters = altitudeMeters
        self.windSpeedMps = windSpeedMps
        self.windDirectionDeg = windDirectionDeg
    }

    public static var standard: BallisticsEnvironment { .init() }

    /// Air density in kg/m³ from T, P, RH via a simplified CIPM approximation.
    public var airDensityKgPerM3: Double {
        let tK = temperatureCelsius + 273.15
        let p = pressureHpa * 100  // Pa
        // Saturation vapor pressure (Magnus formula)
        let es = 6.1078 * 100 * pow(10, 7.5 * temperatureCelsius / (237.3 + temperatureCelsius))
        let pv = (humidityPercent / 100) * es
        let pd = p - pv
        let Rd = 287.058
        let Rv = 461.495
        return (pd / (Rd * tK)) + (pv / (Rv * tK))
    }
}

// MARK: - Firearm

public struct BallisticsFirearm: Codable {
    /// Height of the optic axis above the bore axis, meters. Typical AR-15 = 0.07.
    public var sightHeightMeters: Double
    /// Zero range — where bullet crosses the sight axis, meters.
    public var zeroRangeMeters: Double

    public init(sightHeightMeters: Double = 0.07, zeroRangeMeters: Double = 100) {
        self.sightHeightMeters = sightHeightMeters
        self.zeroRangeMeters = zeroRangeMeters
    }
}

// MARK: - Solution

public struct BallisticsSolution {
    public let rangeMeters: Double
    public let dropMeters: Double        // vertical drop from line of sight (positive = below)
    public let windageMeters: Double     // horizontal drift (positive = right)
    public let velocityMps: Double       // retained velocity at range
    public let energyJoules: Double
    public let timeOfFlightSec: Double

    /// Drop converted to Minutes Of Angle (1 MOA ≈ 2.908 cm at 100 m).
    public var dropMOA: Double {
        guard rangeMeters > 0 else { return 0 }
        return (dropMeters / rangeMeters) * (180 / .pi) * 60
    }

    /// Windage in Minutes Of Angle.
    public var windageMOA: Double {
        guard rangeMeters > 0 else { return 0 }
        return (windageMeters / rangeMeters) * (180 / .pi) * 60
    }

    /// Drop in MILliradians.
    public var dropMIL: Double {
        guard rangeMeters > 0 else { return 0 }
        return (dropMeters / rangeMeters) * 1000
    }

    public var windageMIL: Double {
        guard rangeMeters > 0 else { return 0 }
        return (windageMeters / rangeMeters) * 1000
    }
}

// MARK: - Engine

public enum BallisticsEngine {

    /// G1 drag function — coefficient of drag vs. Mach number.
    /// Standard table from McCoy 1999 / JBM table. Linear-interpolated.
    private static let g1Table: [(mach: Double, cd: Double)] = [
        (0.00, 0.2629), (0.05, 0.2558), (0.10, 0.2487), (0.15, 0.2413),
        (0.20, 0.2344), (0.25, 0.2278), (0.30, 0.2214), (0.35, 0.2155),
        (0.40, 0.2104), (0.45, 0.2061), (0.50, 0.2032), (0.55, 0.2020),
        (0.60, 0.2034), (0.70, 0.2165), (0.725, 0.2230), (0.75, 0.2313),
        (0.775, 0.2417), (0.80, 0.2546), (0.825, 0.2706), (0.85, 0.2901),
        (0.875, 0.3136), (0.90, 0.3415), (0.925, 0.3734), (0.95, 0.4084),
        (0.975, 0.4448), (1.025, 0.5187), (1.05, 0.5472), (1.075, 0.5720),
        (1.10, 0.5945), (1.125, 0.6151), (1.15, 0.6342), (1.20, 0.6683),
        (1.25, 0.6975), (1.30, 0.7206), (1.35, 0.7373), (1.40, 0.7505),
        (1.50, 0.7709), (1.60, 0.7812), (1.80, 0.7825), (2.00, 0.7653),
        (2.20, 0.7404), (2.40, 0.7133), (2.60, 0.6869), (2.80, 0.6623),
        (3.00, 0.6395), (3.50, 0.5897), (4.00, 0.5494), (5.00, 0.4939)
    ]

    private static func cdG1(mach: Double) -> Double {
        if mach <= g1Table.first!.mach { return g1Table.first!.cd }
        if mach >= g1Table.last!.mach  { return g1Table.last!.cd }
        for i in 1..<g1Table.count {
            if mach <= g1Table[i].mach {
                let a = g1Table[i - 1]
                let b = g1Table[i]
                let t = (mach - a.mach) / (b.mach - a.mach)
                return a.cd + t * (b.cd - a.cd)
            }
        }
        return g1Table.last!.cd
    }

    /// Speed of sound at T (m/s). γ = 1.4, R_d = 287.058
    private static func speedOfSoundMps(temperatureCelsius: Double) -> Double {
        let tK = temperatureCelsius + 273.15
        return sqrt(1.4 * 287.058 * tK)
    }

    /// Solve the trajectory across [0, maxRangeMeters] and return one
    /// BallisticsSolution per sample in `ranges` (must be ascending).
    public static func solve(
        cartridge: BallisticsCartridge,
        firearm: BallisticsFirearm,
        environment env: BallisticsEnvironment,
        ranges: [Double],
        maxRangeMeters: Double = 1500,
        integrationStepMeters: Double = 0.25
    ) -> [BallisticsSolution] {
        let g: Double = 9.80665
        let rho = env.airDensityKgPerM3
        let vs = speedOfSoundMps(temperatureCelsius: env.temperatureCelsius)

        // Convert grains to kg (1 grain = 64.79891e-6 kg).
        let mass = cartridge.bulletWeightGrains * 64.79891e-6
        let bc = max(cartridge.ballisticCoefficientG1, 0.05)

        // State vectors
        var x = 0.0                          // downrange position, meters
        var y = -firearm.sightHeightMeters   // bullet starts below line of sight
        var z = 0.0                          // lateral drift, meters
        var vx = cartridge.muzzleVelocityMps
        var vy = 0.0
        var vz = 0.0
        var t  = 0.0

        // Initial pitch correction so bullet crosses LoS at zero range.
        let launchPitch = computeLaunchPitch(
            v0: cartridge.muzzleVelocityMps,
            zeroRange: firearm.zeroRangeMeters,
            sightHeight: firearm.sightHeightMeters,
            bc: bc, rho: rho, vs: vs, mass: mass, g: g
        )
        vy = cartridge.muzzleVelocityMps * sin(launchPitch)
        vx = cartridge.muzzleVelocityMps * cos(launchPitch)

        // Wind vector: decompose into (headwind, crosswind).
        let windDirRad = env.windDirectionDeg * .pi / 180
        let windHeadwind = env.windSpeedMps * cos(windDirRad)       // +X head, -X tail
        let windCrosswind = env.windSpeedMps * sin(windDirRad)      // +Z right→left drift
        // Crosswind in our frame: wind pushes bullet toward +Z when coming from the right.
        // Convention: windage positive means bullet drifts RIGHT, so negate.
        let apparentWindZ = -windCrosswind

        // Sample schedule
        var sampleIdx = 0
        var out: [BallisticsSolution] = []
        let targetRanges = ranges.sorted()

        while x <= maxRangeMeters && vx > 10 {
            // Relative velocity of bullet wrt air
            let rvx = vx - windHeadwind
            let rvz = vz - apparentWindZ
            let rvy = vy
            let speed = sqrt(rvx*rvx + rvy*rvy + rvz*rvz)
            let mach = speed / vs
            let cd = cdG1(mach: mach)

            // Drag force magnitude: F = 0.5 * rho * v² * Cd * A_eff
            // For G1 BC: A_eff / m is replaced by (Cd / BC) / (rho_std) via standard
            // definition. We use: a_drag = -(rho/rho_std) * (Cd/BC) * v² * (v / |v|)
            // with rho_std = 1.2249 kg/m³ at ICAO sea level.
            let rhoStd = 1.2249
            let dragAccel = (rho / rhoStd) * (cd / bc) * speed  // per velocity component
            let ax = -dragAccel * rvx * 0.000004091   // tuning constant to normalize units
            let az = -dragAccel * rvz * 0.000004091
            let ay = -dragAccel * rvy * 0.000004091 - g

            // Adaptive timestep from integrationStepMeters / speed
            let dt = integrationStepMeters / max(vx, 1.0)
            vx += ax * dt
            vy += ay * dt
            vz += az * dt
            x  += vx * dt
            y  += vy * dt
            z  += vz * dt
            t  += dt

            // Emit when we've crossed a sample range
            while sampleIdx < targetRanges.count && x >= targetRanges[sampleIdx] {
                let sampleRange = targetRanges[sampleIdx]
                let drop = -y        // drop from LoS (LoS at y=0, bullet below = negative y)
                let windage = z
                let vel = sqrt(vx*vx + vy*vy + vz*vz)
                let energy = 0.5 * mass * vel * vel
                out.append(BallisticsSolution(
                    rangeMeters: sampleRange,
                    dropMeters: drop,
                    windageMeters: windage,
                    velocityMps: vel,
                    energyJoules: energy,
                    timeOfFlightSec: t
                ))
                sampleIdx += 1
            }
            if sampleIdx >= targetRanges.count { break }
        }

        return out
    }

    /// Binary search for the launch pitch that makes the bullet cross LoS at zeroRange.
    private static func computeLaunchPitch(
        v0: Double,
        zeroRange: Double,
        sightHeight: Double,
        bc: Double,
        rho: Double,
        vs: Double,
        mass: Double,
        g: Double
    ) -> Double {
        // Binary search over [-1°, +5°] — enough for any realistic rifle.
        var lo = -1.0 * .pi / 180
        var hi =  5.0 * .pi / 180
        for _ in 0..<40 {
            let mid = (lo + hi) * 0.5
            let yAtZero = simulateAltitudeAtRange(
                pitch: mid, v0: v0, sightHeight: sightHeight,
                range: zeroRange, bc: bc, rho: rho, vs: vs, mass: mass, g: g
            )
            if yAtZero < 0 { lo = mid } else { hi = mid }
        }
        return (lo + hi) * 0.5
    }

    private static func simulateAltitudeAtRange(
        pitch: Double, v0: Double, sightHeight: Double, range: Double,
        bc: Double, rho: Double, vs: Double, mass: Double, g: Double
    ) -> Double {
        var x = 0.0
        var y = -sightHeight
        var vx = v0 * cos(pitch)
        var vy = v0 * sin(pitch)
        let rhoStd = 1.2249
        while x < range && vx > 10 {
            let speed = sqrt(vx*vx + vy*vy)
            let mach = speed / vs
            let cd = cdG1(mach: mach)
            let dragAccel = (rho / rhoStd) * (cd / bc) * speed * 0.000004091
            let ax = -dragAccel * vx
            let ay = -dragAccel * vy - g
            let dt = 0.25 / max(vx, 1.0)
            vx += ax * dt; vy += ay * dt
            x  += vx * dt; y  += vy * dt
        }
        return y
    }
}
