// MoonPhase.swift — Moon phase, illumination, moonrise/moonset, shadow angle
// Jean Meeus-derived calculations. No internet required.

import Foundation
import CoreLocation
import SwiftUI

// MARK: - MoonPhaseType

enum MoonPhaseType: String, Codable {
    case new            = "New Moon"
    case waxingCrescent = "Waxing Crescent"
    case firstQuarter   = "First Quarter"
    case waxingGibbous  = "Waxing Gibbous"
    case full           = "Full Moon"
    case waningGibbous  = "Waning Gibbous"
    case lastQuarter    = "Last Quarter"
    case waningCrescent = "Waning Crescent"

    var icon: String {
        switch self {
        case .new:             return "moonphase.new.moon"
        case .waxingCrescent:  return "moonphase.waxing.crescent"
        case .firstQuarter:    return "moonphase.first.quarter"
        case .waxingGibbous:   return "moonphase.waxing.gibbous"
        case .full:            return "moonphase.full.moon"
        case .waningGibbous:   return "moonphase.waning.gibbous"
        case .lastQuarter:     return "moonphase.last.quarter"
        case .waningCrescent:  return "moonphase.waning.crescent"
        }
    }
    var color: Color {
        switch self {
        case .new:                       return ZDDesign.mediumGray
        case .waxingCrescent, .waningCrescent: return .yellow.opacity(0.6)
        case .firstQuarter, .lastQuarter: return .yellow
        case .waxingGibbous, .waningGibbous: return .yellow.opacity(0.85)
        case .full:                      return ZDDesign.safetyYellow
        }
    }
}

// MARK: - MoonInfo

struct MoonInfo {
    let date: Date
    let phase: MoonPhaseType
    let agedays: Double              // days into current lunation
    let illumination: Double         // 0.0 – 1.0
    let shadowAngleDeg: Double       // angle of terminator for shadow planning
    let moonrise: Date?
    let moonset: Date?
    let moonNoon: Date?              // transit (highest altitude)
    let altitude: Double?            // current altitude degrees
    let azimuth: Double?             // current azimuth degrees

    var illuminationPercent: Int { Int(illumination * 100) }
    var isGoodForNightOps: Bool { illumination < 0.25 }
}

// MARK: - MoonCalculatorEngine

enum MoonCalculatorEngine {

    // Known new moon: Jan 6, 2000 18:14 UTC → JD 2451550.26
    private static let knownNewMoonJD: Double = 2451550.26
    private static let synodicPeriod: Double = 29.530588861

    static func info(date: Date, latitude: Double, longitude: Double) -> MoonInfo {
        let jd = julianDay(date: date)
        let age = age(jd: jd)
        let phase = phase(age: age)
        let illum = illumination(age: age)
        let shadowAngle = shadowAngle(age: age)
        let pos = position(jd: jd)
        let (rise, set, noon) = riseSetTransit(date: date, lat: latitude, lon: longitude)
        let localAlt = altAz(jd: jd, lat: latitude, lon: longitude)

        return MoonInfo(
            date: date,
            phase: phase,
            agedays: age,
            illumination: illum,
            shadowAngleDeg: shadowAngle,
            moonrise: rise,
            moonset: set,
            moonNoon: noon,
            altitude: localAlt.alt,
            azimuth: localAlt.az
        )
    }

    // MARK: - Phase Age

    static func age(jd: Double) -> Double {
        var a = (jd - knownNewMoonJD).truncatingRemainder(dividingBy: synodicPeriod)
        if a < 0 { a += synodicPeriod }
        return a
    }

    static func phase(age: Double) -> MoonPhaseType {
        let frac = age / synodicPeriod
        switch frac {
        case 0..<0.0339:   return .new
        case 0.0339..<0.25: return .waxingCrescent
        case 0.25..<0.2839: return .firstQuarter
        case 0.2839..<0.50: return .waxingGibbous
        case 0.50..<0.5339: return .full
        case 0.5339..<0.75: return .waningGibbous
        case 0.75..<0.7839: return .lastQuarter
        default:            return .waningCrescent
        }
    }

    static func illumination(age: Double) -> Double {
        let frac = age / synodicPeriod
        return (1.0 - cos(frac * 2 * .pi)) / 2.0
    }

