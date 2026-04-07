import Foundation
import Combine

// MARK: - MQTTClient

class MQTTClient: ObservableObject {
    @Published var isConnected: Bool = false
    @Published var messages: [String] = []
    
    private var mqttManager: MQTTManager?
    private var cancellables = Set<AnyCancellable>()
    
    init() {
        mqttManager = MQTTManager()
        mqttManager?.$isConnected.sink { [weak self] isConnected in
            self?.isConnected = isConnected
        }.store(in: &cancellables)
        
        mqttManager?.$messages.sink { [weak self] messages in
            self?.messages = messages
        }.store(in: &cancellables)
    }
    
    func connect(host: String, port: Int, tls: Bool) {
        mqttManager?.connect(host: host, port: port, tls: tls)
    }
    
    func disconnect() {
        mqttManager?.disconnect()
    }
    
    func subscribe(topic: String, qos: MQTTQoS) {
        mqttManager?.subscribe(topic: topic, qos: qos)
    }
    
    func unsubscribe(topic: String) {
        mqttManager?.unsubscribe(topic: topic)
    }
    
    func publish(topic: String, message: String, qos: MQTTQoS) {
        mqttManager?.publish(topic: topic, message: message, qos: qos)
    }
}

// MARK: - MQTTManager

class MQTTManager: ObservableObject {
    @Published var isConnected: Bool = false
    @Published var messages: [String] = []
    
    private var mqttClient: CocoaMQTT?
    
    func connect(host: String, port: Int, tls: Bool) {
        let clientID = "ZeroDarkClient-\(UUID().uuidString)"
        mqttClient = CocoaMQTT(clientID: clientID, host: host, port: port)
        
        if tls {
            mqttClient?.sslSettings = CocoaMQTTSSLSettings()
        }
        
        mqttClient?.delegate = self
        mqttClient?.connect()
    }
    
    func disconnect() {
        mqttClient?.disconnect()
    }
    
    func subscribe(topic: String, qos: MQTTQoS) {
        mqttClient?.subscribe(topic, qos: qos.rawValue)
    }
    
    func unsubscribe(topic: String) {
        mqttClient?.unsubscribe(topic)
    }
    
    func publish(topic: String, message: String, qos: MQTTQoS) {
        mqttClient?.publish(message, topic: topic, qos: qos.rawValue)
    }
}

// MARK: - MQTTManagerDelegate

extension MQTTManager: CocoaMQTTDelegate {
    func mqtt(_ mqtt: CocoaMQTT, didConnectAck ack: CocoaMQTTConnectAck) {
        isConnected = true
    }
    
    func mqtt(_ mqtt: CocoaMQTT, didDisconnectWith reason: CocoaMQTTDisconnectReason) {
        isConnected = false
    }
    
    func mqtt(_ mqtt: CocoaMQTT, didPublishMessage message: CocoaMQTTMessage, id: UInt16) {
        // Handle publish confirmation if needed
    }
    
    func mqtt(_ mqtt: CocoaMQTT, didReceiveMessage message: CocoaMQTTMessage, id: UInt16, topic: String, qos: CocoaMQTTQoS) {
        messages.append(String(data: message.payload, encoding: .utf8) ?? "Unknown")
    }
}

// MARK: - MQTTQoS

enum MQTTQoS: Int {
    case atMostOnce = 0
    case atLeastOnce = 1
    case exactlyOnce = 2
}