// AppNavigation.swift — Tactical nav shell
import SwiftUI

/// Active tactical tab
public enum AppTab: String, CaseIterable {
    case map   = "Map"
    case lidar = "LiDAR"
    case intel = "Intel"
    case ops = "Ops"

    public var icon: String {
        switch self {
        case .map: return "map.fill"
        case .lidar: return "cube.fill"
        case .intel: return "brain"
        case .ops: return "shield.checkered"
        }
    }
}

/// Root app state
@MainActor
public class AppState: ObservableObject {
    public static let shared = AppState()
    @Published public var selectedTab: AppTab = .map
    private init() {}
}

extension AppTab {
    public var label: String { rawValue }
}
