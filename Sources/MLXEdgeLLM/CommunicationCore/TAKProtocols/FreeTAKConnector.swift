// FreeTAKConnector.swift — FreeTAK Server TCP/TLS Connection Handler
// Implements CoT streaming protocol for TAK server interoperability

import Foundation
import Network
import CoreLocation
import Combine
#if canImport(UIKit)
import UIKit
#endif

@MainActor
final class FreeTAKConnector: NSObject, ObservableObject {
    static let shared = FreeTAKConnector()

    @Published var peers: [CoTEvent] = []
    @Published var isConnected = false
    @Published var lastError: String?

    private var connection: NWConnection?
    private var receiveQueue = DispatchQueue(label: "com.zerodark.tak.receive")
    private var sendQueue = DispatchQueue(label: "com.zerodark.tak.send")
    private var receiveBuffer = Data()
    private var pingTimer: Timer?
    private var peerStaleCheckTimer: Timer?

    private let encoder = CoTEncoder.shared
    private let decoder = CoTDecoder.shared

    private var callsign = AppConfig.deviceCallsign
    private var battery: Int = 100

    // TCP framing: raw XML stream, delimited by </event>
    private let eventDelimiter = "</event>".data(using: .utf8)!

    private override init() {
        super.init()
    }

    // MARK: - Connection Management

    /// Connect to a FreeTAK server over plaintext TCP (port 8087)
    func connect(host: String, port: UInt16 = 8087) {
        disconnect()

        let params = NWParameters(tls: nil)
        params.allowLocalEndpointReuse = true

        guard let portValue = NWEndpoint.Port(rawValue: port) else {
            lastError = "Invalid port"
            return
        }
        let endpoint = NWEndpoint.hostPort(host: NWEndpoint.Host(host), port: portValue)

        connection = NWConnection(to: endpoint, using: params)
        startConnection()
    }

    /// Connect to a FreeTAK server over TLS (port 8089) with mutual TLS
    func connectTLS(host: String, port: UInt16 = 8089) {
        disconnect()

        let tlsOptions = NWProtocolTLS.Options()
        // System default certificate validation is used (rejects self-signed unless trusted).
        // To connect to a server with self-signed cert, install the server's CA cert in the device keychain.
        // INTENTIONAL_STUB: mTLS client certificate not yet implemented — will be added in Phase 8.

        let params = NWParameters(tls: tlsOptions)
        params.allowLocalEndpointReuse = true

        guard let portValue = NWEndpoint.Port(rawValue: port) else {
            lastError = "Invalid port"
            return
        }
        let endpoint = NWEndpoint.hostPort(host: NWEndpoint.Host(host), port: portValue)

        connection = NWConnection(to: endpoint, using: params)
        startConnection()
    }

    private func startConnection() {
        guard let connection = connection else { return }

        connection.stateUpdateHandler = { [weak self] state in
            DispatchQueue.main.async {
                switch state {
                case .ready:
                    self?.isConnected = true
                    self?.lastError = nil
                    self?.setupKeepalive()
                    self?.startReceiving()

                case .failed(let error):
                    self?.isConnected = false
                    self?.lastError = error.localizedDescription

                case .cancelled:
                    self?.isConnected = false

                default:
                    break
                }
            }
        }

        connection.start(queue: sendQueue)
    }

    func disconnect() {
        pingTimer?.invalidate()
        peerStaleCheckTimer?.invalidate()
        connection?.cancel()
        connection = nil
        isConnected = false
        receiveBuffer.removeAll()
    }

    // MARK: - Receiving CoT Events

    private func startReceiving() {
        guard let connection = connection else { return }

        receiveData(on: connection)
    }

