// SunCalculator.swift — Sunrise/sunset, civil/nautical/astronomical twilight, golden hour
// Jean Meeus-derived USNO-compatible solar position algorithm. No internet required.

import Foundation
import CoreLocation
import SwiftUI

// MARK: - SunTimes

struct SunTimes {
    let date: Date
    let latitude: Double
    let longitude: Double

    let sunrise: Date?
    let sunset: Date?
    let solarNoon: Date?
    let civilDawn: Date?       // -6°
    let civilDusk: Date?       // -6°
    let nauticalDawn: Date?    // -12°
    let nauticalDusk: Date?    // -12°
    let astronomicalDawn: Date? // -18°
    let astronomicalDusk: Date? // -18°
    let goldenHourBegin: Date?  // +6° rising
    let goldenHourEnd: Date?    // +6° setting
    let dayLength: TimeInterval?

    init(date: Date, latitude: Double, longitude: Double) {
        self.date = date
        self.latitude = latitude
        self.longitude = longitude
        let results = SunCalculatorEngine.calculate(date: date, lat: latitude, lon: longitude)
        sunrise = results.sunrise
        sunset = results.sunset
        solarNoon = results.solarNoon
        civilDawn = results.civilDawn
        civilDusk = results.civilDusk
        nauticalDawn = results.nauticalDawn
        nauticalDusk = results.nauticalDusk
        astronomicalDawn = results.astronomicalDawn
        astronomicalDusk = results.astronomicalDusk
        goldenHourBegin = results.goldenHourBegin
        goldenHourEnd = results.goldenHourEnd
        if let sr = sunrise, let ss = sunset { dayLength = ss.timeIntervalSince(sr) } else { dayLength = nil }
    }
}

// MARK: - SunCalculatorEngine

enum SunCalculatorEngine {
    struct Results {
        var sunrise: Date?; var sunset: Date?; var solarNoon: Date?
        var civilDawn: Date?; var civilDusk: Date?
        var nauticalDawn: Date?; var nauticalDusk: Date?
        var astronomicalDawn: Date?; var astronomicalDusk: Date?
        var goldenHourBegin: Date?; var goldenHourEnd: Date?
    }

    /// Scan day in 2-minute steps, detect altitude crossings for all events.
    static func calculate(date: Date, lat: Double, lon: Double) -> Results {
        let cal = Calendar(identifier: .gregorian)
        let startOfDay = cal.startOfDay(for: date)
        var r = Results()
        var prevAlt = altitude(at: startOfDay, lat: lat, lon: lon)
        var maxAlt = prevAlt
        var maxT = startOfDay

        let step: TimeInterval = 60
        var t = startOfDay.addingTimeInterval(step)
        while t <= startOfDay.addingTimeInterval(86400) {
            let alt = altitude(at: t, lat: lat, lon: lon)
            let prev = prevAlt

            // Solar noon (max altitude)
            if alt > maxAlt { maxAlt = alt; maxT = t }

            cross(prev, alt, threshold: -0.833, rising: true,  t: t, step: step) { r.sunrise = $0 }
            cross(prev, alt, threshold: -0.833, rising: false, t: t, step: step) { r.sunset = $0 }
            cross(prev, alt, threshold: -6.0,   rising: true,  t: t, step: step) { r.civilDawn = $0 }
            cross(prev, alt, threshold: -6.0,   rising: false, t: t, step: step) { r.civilDusk = $0 }
            cross(prev, alt, threshold: -12.0,  rising: true,  t: t, step: step) { r.nauticalDawn = $0 }
            cross(prev, alt, threshold: -12.0,  rising: false, t: t, step: step) { r.nauticalDusk = $0 }
            cross(prev, alt, threshold: -18.0,  rising: true,  t: t, step: step) { r.astronomicalDawn = $0 }
            cross(prev, alt, threshold: -18.0,  rising: false, t: t, step: step) { r.astronomicalDusk = $0 }
            cross(prev, alt, threshold: 6.0,    rising: true,  t: t, step: step) { r.goldenHourBegin = $0 }
            cross(prev, alt, threshold: 6.0,    rising: false, t: t, step: step) { r.goldenHourEnd = $0 }

            prevAlt = alt
            t = t.addingTimeInterval(step)
        }
        r.solarNoon = maxT
        return r
    }

