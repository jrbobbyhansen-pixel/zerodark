// RegionDrawView.swift — Pan-to-select bounding box for offline map region
// User pans/zooms the map; the visible viewport is the download region.
// "Use This Area" captures the current map extent.

import SwiftUI
import MapKit

struct RegionDrawView: View {
    let onConfirm: (MKCoordinateRegion, String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var mapRegion = MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 39.5, longitude: -98.35),
        span: MKCoordinateSpan(latitudeDelta: 25.0, longitudeDelta: 40.0)
    )
    @State private var regionName = ""

    private var estimatedMB: Double {
        TileDownloadJob(regionName: "", bounds: mapRegion, minZoom: 8, maxZoom: 14)
            .estimatedStorageMB
    }

    var body: some View {
        NavigationStack {
            ZStack {
                // Interactive map — user pans/zooms to select area
                Map(coordinateRegion: $mapRegion)
                    .ignoresSafeArea(edges: .top)

                // Dashed border overlay showing the exact capture area
                Rectangle()
                    .strokeBorder(
                        ZDDesign.cyanAccent,
                        style: StrokeStyle(lineWidth: 2, dash: [8, 4])
                    )
                    .padding(32)
                    .allowsHitTesting(false)

                // Corner markers
                GeometryReader { geo in
                    let inset: CGFloat = 32
                    cornerDot.position(x: inset, y: inset)
                    cornerDot.position(x: geo.size.width - inset, y: inset)
                    cornerDot.position(x: inset, y: geo.size.height - inset)
                    cornerDot.position(x: geo.size.width - inset, y: geo.size.height - inset)
                }
                .allowsHitTesting(false)

                // Bottom confirm panel
                VStack {
                    Spacer()
                    confirmPanel
                        .padding(.horizontal, 16)
                        .padding(.bottom, 24)
                }
            }
            .navigationTitle("Select Area")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
            }
            .preferredColorScheme(.dark)
        }
    }

    private var cornerDot: some View {
        Circle()
            .fill(ZDDesign.cyanAccent)
            .frame(width: 10, height: 10)
    }

    private var confirmPanel: some View {
        VStack(spacing: 10) {
            HStack {
                Label("Pan and zoom to frame your region", systemImage: "hand.draw")
                    .font(.caption)
                    .foregroundColor(ZDDesign.mediumGray)
                Spacer()
                Text(String(format: "~%.0f MB", estimatedMB))
                    .font(.caption.monospacedDigit())
                    .foregroundColor(estimatedMB > 500 ? ZDDesign.safetyYellow : ZDDesign.mediumGray)
            }

            TextField("Region name (optional)", text: $regionName)
                .font(.subheadline)
                .padding(10)
                .background(Color.black.opacity(0.8), in: RoundedRectangle(cornerRadius: 8))
                .autocorrectionDisabled()

            Button {
                let name = regionName.isEmpty
                    ? "Custom_\(Int.random(in: 1000...9999))"
                    : regionName.replacingOccurrences(of: " ", with: "_")
                onConfirm(mapRegion, name)
            } label: {
                Label("Use This Area", systemImage: "checkmark.circle.fill")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(12)
                    .background(ZDDesign.cyanAccent)
                    .foregroundColor(.black)
                    .cornerRadius(10)
            }
        }
        .padding(14)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14))
    }
}

#Preview {
    RegionDrawView { region, name in
        print("Region: \(region.center), name: \(name)")
    }
}
