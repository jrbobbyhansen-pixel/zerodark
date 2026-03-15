import Foundation

// MARK: - Plugin System

/// Extensible plugin architecture for third-party tools
/// This is what makes Zero Dark a PLATFORM, not just an app

public protocol ZeroDarkPlugin: AnyObject {
    /// Unique identifier for this plugin
    var identifier: String { get }
    
    /// Display name
    var name: String { get }
    
    /// Plugin description
    var description: String { get }
    
    /// Version string
    var version: String { get }
    
    /// Author/organization
    var author: String { get }
    
    /// Tools provided by this plugin
    var tools: [AgentToolkit.Tool] { get }
    
    /// Initialize the plugin
    func initialize() async throws
    
    /// Execute a tool call
    func execute(_ call: AgentToolkit.ToolCall) async -> AgentToolkit.ToolResult
    
    /// Cleanup when plugin is unloaded
    func cleanup() async
}

// MARK: - Plugin Manager

@MainActor
public final class PluginManager: ObservableObject {
    
    public static let shared = PluginManager()
    
    // MARK: - State
    
    @Published public var loadedPlugins: [ZeroDarkPlugin] = []
    @Published public var availableTools: [AgentToolkit.Tool] = []
    
    private var pluginsByIdentifier: [String: ZeroDarkPlugin] = [:]
    
    // MARK: - Plugin Directory
    
    public var pluginDirectory: URL {
        FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("ZeroDark/Plugins", isDirectory: true)
    }
    
    // MARK: - Init
    
    private init() {
        // Create plugin directory
        try? FileManager.default.createDirectory(
            at: pluginDirectory,
            withIntermediateDirectories: true
        )
    }
    
    // MARK: - Load Plugin
    
    public func loadPlugin(_ plugin: ZeroDarkPlugin) async throws {
        // Initialize
        try await plugin.initialize()
        
        // Register
        loadedPlugins.append(plugin)
        pluginsByIdentifier[plugin.identifier] = plugin
        
        // Add tools
        availableTools.append(contentsOf: plugin.tools)
        
        print("[PluginManager] Loaded: \(plugin.name) v\(plugin.version)")
    }
    
    public func unloadPlugin(_ identifier: String) async {
        guard let plugin = pluginsByIdentifier[identifier] else { return }
        
        // Cleanup
        await plugin.cleanup()
        
        // Remove
        loadedPlugins.removeAll { $0.identifier == identifier }
        pluginsByIdentifier.removeValue(forKey: identifier)
        
        // Remove tools
        let toolNames = Set(plugin.tools.map { $0.name })
        availableTools.removeAll { toolNames.contains($0.name) }
        
        print("[PluginManager] Unloaded: \(plugin.name)")
    }
    
    // MARK: - Execute
    
    public func execute(_ call: AgentToolkit.ToolCall) async -> AgentToolkit.ToolResult? {
        // Find which plugin owns this tool
        for plugin in loadedPlugins {
            if plugin.tools.contains(where: { $0.name == call.tool }) {
                return await plugin.execute(call)
            }
        }
        return nil
    }
    
    // MARK: - Discovery
    
    public func discoverPlugins() async -> [PluginManifest] {
        var manifests: [PluginManifest] = []
        
        guard let contents = try? FileManager.default.contentsOfDirectory(
            at: pluginDirectory,
            includingPropertiesForKeys: nil
        ) else {
            return []
        }
        
        for url in contents {
            let manifestURL = url.appendingPathComponent("manifest.json")
            if let data = try? Data(contentsOf: manifestURL),
               let manifest = try? JSONDecoder().decode(PluginManifest.self, from: data) {
                manifests.append(manifest)
            }
        }
        
        return manifests
    }
}

// MARK: - Plugin Manifest

public struct PluginManifest: Codable {
    public let identifier: String
    public let name: String
    public let description: String
    public let version: String
    public let author: String
    public let homepage: String?
    public let tools: [ToolManifest]
    public let permissions: [Permission]
    
    public struct ToolManifest: Codable {
        public let name: String
        public let description: String
        public let parameters: [ParameterManifest]
        
        public struct ParameterManifest: Codable {
            public let name: String
            public let type: String
            public let description: String
            public let required: Bool
        }
    }
    
