// PlanningToolsSection.swift — Mission planning tools hub within Ops tab
// NavigationLinks to all planning features

import SwiftUI
import CoreLocation

struct PlanningToolsSection: View {
    var body: some View {
        ScrollView {
            LazyVStack(spacing: 12) {
                PlanningCard(
                    title: "Op Order Builder",
                    subtitle: "5-paragraph OPORD — PDF + JSON export",
                    icon: "doc.richtext.fill",
                    color: ZDDesign.cyanAccent,
                    destination: OpOrderBuilderView()
                )

                PlanningCard(
                    title: "Risk Matrix",
                    subtitle: "5×5 probability × severity assessment",
                    icon: "exclamationmark.triangle.fill",
                    color: .orange,
                    destination: RiskMatrixView()
                )

                PlanningCard(
                    title: "Consumption Planner",
                    subtitle: "Water, food, battery, and fuel planning",
                    icon: "drop.fill",
                    color: .blue,
                    destination: ConsumptionPlannerView()
                )

                PlanningCard(
                    title: "Pace Calculator",
                    subtitle: "Naismith's rule with terrain and weather modifiers",
                    icon: "figure.hiking",
                    color: .green,
                    destination: ComingSoonView(title: "Pace Calculator", icon: "figure.hiking", description: "Naismith's rule with terrain and weather modifiers")
                )

                PlanningCard(
                    title: "Load Calculator",
                    subtitle: "Team load distribution and redistribution",
                    icon: "scalemass.fill",
                    color: ZDDesign.safetyYellow,
                    destination: LoadCalculatorView()
                )

                PlanningCard(
                    title: "Mission Timeline",
                    subtitle: "Phase tracking with NLT times and sharing",
                    icon: "timeline.selection",
                    color: ZDDesign.cyanAccent,
                    destination: TimelinePlannerView()
                )

                PlanningCard(
                    title: "Contingency Matrix",
                    subtitle: "IF/THEN contingency planning with trigger alerts",
                    icon: "arrow.triangle.branch",
                    color: .orange,
                    destination: ContingencyMatrixView()
                )

                PlanningCard(
                    title: "Rehearsal Checklist",
                    subtitle: "Pre-mission checklists with templates",
                    icon: "checklist",
                    color: .green,
                    destination: RehearsalChecklistView()
                )

                PlanningCard(
                    title: "Drop Zone Marker",
                    subtitle: "Mark airdrop LZ, parachute drift offset, mesh transmission of coordinates",
                    icon: "shippingbox.fill",
                    color: ZDDesign.safetyYellow,
                    destination: LandingZoneMarkerView()
                )

                PlanningCard(
                    title: "Drift Calculator",
                    subtitle: "SAR lost person probability distribution — ISRID profiles, terrain barriers",
                    icon: "arrow.triangle.branch",
                    color: .orange,
                    destination: DriftCalculatorView()
                )

                PlanningCard(
                    title: "Road & Trail Detector",
                    subtitle: "Detect roads/trails from LiDAR ground returns — maintained vs unmaintained",
                    icon: "road.lanes",
                    color: ZDDesign.forestGreen,
                    destination: RoadTrailDetectorView()
                )

                PlanningCard(
                    title: "Climb Route Finder",
                    subtitle: "Analyze cliff face LiDAR for holds, ledges, protection placements, YDS grade",
                    icon: "mountain.2.fill",
                    color: .brown,
                    destination: ClimbRouteFinderView()
                )

                PlanningCard(
                    title: "Current Estimator",
                    subtitle: "River current speed (Manning's eq.), drift calculation for water crossings",
                    icon: "drop.fill",
                    color: ZDDesign.cyanAccent,
                    destination: CurrentEstimatorView()
                )

                PlanningCard(
                    title: "Cave Mapper",
                    subtitle: "Indoor SLAM — floor plan from LiDAR, GPS-denied position, mark hazards & exits",
                    icon: "map.fill",
                    color: ZDDesign.mediumGray,
                    destination: CaveMapperView()
                )

                PlanningCard(
                    title: "Avalanche Analyzer",
                    subtitle: "Identify prone slopes (30-45°), terrain traps, risk rating, safe corridors",
                    icon: "mountain.2.fill",
                    color: ZDDesign.signalRed,
                    destination: AvalancheAnalyzerView()
                )

                PlanningCard(
                    title: "Terrain Classifier",
                    subtitle: "Classify LiDAR voxels: rock, vegetation, water, snow, sand, mud — traversability scores",
                    icon: "mountain.2.fill",
                    color: .brown,
                    destination: TerrainClassifierView()
                )

                PlanningCard(
                    title: "Route Optimizer",
                    subtitle: "Multi-objective Pareto routes: distance, elevation, hazard, cover, exposure",
                    icon: "point.topleft.down.to.point.bottomright.curvepath.fill",
                    color: ZDDesign.forestGreen,
                    destination: RouteOptimizerView()
                )

                PlanningCard(
                    title: "Distance & Bearing",
                    subtitle: "Distance/bearing between waypoints; reverse bearing; multi-leg routes",
                    icon: "ruler.fill",
                    color: ZDDesign.cyanAccent,
                    destination: DistanceBearingView()
                )

                PlanningCard(
                    title: "Area Calculator",
                    subtitle: "Draw polygons on map, calculate enclosed area in m²/ha/acres",
                    icon: "pentagon.fill",
                    color: ZDDesign.safetyYellow,
                    destination: AreaCalculatorView()
                )

                PlanningCard(
                    title: "Elevation Profile",
                    subtitle: "Cumulative gain/loss, high points, saddles from breadcrumb track",
                    icon: "mountain.2.fill",
                    color: .orange,
                    destination: ElevationProfileView()
                )

                OpsSectionHeader(icon: "cloud.sun.fill", title: "ENVIRONMENT", color: ZDDesign.safetyYellow)
                    .padding(.top, 4)

                PlanningCard(
                    title: "Weather Forecaster",
                    subtitle: "Barometric pressure trend, 12-24hr prediction, storm warning",
                    icon: "barometer",
                    color: ZDDesign.cyanAccent,
                    destination: WeatherForecasterView()
                )

                PlanningCard(
                    title: "Sun Calculator",
                    subtitle: "Sunrise/sunset, twilight windows, golden hour, solar altitude",
                    icon: "sun.max.fill",
                    color: .orange,
                    destination: SunCalculatorView()
                )

                PlanningCard(
                    title: "Moon Phase",
                    subtitle: "Phase, illumination, moonrise/moonset, shadow angle, night ops",
                    icon: "moonphase.full.moon",
                    color: .yellow,
                    destination: MoonPhaseView()
                )

                PlanningCard(
                    title: "Light Estimator",
                    subtitle: "Predict lux by time and cloud cover; NVG transition windows",
                    icon: "eye.fill",
                    color: ZDDesign.mediumGray,
                    destination: LightEstimatorView()
                )

                PlanningCard(
                    title: "Wind Estimator",
                    subtitle: "Beaufort field observations, terrain channeling, history",
                    icon: "wind",
                    color: ZDDesign.cyanAccent,
                    destination: WindEstimatorView()
                )

                PlanningCard(
                    title: "Temperature Log",
                    subtitle: "Log temps, overnight low prediction, cold injury risk",
                    icon: "thermometer.snowflake",
                    color: .blue,
                    destination: TempLoggerView()
                )

                PlanningCard(
                    title: "Altitude Tracker",
                    subtitle: "Acclimatization time, AMS risk, ascent rate warnings",
                    icon: "mountain.2.fill",
                    color: .orange,
                    destination: AltitudeTrackerView()
                )

                PlanningCard(
                    title: "Hydration",
                    subtitle: "Water needs by weight/activity/temp/altitude, intake tracker",
                    icon: "drop.fill",
                    color: .blue,
                    destination: HydrationView()
                )

                OpsSectionHeader(icon: "cross.case.fill", title: "MEDICAL", color: ZDDesign.signalRed)
                    .padding(.top, 4)

                PlanningCard(
                    title: "MARCH Casualty Card",
                    subtitle: "TCCC primary survey + indicated interventions + vitals + persistence",
                    icon: "heart.text.square.fill",
                    color: ZDDesign.signalRed,
                    destination: MARCHView()
                )

                OpsSectionHeader(icon: "scope", title: "TACTICAL", color: ZDDesign.cyanAccent)
                    .padding(.top, 4)

                PlanningCard(
                    title: "Ballistics Calculator",
                    subtitle: "G1 drag model, 6 preset cartridges, MOA + MIL holdover + wind drift",
                    icon: "target",
                    color: ZDDesign.cyanAccent,
                    destination: BallisticsView()
                )

                PlanningCard(
                    title: "AR Waypoint Navigator",
                    subtitle: "Camera-overlay heading arrow to a target coordinate; GPS-denied tolerant",
                    icon: "arrow.up.forward.app.fill",
                    color: .green,
                    destination: ARWaypointPickerView()
                )

                PlanningCard(
                    title: "Scan Diff",
                    subtitle: "Voxel-delta change detection between two captured scans",
                    icon: "arrow.left.arrow.right.square.fill",
                    color: .orange,
                    destination: ChangeDetectionView()
                )
            }
            .padding(.horizontal)
            .padding(.top, 8)
        }
    }
}

