// GeofenceEditorView.swift — Geofence editor UI for adding/managing zones

import SwiftUI
import CoreLocation

struct GeofenceEditorView: View {
    @ObservedObject private var manager = GeofenceManager.shared
    @State private var showAddForm = false

    var body: some View {
        ZStack {
            ZDDesign.darkBackground.ignoresSafeArea()

            VStack(spacing: 0) {
                // Header
                HStack {
                    Text("Geofences")
                        .font(.title2)
                        .fontWeight(.bold)
                        .foregroundColor(ZDDesign.pureWhite)

                    Spacer()

                    Button(action: { showAddForm = true }) {
                        Image(systemName: "plus.circle.fill")
                            .font(.title3)
                            .foregroundColor(ZDDesign.cyanAccent)
                    }
                }
                .padding()

                if manager.geofences.isEmpty {
                    VStack(spacing: 16) {
                        Spacer()
                        Image(systemName: "mappin.circle")
                            .font(.system(size: 48))
                            .foregroundColor(ZDDesign.mediumGray)
                        Text("No Geofences")
                            .font(.headline)
                            .foregroundColor(ZDDesign.pureWhite)
                        Text("Add a keep-in or keep-out zone")
                            .font(.caption)
                            .foregroundColor(ZDDesign.mediumGray)
                        Spacer()
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List {
                        ForEach(manager.geofences) { geofence in
                            GeofenceRow(geofence: geofence, manager: manager)
                                .listRowBackground(ZDDesign.darkCard)
                        }
                    }
                    .listStyle(.plain)
                }
            }
        }
        .sheet(isPresented: $showAddForm) {
            AddGeofenceView(isPresented: $showAddForm, manager: manager)
        }
    }
}

struct GeofenceRow: View {
    let geofence: Geofence
    let manager: GeofenceManager

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "mappin.circle.fill")
                    .foregroundColor(geofence.type == "keep-in" ? ZDDesign.successGreen : ZDDesign.signalRed)

                VStack(alignment: .leading, spacing: 2) {
                    Text(geofence.name)
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundColor(ZDDesign.pureWhite)

                    Text(geofence.type.uppercased())
                        .font(.caption2)
                        .foregroundColor(ZDDesign.mediumGray)
                }

                Spacer()

                Button(action: { Task { manager.remove(geofence) } }) {
                    Image(systemName: "trash")
                        .foregroundColor(ZDDesign.signalRed)
                }
            }

            Text("Created: \(formatDate(geofence.createdAt))")
                .font(.caption2)
                .foregroundColor(ZDDesign.mediumGray)
        }
        .padding(8)
    }

    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM dd, HH:mm"
        return formatter.string(from: date)
    }
}

struct AddGeofenceView: View {
    @Binding var isPresented: Bool
    let manager: GeofenceManager
    @State private var name = ""
    @State private var type = "keep-in"
    @State private var radius = 500.0
    @State private var useCurrentLocation = true
    @State private var selectedCoordinate: CodableCoordinate? = nil
    @State private var locationManager = CLLocationManager()

    var body: some View {
        ZStack {
            ZDDesign.darkBackground.ignoresSafeArea()

            VStack(spacing: 16) {
                HStack {
                    Text("Add Geofence")
                        .font(.headline)
                        .foregroundColor(ZDDesign.pureWhite)

                    Spacer()

                    Button(action: { isPresented = false }) {
                        Image(systemName: "xmark")
                            .foregroundColor(ZDDesign.mediumGray)
                    }
                }
                .padding()

                VStack(alignment: .leading, spacing: 12) {
                    // Name
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Name")
                            .font(.caption)
                            .fontWeight(.semibold)
                            .foregroundColor(ZDDesign.cyanAccent)

                        TextField("Zone name", text: $name)
                            .textFieldStyle(.roundedBorder)
                            .foregroundColor(ZDDesign.pureWhite)
                    }

                    // Type
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Type")
                            .font(.caption)
                            .fontWeight(.semibold)
                            .foregroundColor(ZDDesign.cyanAccent)

                        Picker("Type", selection: $type) {
                            Text("Keep-In").tag("keep-in")
                            Text("Keep-Out").tag("keep-out")
                            Text("Alert").tag("alert")
                        }
                        .pickerStyle(.segmented)
                    }

                    // Radius slider
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text("Radius")
                                .font(.caption)
                                .fontWeight(.semibold)
                                .foregroundColor(ZDDesign.cyanAccent)

                            Spacer()

                            Text("\(Int(radius))m")
                                .font(.caption)
                                .foregroundColor(ZDDesign.mediumGray)
                        }

                        Slider(value: $radius, in: 50...5000, step: 50)
                            .tint(ZDDesign.cyanAccent)
                    }

                    // Location button
                    if useCurrentLocation {
                        Button(action: captureCurrentLocation) {
                            HStack(spacing: 8) {
                                Image(systemName: "location.circle.fill")
                                Text("Use Current Location")
                            }
                            .font(.caption)
                            .frame(maxWidth: .infinity)
                            .padding(8)
                            .background(ZDDesign.cyanAccent.opacity(0.2))
                            .cornerRadius(6)
                            .foregroundColor(ZDDesign.cyanAccent)
                        }
                    }
                }
                .padding()

                Spacer()

                // Create button
                Button(action: createGeofence) {
                    Text("Create Geofence")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(12)
                        .background(ZDDesign.cyanAccent)
                        .cornerRadius(8)
                        .foregroundColor(.black)
                }
                .disabled(name.isEmpty)
                .padding()
            }
        }
    }

    private func captureCurrentLocation() {
        locationManager.requestWhenInUseAuthorization()
        locationManager.startUpdatingLocation()

        // Simple capture: use last known location or default
        selectedCoordinate = CodableCoordinate(latitude: 37.7749, longitude: -122.4194)  // SF default
    }

    private func createGeofence() {
        let center = selectedCoordinate ?? CodableCoordinate(latitude: 37.7749, longitude: -122.4194)
        let geometry = GeofenceGeometry.circle(center: center, radiusMeters: radius)
        let geofence = Geofence(name: name, type: type, geometry: geometry)

        manager.add(geofence)
        isPresented = false
    }
}