    public enum Permission: String, Codable {
        case network = "network"
        case filesystem = "filesystem"
        case contacts = "contacts"
        case calendar = "calendar"
        case location = "location"
        case health = "health"
        case homekit = "homekit"
        case notifications = "notifications"
    }
}

// MARK: - Built-in Plugin Examples

/// Example: Wolfram Alpha plugin
public final class WolframAlphaPlugin: ZeroDarkPlugin {
    public let identifier = "com.zerodark.wolfram"
    public let name = "Wolfram Alpha"
    public let description = "Computational knowledge engine"
    public let version = "1.0.0"
    public let author = "Zero Dark"
    
    private var apiKey: String?
    
    public var tools: [AgentToolkit.Tool] {
        [
            AgentToolkit.Tool(
                name: "wolfram_compute",
                description: "Query Wolfram Alpha for computational answers (math, science, data)",
                parameters: [
                    .init(name: "query", type: "string", description: "The question or computation", required: true, enumValues: nil)
                ],
                handler: "wolfram_compute"
            )
        ]
    }
    
    public func initialize() async throws {
        // Load API key from keychain or config
        // In production, this would use proper secure storage
    }
    
    public func execute(_ call: AgentToolkit.ToolCall) async -> AgentToolkit.ToolResult {
        guard call.tool == "wolfram_compute",
              let query = call.arguments["query"] else {
            return AgentToolkit.ToolResult(success: false, output: "Invalid call", data: nil)
        }
        
        // In production, this would call Wolfram Alpha API
        return AgentToolkit.ToolResult(
            success: true,
            output: "Wolfram Alpha result for: \(query)",
            data: nil
        )
    }
    
    public func cleanup() async {}
}

/// Example: Spotify plugin
public final class SpotifyPlugin: ZeroDarkPlugin {
    public let identifier = "com.zerodark.spotify"
    public let name = "Spotify Control"
    public let description = "Control Spotify playback"
    public let version = "1.0.0"
    public let author = "Zero Dark"
    
    public var tools: [AgentToolkit.Tool] {
        [
            AgentToolkit.Tool(
                name: "spotify_play",
                description: "Play music on Spotify",
                parameters: [
                    .init(name: "query", type: "string", description: "Song, artist, or playlist name", required: true, enumValues: nil)
                ],
                handler: "spotify_play"
            ),
            AgentToolkit.Tool(
                name: "spotify_control",
                description: "Control Spotify playback",
                parameters: [
                    .init(name: "action", type: "string", description: "Playback action", required: true, enumValues: ["play", "pause", "next", "previous", "shuffle"])
                ],
                handler: "spotify_control"
            )
        ]
    }
    
    public func initialize() async throws {}
    
    public func execute(_ call: AgentToolkit.ToolCall) async -> AgentToolkit.ToolResult {
        // In production, this would use Spotify API or URL schemes
        return AgentToolkit.ToolResult(
            success: true,
            output: "Spotify: \(call.tool) executed",
            data: nil
        )
    }
    
    public func cleanup() async {}
}

/// Example: Notion plugin
public final class NotionPlugin: ZeroDarkPlugin {
    public let identifier = "com.zerodark.notion"
    public let name = "Notion"
    public let description = "Interact with Notion workspaces"
    public let version = "1.0.0"
    public let author = "Zero Dark"
    
    public var tools: [AgentToolkit.Tool] {
        [
            AgentToolkit.Tool(
                name: "notion_search",
                description: "Search Notion pages and databases",
                parameters: [
                    .init(name: "query", type: "string", description: "Search query", required: true, enumValues: nil)
                ],
                handler: "notion_search"
            ),
            AgentToolkit.Tool(
                name: "notion_create_page",
                description: "Create a new Notion page",
                parameters: [
                    .init(name: "title", type: "string", description: "Page title", required: true, enumValues: nil),
                    .init(name: "content", type: "string", description: "Page content (markdown)", required: false, enumValues: nil),
                    .init(name: "database", type: "string", description: "Database to add to", required: false, enumValues: nil)
                ],
                handler: "notion_create_page"
            )
        ]
    }
    
    public func initialize() async throws {}
    
    public func execute(_ call: AgentToolkit.ToolCall) async -> AgentToolkit.ToolResult {
        return AgentToolkit.ToolResult(
            success: true,
            output: "Notion: \(call.tool) executed",
            data: nil
        )
    }
    
    public func cleanup() async {}
}