    /// Interpolate crossing time for a threshold.
    private static func cross(
        _ prev: Double, _ curr: Double, threshold: Double,
        rising: Bool, t: Date, step: TimeInterval,
        assign: (Date) -> Void
    ) {
        guard rising ? (prev <= threshold && curr > threshold) : (prev > threshold && curr <= threshold) else { return }
        let frac = (threshold - prev) / (curr - prev)
        assign(t.addingTimeInterval((frac - 1) * step))
    }

    // MARK: - Solar Altitude (USNO simplified Meeus)

    static func altitude(at date: Date, lat: Double, lon: Double) -> Double {
        let jd = julianDay(date: date)
        let n = jd - 2451545.0   // days from J2000.0

        // Mean longitude and mean anomaly
        let L = (280.460 + 0.9856474 * n).truncatingRemainder(dividingBy: 360)
        let g = (357.528 + 0.9856003 * n).truncatingRemainder(dividingBy: 360)
        let gR = g * .pi / 180

        // Ecliptic longitude
        let lambda = L + 1.915 * sin(gR) + 0.020 * sin(2 * gR)
        let lambdaR = lambda * .pi / 180

        // Obliquity of ecliptic
        let eps = (23.439 - 0.0000004 * n) * .pi / 180

        // Right ascension and declination
        var ra = atan2(cos(eps) * sin(lambdaR), cos(lambdaR))
        if ra < 0 { ra += 2 * .pi }
        let dec = asin(sin(eps) * sin(lambdaR))

        // Greenwich Sidereal Time → Local Hour Angle
        let ut = gmst(jd: jd)
        let ha = ut + lon * .pi / 180 - ra

        // Altitude
        let latR = lat * .pi / 180
        let sinAlt = sin(latR) * sin(dec) + cos(latR) * cos(dec) * cos(ha)
        return asin(max(-1, min(1, sinAlt))) * 180 / .pi
    }

    private static func julianDay(date: Date) -> Double {
        date.timeIntervalSince1970 / 86400.0 + 2440587.5
    }

    private static func gmst(jd: Double) -> Double {
        let T = (jd - 2451545.0) / 36525.0
        var θ = 280.46061837 + 360.98564736629 * (jd - 2451545.0) + T * T * (0.000387933 - T / 38710000.0)
        θ = θ.truncatingRemainder(dividingBy: 360)
        return θ * .pi / 180
    }
}

// MARK: - SunCalculator (ObservableObject)

@MainActor
final class SunCalculator: ObservableObject {
    static let shared = SunCalculator()

    @Published private(set) var todayTimes: SunTimes?
    @Published private(set) var tomorrowTimes: SunTimes?

    private init() {
        refresh()
        NotificationCenter.default.addObserver(
            forName: Notification.Name("ZD.locationUpdate"),
            object: nil, queue: .main
        ) { [weak self] _ in Task { @MainActor [weak self] in self?.refresh() } }
    }

    func refresh() {
        guard let loc = LocationManager.shared.currentLocation else { return }
        let now = Date()
        todayTimes = SunTimes(date: now, latitude: loc.latitude, longitude: loc.longitude)
        let tomorrow = now.addingTimeInterval(86400)
        tomorrowTimes = SunTimes(date: tomorrow, latitude: loc.latitude, longitude: loc.longitude)
    }

    /// Calculate sun times for an arbitrary date + location.
    func calculate(date: Date, latitude: Double, longitude: Double) -> SunTimes {
        SunTimes(date: date, latitude: latitude, longitude: longitude)
    }

    var currentAltitude: Double? {
        guard let loc = LocationManager.shared.currentLocation else { return nil }
        return SunCalculatorEngine.altitude(at: Date(), lat: loc.latitude, lon: loc.longitude)
    }
}

// MARK: - SunCalculatorView

