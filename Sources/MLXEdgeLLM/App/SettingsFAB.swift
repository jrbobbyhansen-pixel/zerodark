// SettingsFAB.swift — Floating Settings Button (Phase 15)

import SwiftUI

struct SettingsFAB: View {
    @State private var showingSettings = false
    @State private var appeared = false

    var body: some View {
        VStack {
            Spacer()
            HStack {
                Spacer()
                Button {
                    showingSettings = true
                } label: {
                    Image(systemName: "gearshape.fill")
                        .font(.title2)
                        .foregroundColor(.white)
                        .padding()
                        .background(ZDDesign.darkCard)
                        .clipShape(Circle())
                        .shadow(radius: 4)
                }
                .scaleEffect(appeared ? 1.0 : 0.1)
                .animation(.spring(response: 0.4, dampingFraction: 0.6), value: appeared)
                .onAppear { appeared = true }
                .padding(.trailing, 20)
                .padding(.bottom, 80)
            }
        }
        .sheet(isPresented: $showingSettings) {
            SettingsTabView()
        }
    }
}

#Preview {
    ZStack {
        Color.black
        SettingsFAB()
    }
}
