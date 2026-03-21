// HapticPickerSheet.swift — Tactical haptic code picker
import SwiftUI

struct HapticPickerSheet: View {
    @Environment(\.dismiss) var dismiss
    @StateObject private var haptic = HapticComms.shared
    let columns = [GridItem(.flexible()), GridItem(.flexible())]

    var body: some View {
        NavigationStack {
            ZStack {
                ZDDesign.darkBackground.ignoresSafeArea()
                ScrollView {
                    LazyVGrid(columns: columns, spacing: 16) {
                        ForEach(TacticalHapticCode.allCases, id: \.self) { code in
                            Button {
                                haptic.send(code)
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { dismiss() }
                            } label: {
                                VStack(spacing: 8) {
                                    Image(systemName: code.icon)
                                        .font(.title)
                                        .foregroundColor(code == .danger ? ZDDesign.signalRed : ZDDesign.cyanAccent)
                                    Text(code.displayName)
                                        .font(.caption)
                                        .foregroundColor(ZDDesign.pureWhite)
                                }
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(ZDDesign.darkCard)
                                .cornerRadius(12)
                            }
                        }
                    }
                    .padding()
                }
            }
            .navigationTitle("Send Haptic")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }
}
