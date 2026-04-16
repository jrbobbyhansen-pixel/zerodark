// CelestialNavigator.swift — Celestial navigation system (NASA COTS-Star-Tracker pattern)
// v6.1: Added sun/moon position, AR overlay data, urban fallback modes

import AVFoundation
import Observation
import CoreLocation

/// Celestial navigator using star detection + sun/moon ephemeris
@MainActor
public class CelestialNavigator: NSObject, ObservableObject, AVCaptureVideoDataOutputSampleBufferDelegate {
    static let shared = CelestialNavigator()

    @Published public var estimatedHeading: Double?
    @Published public var detectedStarCount: Int = 0
    @Published public var isSessionRunning: Bool = false
    @Published var arOverlayData: CelestialOverlayData?
    @Published var fallbackMode: CelestialFallback = .none

    private let captureSession = AVCaptureSession()
    private let detector = StarDetector()
    private let solver = AttitudeSolver()
    private let catalog = StarCatalog.shared
    private let output = AVCaptureVideoDataOutput()
    private let queue = DispatchQueue(label: "com.zerodark.celestial")

    // Location for ephemeris calculations
    private var currentLocation: CLLocationCoordinate2D?

    public override init() {
        super.init()
    }

    /// Update location for sun/moon position calculations
    public func updateLocation(_ coordinate: CLLocationCoordinate2D) {
        currentLocation = coordinate
        refreshEphemeris()
    }

    /// Start capture session
    public func startSession() {
        guard !isSessionRunning else { return }

        captureSession.sessionPreset = .medium

        guard let camera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
              let input = try? AVCaptureDeviceInput(device: camera) else {
            return
        }

        captureSession.addInput(input)

        output.setSampleBufferDelegate(self, queue: queue)
        output.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
        captureSession.addOutput(output)

        captureSession.startRunning()
        isSessionRunning = true
    }

    /// Stop capture session
    public func stopSession() {
        captureSession.stopRunning()
        isSessionRunning = false
    }

    // MARK: - AVCaptureVideoDataOutputSampleBufferDelegate

