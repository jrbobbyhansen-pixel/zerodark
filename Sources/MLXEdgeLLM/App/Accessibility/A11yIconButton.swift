// A11yIconButton.swift — SwiftUI modifier helpers for icon-only button accessibility.
//
// Icon-only buttons (image alone, no text) default to an empty accessibility
// label — VoiceOver just announces "Button" which is useless. This file gives
// callers a one-line modifier (.a11yIcon("Open Ops")) that sets both
// accessibilityLabel and .accessibilityAddTraits(.isButton) consistently.
// Use on any Image-in-Button site where there's no visible text to carry the
// label.

import SwiftUI

public extension View {
    /// Label an icon-only button for VoiceOver. Applies both the label and
    /// the .isButton trait (useful when the wrapping element is a non-Button
    /// view that happens to be tap-handled).
    func a11yIcon(_ label: String) -> some View {
        self
            .accessibilityLabel(label)
            .accessibilityAddTraits(.isButton)
    }

    /// Set a label + value pair for a status indicator (HStack of Image + Text).
    /// Combines the two into a single accessibility element so VoiceOver reads
    /// "Label: Value" instead of focusing on the decorative icon.
    func a11yStatus(label: String, value: String) -> some View {
        self
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(label)")
            .accessibilityValue(value)
    }
}