struct SunCalculatorView: View {
    @ObservedObject private var calc = SunCalculator.shared
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()
                ScrollView {
                    VStack(spacing: 16) {
                        if let t = calc.todayTimes {
                            dayCard(title: "TODAY", times: t)
                        } else {
                            noLocationCard
                        }
                        if let t = calc.tomorrowTimes {
                            dayCard(title: "TOMORROW", times: t)
                        }
                        altCard
                    }
                    .padding()
                }
            }
            .navigationTitle("Sun Calculator")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("Done") { dismiss() } }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { calc.refresh() } label: {
                        Image(systemName: "arrow.clockwise").foregroundColor(ZDDesign.cyanAccent)
                    }
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    private var noLocationCard: some View {
        VStack(spacing: 8) {
            Image(systemName: "location.slash").font(.title).foregroundColor(.secondary)
            Text("Location required").font(.subheadline).foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity).padding(30)
        .background(ZDDesign.darkCard).cornerRadius(12)
    }

    private func dayCard(title: String, times: SunTimes) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title).font(.caption.bold()).foregroundColor(.secondary)

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                sunRow(icon: "sunrise.fill",  label: "Sunrise",          time: times.sunrise,            color: .orange)
                sunRow(icon: "sunset.fill",   label: "Sunset",           time: times.sunset,             color: .orange)
                sunRow(icon: "sun.max.fill",  label: "Solar Noon",       time: times.solarNoon,          color: ZDDesign.safetyYellow)
                dayLengthRow(seconds: times.dayLength)
                sunRow(icon: "sun.horizon.fill", label: "Civil Dawn",    time: times.civilDawn,          color: ZDDesign.cyanAccent)
                sunRow(icon: "sun.horizon.fill", label: "Civil Dusk",    time: times.civilDusk,          color: ZDDesign.cyanAccent)
                sunRow(icon: "moon.stars.fill",  label: "Naut Dawn",     time: times.nauticalDawn,       color: .indigo)
                sunRow(icon: "moon.stars.fill",  label: "Naut Dusk",     time: times.nauticalDusk,       color: .indigo)
                sunRow(icon: "star.fill",        label: "Astro Dawn",    time: times.astronomicalDawn,   color: .purple)
                sunRow(icon: "star.fill",        label: "Astro Dusk",    time: times.astronomicalDusk,   color: .purple)
                sunRow(icon: "camera.aperture",  label: "Golden Begin",  time: times.goldenHourBegin,    color: .yellow)
                sunRow(icon: "camera.aperture",  label: "Golden End",    time: times.goldenHourEnd,      color: .yellow)
            }
        }
        .padding()
        .background(ZDDesign.darkCard)
        .cornerRadius(12)
    }

    private func sunRow(icon: String, label: String, time: Date?, color: Color) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon).foregroundColor(color).font(.caption)
            VStack(alignment: .leading, spacing: 1) {
                Text(label).font(.caption2).foregroundColor(.secondary)
                Text(time.map { $0.formatted(date: .omitted, time: .shortened) } ?? "—")
                    .font(.caption.bold()).foregroundColor(ZDDesign.pureWhite)
            }
            Spacer()
        }
        .padding(8)
        .background(Color.white.opacity(0.04))
        .cornerRadius(8)
    }

    private func dayLengthRow(seconds: TimeInterval?) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "clock.fill").foregroundColor(ZDDesign.successGreen).font(.caption)
            VStack(alignment: .leading, spacing: 1) {
                Text("Day Length").font(.caption2).foregroundColor(.secondary)
                if let s = seconds {
                    let h = Int(s) / 3600, m = (Int(s) % 3600) / 60
                    Text("\(h)h \(m)m").font(.caption.bold()).foregroundColor(ZDDesign.pureWhite)
                } else {
                    Text("—").font(.caption.bold()).foregroundColor(ZDDesign.pureWhite)
                }
            }
            Spacer()
        }
        .padding(8)
        .background(Color.white.opacity(0.04))
        .cornerRadius(8)
    }

    private var altCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("CURRENT SUN ALTITUDE").font(.caption.bold()).foregroundColor(.secondary)
            if let alt = calc.currentAltitude {
                HStack {
                    Image(systemName: alt > 0 ? "sun.max.fill" : "moon.fill")
                        .foregroundColor(alt > 0 ? .yellow : .indigo)
                    Text(String(format: "%.1f°", alt))
                        .font(.title3.bold()).foregroundColor(ZDDesign.pureWhite)
                    Spacer()
                    Text(altitudeLabel(alt)).font(.caption).foregroundColor(.secondary)
                }
            } else {
                Text("Location unavailable").font(.caption).foregroundColor(.secondary)
            }
        }
        .padding()
        .background(ZDDesign.darkCard)
        .cornerRadius(12)
    }

    private func altitudeLabel(_ alt: Double) -> String {
        if alt > 0 { return "Daylight" }
        if alt > -6 { return "Civil twilight" }
        if alt > -12 { return "Nautical twilight" }
        if alt > -18 { return "Astronomical twilight" }
        return "Night"
    }
}