    public func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
            return
        }

        let detectedStars = detector.detect(in: pixelBuffer)

        Task { @MainActor [weak self] in
            guard let self else { return }
            self.detectedStarCount = detectedStars.count

            // Update fallback mode based on star count
            if detectedStars.count >= 2 {
                self.fallbackMode = .none
            } else if self.currentLocation != nil {
                self.fallbackMode = .sunOnly
            } else {
                self.fallbackMode = .gyroOnly
            }

            guard detectedStars.count >= 2 else {
                self.estimatedHeading = nil
                return
            }

            let lat = self.currentLocation?.latitude ?? 30.0  // Default to mid-latitude
            let visibleCatalog = (self.catalog.visibleStars(heading: self.estimatedHeading ?? 0, latitude: lat)).prefix(detectedStars.count)

            if let quat = self.solver.solve(detected: detectedStars, catalog: Array(visibleCatalog)) {
                let heading = self.quaternionToHeading(quat)
                self.estimatedHeading = heading
            }
        }
    }

    // MARK: - Sun Position (Jean Meeus simplified)

    /// Calculate sun position for given date and location
    /// Returns (azimuth: 0-360 degrees from N, altitude: degrees above horizon)
    public func sunPosition(date: Date = Date(), latitude: Double, longitude: Double) -> (azimuth: Double, altitude: Double) {
        let calendar = Calendar(identifier: .gregorian)
        let comps = calendar.dateComponents(in: TimeZone(identifier: "UTC")!, from: date)

        let year = Double(comps.year ?? 2026)
        let month = Double(comps.month ?? 1)
        let day = Double(comps.day ?? 1)
        let hour = Double(comps.hour ?? 0) + Double(comps.minute ?? 0) / 60.0 + Double(comps.second ?? 0) / 3600.0

        // Julian date
        let a = floor((14 - month) / 12)
        let y = year + 4800 - a
        let m = month + 12 * a - 3
        let jd = day + floor((153 * m + 2) / 5) + 365 * y + floor(y / 4) - floor(y / 100) + floor(y / 400) - 32045 + (hour - 12) / 24.0

        // Julian century
        let T = (jd - 2451545.0) / 36525.0

        // Solar coordinates
        let L0 = (280.46646 + 36000.76983 * T).truncatingRemainder(dividingBy: 360.0)  // mean longitude
        let M = (357.52911 + 35999.05029 * T).truncatingRemainder(dividingBy: 360.0)    // mean anomaly
        let Mrad = M * .pi / 180.0

        // Equation of center
        let C = (1.914602 - 0.004817 * T) * sin(Mrad) + 0.019993 * sin(2 * Mrad)
        let sunLon = (L0 + C).truncatingRemainder(dividingBy: 360.0)

        // Obliquity of ecliptic
        let obliquity = 23.439291 - 0.0130042 * T
        let oblRad = obliquity * .pi / 180.0
        let sunLonRad = sunLon * .pi / 180.0

        // Right ascension and declination
        let sinDec = sin(oblRad) * sin(sunLonRad)
        let dec = asin(sinDec)
        let ra = atan2(cos(oblRad) * sin(sunLonRad), cos(sunLonRad))

        // Greenwich sidereal time
        let d = jd - 2451545.0
        let GMST = (280.46061837 + 360.98564736629 * d).truncatingRemainder(dividingBy: 360.0)
        let LST = (GMST + longitude).truncatingRemainder(dividingBy: 360.0)
        let LSTrad = LST * .pi / 180.0

        // Hour angle
        let HA = LSTrad - ra

        // Altitude and azimuth
        let latRad = latitude * .pi / 180.0
        let sinAlt = sin(latRad) * sin(dec) + cos(latRad) * cos(dec) * cos(HA)
        let altitude = asin(sinAlt) * 180.0 / .pi

        let cosAz = (sin(dec) - sin(latRad) * sinAlt) / (cos(latRad) * cos(asin(sinAlt)))
        var azimuth = acos(max(-1, min(1, cosAz))) * 180.0 / .pi
        if sin(HA) > 0 { azimuth = 360.0 - azimuth }

        return (azimuth: azimuth, altitude: altitude)
    }

    // MARK: - Sunrise / Sunset

    /// Calculate sunrise and sunset times for given date and location
    public func sunTimes(date: Date = Date(), latitude: Double, longitude: Double) -> (sunrise: Date?, sunset: Date?, civilTwilight: Date?) {
        let calendar = Calendar(identifier: .gregorian)
        let startOfDay = calendar.startOfDay(for: date)

        // Search for solar altitude crossing -0.833 degrees (standard sunrise/sunset)
        var sunrise: Date?
        var sunset: Date?
        var civilTwilight: Date?

        for minute in stride(from: 0, to: 1440, by: 2) {
            let t = startOfDay.addingTimeInterval(Double(minute) * 60)
            let pos = sunPosition(date: t, latitude: latitude, longitude: longitude)

            let tNext = startOfDay.addingTimeInterval(Double(minute + 2) * 60)
            let posNext = sunPosition(date: tNext, latitude: latitude, longitude: longitude)

            // Sunrise: altitude crosses -0.833 going up
            if pos.altitude <= -0.833 && posNext.altitude > -0.833 && sunrise == nil {
                sunrise = t
            }
            // Sunset: altitude crosses -0.833 going down
            if pos.altitude > -0.833 && posNext.altitude <= -0.833 {
                sunset = t
            }
            // Civil twilight: altitude crosses -6 going down
            if pos.altitude > -6.0 && posNext.altitude <= -6.0 {
                civilTwilight = t
            }
        }

        return (sunrise, sunset, civilTwilight)
    }

    // MARK: - AR Overlay Data

    private func refreshEphemeris() {
        guard let loc = currentLocation else { return }
        let now = Date()

        let sun = sunPosition(date: now, latitude: loc.latitude, longitude: loc.longitude)

        arOverlayData = CelestialOverlayData(
            sunAzimuth: sun.azimuth,
            sunAltitude: sun.altitude,
            moonAzimuth: nil,  // Moon ephemeris simplified out for v6.1
            moonAltitude: nil,
            detectedStarPositions: [],
            timestamp: now
        )
    }

    // MARK: - Helpers

    private func quaternionToHeading(_ quat: simd_quatd) -> Double {
        let roll = atan2(2 * (quat.vector.w * quat.vector.x + quat.vector.y * quat.vector.z),
                         1 - 2 * (quat.vector.x * quat.vector.x + quat.vector.y * quat.vector.y))
        let pitch = asin(2 * (quat.vector.w * quat.vector.y - quat.vector.z * quat.vector.x))
        let yaw = atan2(2 * (quat.vector.w * quat.vector.z + quat.vector.x * quat.vector.y),
                        1 - 2 * (quat.vector.y * quat.vector.y + quat.vector.z * quat.vector.z))

        // Suppress unused variable warnings
        _ = roll
        _ = pitch

        var heading = yaw * 180.0 / .pi
        if heading < 0 {
            heading += 360
        }
        return heading
    }
}
