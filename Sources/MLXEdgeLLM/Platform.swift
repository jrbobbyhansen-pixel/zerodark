import SwiftUI

#if canImport(UIKit)
#if canImport(UIKit)
import UIKit
#endif
#elseif canImport(AppKit)
#if os(macOS)
#if os(macOS)
import AppKit
#endif
#endif
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
