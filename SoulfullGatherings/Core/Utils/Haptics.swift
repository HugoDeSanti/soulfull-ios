//
//  Haptics.swift
//  Soulfull Gatherings
//
//  Tiny façade over UIImpactFeedbackGenerator / UINotificationFeedbackGenerator
//  so any view can call `Haptics.tap()` without importing UIKit directly.
//

import UIKit

enum Haptics {

    /// Standard tap — soft. Default for chips, list rows, secondary actions.
    static func tap() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    /// Stronger tap — for primary CTAs ("Begin", "Reserve").
    static func bump() {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
    }

    /// Selection change — used when the retreat stack scrolls past a new name.
    static func select() {
        UISelectionFeedbackGenerator().selectionChanged()
    }

    /// Success — onboarding complete, reservation confirmed.
    static func success() {
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }
}