    static func shadowAngle(age: Double) -> Double {
        // Shadow angle: 270° at new (no shadow / dark), 90° at full (shadow toward viewer)
        return age / synodicPeriod * 360.0
    }

    // MARK: - Moon Position (simplified Meeus)

    struct Position { var ra: Double; var dec: Double }

    static func position(jd: Double) -> Position {
        let T = (jd - 2451545.0) / 36525.0
        let D = (297.850 + 445267.111 * T).truncatingRemainder(dividingBy: 360)
        let M  = (357.528 + 35999.050 * T).truncatingRemainder(dividingBy: 360)
        let Mp = (134.963 + 477198.868 * T).truncatingRemainder(dividingBy: 360)
        let F  = (93.272 + 483202.018 * T).truncatingRemainder(dividingBy: 360)
        let DR = D * .pi / 180; let MR = M * .pi / 180
        let MpR = Mp * .pi / 180; let FR = F * .pi / 180

        var lon = 218.316 + 481267.881 * T
        lon += 6.289 * sin(MpR)
        lon -= 1.274 * sin(2 * DR - MpR)
        lon += 0.658 * sin(2 * DR)
        lon -= 0.186 * sin(MR)
        lon -= 0.059 * sin(2 * DR - 2 * MpR)
        lon -= 0.057 * sin(2 * DR - MR - MpR)
        lon += 0.053 * sin(2 * DR + MpR)
        lon += 0.046 * sin(2 * DR - MR)
        lon += 0.041 * sin(MpR - MR)
        lon -= 0.035 * sin(DR)
        lon -= 0.031 * sin(MpR + MR)
        lon -= 0.015 * sin(2 * FR - 2 * DR)
        lon += 0.011 * sin(2 * (DR - MpR))
        lon = lon.truncatingRemainder(dividingBy: 360)

        var lat = 5.128 * sin(FR)
        lat += 0.280 * sin(MpR + FR)
        lat += 0.277 * sin(MpR - FR)
        lat += 0.173 * sin(2 * DR - FR)
        lat += 0.055 * sin(2 * DR - MpR + FR)
        lat -= 0.046 * sin(2 * DR - MpR - FR)
        lat += 0.033 * sin(2 * DR + FR)
        lat += 0.017 * sin(2 * MpR + FR)

        let lonR = lon * .pi / 180; let latR = lat * .pi / 180
        let eps = (23.439 - 0.0000004 * (jd - 2451545.0)) * .pi / 180
        let ra = atan2(sin(lonR) * cos(eps) - tan(latR) * sin(eps), cos(lonR))
        let dec = asin(sin(latR) * cos(eps) + cos(latR) * sin(eps) * sin(lonR))
        return Position(ra: ra, dec: dec)
    }

    // MARK: - Local Altitude + Azimuth

    struct AltAz { var alt: Double; var az: Double }

    static func altAz(jd: Double, lat: Double, lon: Double) -> AltAz {
        let T = (jd - 2451545.0) / 36525.0
        var θ = 280.46061837 + 360.98564736629 * (jd - 2451545.0) + T * T * (0.000387933 - T / 38710000.0)
        θ = θ.truncatingRemainder(dividingBy: 360) * .pi / 180
        let pos = position(jd: jd)
        let ha = θ + lon * .pi / 180 - pos.ra
        let latR = lat * .pi / 180
        let sinAlt = sin(latR) * sin(pos.dec) + cos(latR) * cos(pos.dec) * cos(ha)
        let alt = asin(max(-1, min(1, sinAlt))) * 180 / .pi
        let cosAz = (sin(pos.dec) - sin(latR) * sinAlt) / (cos(latR) * cos(asin(sinAlt)))
        var az = acos(max(-1, min(1, cosAz))) * 180 / .pi
        if sin(ha) > 0 { az = 360 - az }
        return AltAz(alt: alt, az: az)
    }

    // MARK: - Moonrise / Moonset / Transit

