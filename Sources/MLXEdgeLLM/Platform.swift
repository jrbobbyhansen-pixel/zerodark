import SwiftUI

#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

// MARK: - Platform

#if canImport(UIKit)
public typealias PlatformImage = UIImage
#elseif canImport(AppKit)
public typealias PlatformImage = NSImage
#endif

// MARK: - SwiftUI extensions

public extension SwiftUI.Image {
    init(platformImage: PlatformImage) {
#if canImport(UIKit)
        self.init(uiImage: platformImage)
#elseif canImport(AppKit)
        self.init(nsImage: platformImage)
#endif
    }
}

public extension SwiftUI.Color {
    static var outputBackground: Color {
#if canImport(UIKit)
        return Color(.systemGroupedBackground)
#elseif canImport(AppKit)
        return Color(nsColor: .windowBackgroundColor)
#else
        return Color.secondary.opacity(0.1)
#endif
    }
}
