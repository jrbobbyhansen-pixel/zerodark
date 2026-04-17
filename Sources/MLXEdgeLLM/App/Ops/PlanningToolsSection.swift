// PlanningToolsSection.swift — Mission planning tools hub within Ops tab
// NavigationLinks to all planning features

import SwiftUI

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
            }
            .padding(.horizontal)
            .padding(.top, 8)
        }
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
