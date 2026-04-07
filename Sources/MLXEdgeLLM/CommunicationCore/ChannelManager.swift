import Foundation
import SwiftUI
import CoreLocation
import ARKit
import AVFoundation

// MARK: - ChannelManager

final class ChannelManager: ObservableObject {
    @Published var channels: [Channel] = []
    @Published var selectedChannel: Channel?

    init() {
        setupDefaultChannels()
    }

    private func setupDefaultChannels() {
        let commandChannel = Channel(name: "Command", encryptionKey: "commandKey123")
        let logisticsChannel = Channel(name: "Logistics", encryptionKey: "logisticsKey456")
        let medicalChannel = Channel(name: "Medical", encryptionKey: "medicalKey789")

        channels = [commandChannel, logisticsChannel, medicalChannel]
    }

    func selectChannel(_ channel: Channel) {
        selectedChannel = channel
    }

    func addChannel(name: String, encryptionKey: String) {
        let newChannel = Channel(name: name, encryptionKey: encryptionKey)
        channels.append(newChannel)
    }

    func removeChannel(_ channel: Channel) {
        channels.removeAll { $0.id == channel.id }
    }
}

// MARK: - Channel

struct Channel: Identifiable, Codable {
    let id = UUID()
    var name: String
    var encryptionKey: String
}

// MARK: - ChannelView

struct ChannelView: View {
    @StateObject private var channelManager = ChannelManager()

    var body: some View {
        VStack {
            List(channelManager.channels) { channel in
                Button(action: {
                    channelManager.selectChannel(channel)
                }) {
                    Text(channel.name)
                        .font(.headline)
                        .foregroundColor(.primary)
                }
                .listRowBackground(channelManager.selectedChannel == channel ? Color.blue.opacity(0.2) : Color.clear)
            }

            Button(action: {
                // Add new channel logic here
            }) {
                Text("Add Channel")
                    .padding()
                    .background(Color.blue)
                    .foregroundColor(.white)
                    .cornerRadius(8)
            }
        }
        .navigationTitle("Channels")
    }
}

// MARK: - Preview

struct ChannelView_Previews: PreviewProvider {
    static var previews: some View {
        ChannelView()
    }
}