    static func riseSetTransit(date: Date, lat: Double, lon: Double) -> (rise: Date?, set: Date?, noon: Date?) {
        let cal = Calendar(identifier: .gregorian)
        let startOfDay = cal.startOfDay(for: date)
        var rise: Date?; var set: Date?; var noon: Date?
        var maxAlt = -90.0; var maxT = startOfDay
        var prevAlt = altAz(jd: julianDay(date: startOfDay), lat: lat, lon: lon).alt
        let step: TimeInterval = 120
        var t = startOfDay.addingTimeInterval(step)
        while t <= startOfDay.addingTimeInterval(86400 + step) {
            let jd = julianDay(date: t)
            let aa = altAz(jd: jd, lat: lat, lon: lon)
            let curr = aa.alt
            if curr > maxAlt { maxAlt = curr; maxT = t }
            let thresh = -0.833
            if prevAlt <= thresh && curr > thresh && rise == nil {
                let frac = (thresh - prevAlt) / (curr - prevAlt)
                rise = t.addingTimeInterval((frac - 1) * step)
            }
            if prevAlt > thresh && curr <= thresh {
                let frac = (thresh - prevAlt) / (curr - prevAlt)
                set = t.addingTimeInterval((frac - 1) * step)
            }
            prevAlt = curr
            t = t.addingTimeInterval(step)
        }
        noon = maxT
        return (rise, set, noon)
    }

    // MARK: - Helpers

    static func julianDay(date: Date) -> Double {
        date.timeIntervalSince1970 / 86400.0 + 2440587.5
    }
}

// MARK: - MoonPhaseService (ObservableObject)

@MainActor
final class MoonPhaseService: ObservableObject {
    static let shared = MoonPhaseService()

    @Published private(set) var info: MoonInfo?

    private init() {
        refresh()
        NotificationCenter.default.addObserver(
            forName: Notification.Name("ZD.locationUpdate"),
            object: nil, queue: .main
        ) { [weak self] _ in Task { @MainActor [weak self] in self?.refresh() } }
    }

    func refresh() {
        let loc = LocationManager.shared.currentLocation
        let lat = loc?.latitude ?? 30.0    // fallback mid-latitude
        let lon = loc?.longitude ?? -97.0
        info = MoonCalculatorEngine.info(date: Date(), latitude: lat, longitude: lon)
    }

    func calculate(date: Date, latitude: Double, longitude: Double) -> MoonInfo {
        MoonCalculatorEngine.info(date: date, latitude: latitude, longitude: longitude)
    }

    // Legacy compatibility properties
    var moonPhase: MoonPhaseType? { info?.phase }
    var illumination: Double { info?.illumination ?? 0 }
    var moonAngle: Double { info?.shadowAngleDeg ?? 0 }
    var moonrise: Date? { info?.moonrise }
    var moonset: Date? { info?.moonset }
}

// MARK: - MoonPhaseView