// MARK: - AR Waypoint Picker

/// Wrapper that selects a waypoint before handing off to ARWaypointNavigatorView.
/// Pulls from WaypointManager's saved list; falls back to a manual lat/lon entry.
private struct ARWaypointPickerView: View {
    @StateObject private var wm = WaypointManager()
    @State private var manualLat: String = ""
    @State private var manualLon: String = ""
    @State private var manualName: String = ""

    var body: some View {
        List {
            Section("Saved Waypoints") {
                if wm.waypoints.isEmpty {
                    Text("No waypoints saved.").foregroundColor(.secondary).font(.caption)
                } else {
                    ForEach(wm.waypoints) { wp in
                        NavigationLink {
                            ARWaypointNavigatorView(
                                target: CLLocationCoordinate2D(
                                    latitude: wp.coordinates.latitude,
                                    longitude: wp.coordinates.longitude
                                ),
                                targetName: wp.name
                            )
                        } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(wp.name).font(.body)
                                Text(String(format: "%.5f, %.5f",
                                            wp.coordinates.latitude,
                                            wp.coordinates.longitude))
                                    .font(.caption2.monospacedDigit())
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                }
            }

            Section("Manual Entry") {
                TextField("Name", text: $manualName)
                TextField("Latitude", text: $manualLat)
                    .keyboardType(.decimalPad)
                TextField("Longitude", text: $manualLon)
                    .keyboardType(.decimalPad)
                NavigationLink("Navigate to Manual Target") {
                    if let lat = Double(manualLat), let lon = Double(manualLon) {
                        ARWaypointNavigatorView(
                            target: CLLocationCoordinate2D(latitude: lat, longitude: lon),
                            targetName: manualName.isEmpty ? "Target" : manualName
                        )
                    } else {
                        Text("Enter valid decimal lat/lon").foregroundColor(.red)
                    }
                }
                .disabled(Double(manualLat) == nil || Double(manualLon) == nil)
            }
        }
        .navigationTitle("AR Waypoint")
    }
}

// MARK: - Planning Card

private struct PlanningCard<Destination: View>: View {
    let title: String
    let subtitle: String
    let icon: String
    let color: Color
    let destination: Destination

    var body: some View {
        NavigationLink(destination: destination) {
            HStack(spacing: 14) {
                Image(systemName: icon)
                    .font(.title2)
                    .foregroundColor(color)
                    .frame(width: 36)

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.headline)
                        .foregroundColor(ZDDesign.pureWhite)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundColor(ZDDesign.mediumGray)
                        .lineLimit(2)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundColor(ZDDesign.mediumGray)
            }
            .padding()
            .background(ZDDesign.darkCard)
            .cornerRadius(12)
        }
    }
}

#Preview {
    NavigationStack { PlanningToolsSection() }
}
