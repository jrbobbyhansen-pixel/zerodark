// ScanOverlayToolbar.swift — Floating bottom toolbar for scan overlay editing.
// Segmented: View | Markers | Architecture. Per-tab: horizontal picker of kinds.

import SwiftUI

/// Edit mode driven by the Terrain3DViewer.
enum OverlayEditMode: Equatable {
    case view
    case placing(ScanOverlayKind)

    var kind: ScanOverlayKind? {
        if case .placing(let k) = self { return k }
        return nil
    }
}

struct ScanOverlayToolbar: View {
    @Binding var editMode: OverlayEditMode
    @Binding var pendingPointCount: Int
    var onFinalizeZone: () -> Void
    var onCancel: () -> Void

    @State private var category: Category = .markers

    enum Category: String, CaseIterable {
        case markers = "Markers"
        case architecture = "Architecture"
    }

    private var markerKinds: [ScanOverlayKind] {
        [.hazard, .cover, .entry, .objective]
    }
    private var archKinds: [ScanOverlayKind] {
        [.wall, .door, .window, .zone]
    }

    var body: some View {
        VStack(spacing: 0) {
            if editMode != .view {
                placementBanner
            }
            HStack(spacing: 12) {
                categoryPicker
                Spacer()
                kindButtons
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
        }
        .background(.ultraThinMaterial)
    }

    // MARK: - Placement banner

    @ViewBuilder
    private var placementBanner: some View {
        if case .placing(let kind) = editMode {
            HStack(spacing: 10) {
                Image(systemName: kind.icon)
                    .foregroundColor(ZDDesign.cyanAccent)
                Text(bannerText(for: kind))
                    .font(.caption.bold())
                    .foregroundColor(ZDDesign.pureWhite)
                Spacer()
                if kind == .zone && pendingPointCount >= 3 {
                    Button("Done") { onFinalizeZone() }
                        .font(.caption.bold())
                        .foregroundColor(ZDDesign.successGreen)
                }
                Button("Cancel") { onCancel() }
                    .font(.caption.bold())
                    .foregroundColor(ZDDesign.signalRed)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(Color.black.opacity(0.45))
        }
    }

    private func bannerText(for kind: ScanOverlayKind) -> String {
        switch kind {
        case .wall:
            return pendingPointCount == 0 ? "Tap wall start point" : "Tap wall end point"
        case .zone:
            return "Tap zone corners (\(pendingPointCount) placed) — Done when complete"
        case .door, .window:
            return "Tap to place \(kind.displayName)"
        case .hazard, .cover, .entry, .objective:
            return "Tap to place \(kind.displayName) marker"
        }
    }

    // MARK: - Category picker

    private var categoryPicker: some View {
        Picker("", selection: $category) {
            ForEach(Category.allCases, id: \.self) { c in
                Text(c.rawValue).tag(c)
            }
        }
        .pickerStyle(.segmented)
        .frame(width: 220)
    }

    // MARK: - Kind buttons

    private var kindButtons: some View {
        let kinds = (category == .markers) ? markerKinds : archKinds
        return HStack(spacing: 6) {
            ForEach(kinds, id: \.self) { kind in
                kindButton(kind)
            }
        }
    }

    private func kindButton(_ kind: ScanOverlayKind) -> some View {
        let active = (editMode.kind == kind)
        return Button {
            if active {
                editMode = .view
            } else {
                editMode = .placing(kind)
            }
        } label: {
            VStack(spacing: 2) {
                Image(systemName: kind.icon)
                    .font(.caption)
                Text(kind.displayName)
                    .font(.system(size: 9))
            }
            .foregroundColor(active ? ZDDesign.cyanAccent : .secondary)
            .frame(width: 48)
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(active ? ZDDesign.cyanAccent.opacity(0.15) : Color.clear)
            )
        }
    }
}