    private func receiveData(on connection: NWConnection) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 4096) { [weak self] data, context, isComplete, error in
            guard let self = self else { return }

            if let data = data, !data.isEmpty {
                DispatchQueue.main.async {
                    self.receiveBuffer.append(data)
                    self.processBuffer()
                }
            }

            if let error = error {
                DispatchQueue.main.async {
                    self.lastError = error.localizedDescription
                    self.disconnect()
                }
                return
            }

            // Continue receiving
            self.receiveData(on: connection)
        }
    }

    private func processBuffer() {
        // Search for </event> terminator
        while let delimiterRange = receiveBuffer.range(of: eventDelimiter) {
            let eventEnd = delimiterRange.lowerBound + eventDelimiter.count
            let eventData = receiveBuffer.subdata(in: 0..<eventEnd)

            // Decode the event
            if let event = decoder.decode(eventData) {
                upsertPeer(event)
            }

            // Remove processed event from buffer
            receiveBuffer.removeFirst(eventEnd)
        }
    }

    // MARK: - Sending CoT Events

    /// Send a friendly presence event (location + status)
    func sendPresence(coordinate: CLLocationCoordinate2D,
                      callsign: String? = nil,
                      battery: Int? = nil) {
        let cs = callsign ?? self.callsign
        let batt = battery ?? self.battery

        var event = CoTEvent(
            uid: UUID().uuidString,
            type: "a-f-G",
            how: "m-g",
            time: Date(),
            start: Date(),
            stale: Date(timeIntervalSinceNow: 300),
            lat: coordinate.latitude,
            lon: coordinate.longitude,
            hae: 9999999,
            ce: 9999999,
            le: 9999999
        )

        var detail = CoTDetail()
        detail.contact = CoTContact(callsign: cs, endpoint: nil)
        detail.status = CoTStatus(battery: batt)
        #if os(iOS)
        detail.takv = CoTTakv(
            device: UIDevice.current.name,
            platform: "iOS",
            os: UIDevice.current.systemVersion,
            version: "1.0"
        )
        #else
        detail.takv = CoTTakv(
            device: Host.current().localizedName ?? "Mac",
            platform: "macOS",
            os: ProcessInfo.processInfo.operatingSystemVersionString,
            version: "1.0"
        )
        #endif
        event.detail = detail

        send(event)
    }

    /// Send an SOS/emergency marker event
    func sendSOS(coordinate: CLLocationCoordinate2D,
                 callsign: String? = nil) {
        let cs = callsign ?? self.callsign

        var event = CoTEvent(
            uid: UUID().uuidString,
            type: "b-m-p-s-p-i",  // Spot/point of interest for emergency
            how: "h-g-i-g-o",      // Human generated
            time: Date(),
            start: Date(),
            stale: Date(timeIntervalSinceNow: 600),  // 10 minutes
            lat: coordinate.latitude,
            lon: coordinate.longitude,
            hae: 9999999,
            ce: 50,
            le: 9999999
        )

        var detail = CoTDetail()
        detail.contact = CoTContact(callsign: "\(cs)-SOS", endpoint: nil)
        event.detail = detail

        send(event)
    }

    /// Send a connectivity ping
    func sendPing() {
        let event = CoTEvent(
            uid: UUID().uuidString,
            type: "t-x-c-t",
            how: "m-g",
            time: Date(),
            start: Date(),
            stale: Date(timeIntervalSinceNow: 30)
        )

        send(event)
    }

    /// Send a chat/GeoChat message
    func sendChat(text: String,
                  toCallsign: String? = nil) {
        var event = CoTEvent(
            uid: UUID().uuidString,
            type: "b-f-t-c",  // Custom chat type
            how: "h-g-i-g-o",
            time: Date(),
            start: Date(),
            stale: Date(timeIntervalSinceNow: 60)
        )

        var detail = CoTDetail()
        detail.contact = CoTContact(callsign: callsign, endpoint: nil)
        detail.xmlDetail = "    <__chat text=\"\(xmlEscape(text))\"/>\n"
        if let to = toCallsign {
            detail.xmlDetail?.append("    <__target callsign=\"\(xmlEscape(to))\"/>\n")
        }
        event.detail = detail

        send(event)
    }

    private func send(_ event: CoTEvent) {
        guard let connection = connection, isConnected else { return }

        let data = encoder.encode(event)

        connection.send(content: data, completion: .contentProcessed { [weak self] error in
            if let error = error {
                DispatchQueue.main.async {
                    self?.lastError = error.localizedDescription
                }
            }
        })
    }

    // MARK: - Keepalive & Peer Management

    private func setupKeepalive() {
        // Send ping every 60 seconds
        pingTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            self?.sendPing()
        }

        // Check for stale peers every 30 seconds (5 minute timeout)
        peerStaleCheckTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            self?.removeStalepeers()
        }
    }

    private func upsertPeer(_ event: CoTEvent) {
        DispatchQueue.main.async {
            if let index = self.peers.firstIndex(where: { $0.uid == event.uid }) {
                self.peers[index] = event
            } else {
                self.peers.append(event)
            }
        }
    }

    private func removeStalepeers() {
        let now = Date()
        peers.removeAll { event in
            event.stale < now
        }
    }

    private func xmlEscape(_ string: String) -> String {
        return string
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&apos;")
    }
}