struct MoonPhaseView: View {
    @ObservedObject private var service = MoonPhaseService.shared
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()
                ScrollView {
                    VStack(spacing: 16) {
                        if let m = service.info {
                            phaseCard(m)
                            timingCard(m)
                            positionCard(m)
                            cycleCard(m)
                        } else {
                            ProgressView().tint(ZDDesign.cyanAccent).padding(40)
                        }
                    }
                    .padding()
                }
            }
            .navigationTitle("Moon Phase")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("Done") { dismiss() } }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { service.refresh() } label: {
                        Image(systemName: "arrow.clockwise").foregroundColor(ZDDesign.cyanAccent)
                    }
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    private func phaseCard(_ m: MoonInfo) -> some View {
        VStack(spacing: 12) {
            HStack(spacing: 16) {
                Image(systemName: m.phase.icon)
                    .font(.system(size: 56))
                    .foregroundColor(m.phase.color)
                VStack(alignment: .leading, spacing: 6) {
                    Text(m.phase.rawValue)
                        .font(.title3.bold()).foregroundColor(ZDDesign.pureWhite)
                    Text(String(format: "%.0f%% illuminated", m.illumination * 100))
                        .font(.subheadline).foregroundColor(m.phase.color)
                    Text(String(format: "Day %.1f of lunation", m.agedays))
                        .font(.caption).foregroundColor(.secondary)
                }
                Spacer()
            }
            // Illumination bar
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 4).fill(ZDDesign.darkCard).frame(height: 8)
                    RoundedRectangle(cornerRadius: 4)
                        .fill(m.phase.color)
                        .frame(width: geo.size.width * CGFloat(m.illumination), height: 8)
                }
            }
            .frame(height: 8)
            if m.isGoodForNightOps {
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.circle.fill").foregroundColor(ZDDesign.successGreen)
                    Text("Good for night operations — low illumination")
                        .font(.caption).foregroundColor(ZDDesign.successGreen)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding()
        .background(ZDDesign.darkCard)
        .cornerRadius(12)
    }

    private func timingCard(_ m: MoonInfo) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("TODAY'S TIMING").font(.caption.bold()).foregroundColor(.secondary)
            HStack(spacing: 0) {
                timingPill(icon: "moon.fill", label: "Moonrise", time: m.moonrise, color: .indigo)
                Spacer()
                timingPill(icon: "sun.max.fill", label: "Transit", time: m.moonNoon, color: .yellow)
                Spacer()
                timingPill(icon: "moon.zzz.fill", label: "Moonset", time: m.moonset, color: .purple)
            }
        }
        .padding()
        .background(ZDDesign.darkCard)
        .cornerRadius(12)
    }

    private func timingPill(icon: String, label: String, time: Date?, color: Color) -> some View {
        VStack(spacing: 4) {
            Image(systemName: icon).foregroundColor(color).font(.title3)
            Text(label).font(.caption2).foregroundColor(.secondary)
            Text(time.map { $0.formatted(date: .omitted, time: .shortened) } ?? "—")
                .font(.caption.bold()).foregroundColor(ZDDesign.pureWhite)
        }
        .frame(minWidth: 80)
    }

    private func positionCard(_ m: MoonInfo) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("CURRENT POSITION").font(.caption.bold()).foregroundColor(.secondary)
            HStack(spacing: 24) {
                if let alt = m.altitude {
                    VStack(spacing: 2) {
                        Text(String(format: "%.1f°", alt))
                            .font(.title3.bold()).foregroundColor(alt > 0 ? ZDDesign.pureWhite : .secondary)
                        Text("Altitude").font(.caption2).foregroundColor(.secondary)
                    }
                }
                if let az = m.azimuth {
                    VStack(spacing: 2) {
                        Text(String(format: "%.0f°", az))
                            .font(.title3.bold()).foregroundColor(ZDDesign.pureWhite)
                        Text("Azimuth").font(.caption2).foregroundColor(.secondary)
                    }
                }
                VStack(spacing: 2) {
                    Text(String(format: "%.0f°", m.shadowAngleDeg))
                        .font(.title3.bold()).foregroundColor(ZDDesign.pureWhite)
                    Text("Shadow Angle").font(.caption2).foregroundColor(.secondary)
                }
            }
            if let alt = m.altitude {
                Text(alt > 0 ? "Moon is above horizon" : "Moon is below horizon")
                    .font(.caption).foregroundColor(alt > 0 ? ZDDesign.successGreen : .secondary)
            }
        }
        .padding()
        .background(ZDDesign.darkCard)
        .cornerRadius(12)
    }

    private func cycleCard(_ m: MoonInfo) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("LUNAR CYCLE").font(.caption.bold()).foregroundColor(.secondary)
            GeometryReader { geo in
                let progress = CGFloat(m.agedays / 29.530588861)
                ZStack(alignment: .leading) {
                    Capsule().fill(ZDDesign.darkCard.opacity(0.6)).frame(height: 20)
                    Capsule().fill(
                        LinearGradient(colors: [.indigo, .yellow, .indigo], startPoint: .leading, endPoint: .trailing)
                    )
                    .frame(width: max(20, geo.size.width * progress), height: 20)
                    HStack {
                        Text("New").font(.system(size: 9)).foregroundColor(.white.opacity(0.7)).padding(.leading, 6)
                        Spacer()
                        Text("Full").font(.system(size: 9)).foregroundColor(.white.opacity(0.7))
                        Spacer()
                        Text("New").font(.system(size: 9)).foregroundColor(.white.opacity(0.7)).padding(.trailing, 6)
                    }
                }
            }
            .frame(height: 20)
            .cornerRadius(10)

            let daysLeft = 29.530588861 - m.agedays
            Text(String(format: "Next new moon in %.1f days", daysLeft))
                .font(.caption2).foregroundColor(.secondary)
        }
        .padding()
        .background(ZDDesign.darkCard)
        .cornerRadius(12)
    }
}
