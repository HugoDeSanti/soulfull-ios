//
//  Haptics.swift
//  Soulfull Gatherings
//
//  Thin façade over UIKit feedback generators. Generators are cached as
//  statics so the Taptic Engine is warmed up and ready on first use.
//

import UIKit

@MainActor
enum Haptics {

    private static let light        = UIImpactFeedbackGenerator(style: .light)
    private static let medium       = UIImpactFeedbackGenerator(style: .medium)
    private static let selection    = UISelectionFeedbackGenerator()
    private static let notification = UINotificationFeedbackGenerator()

    /// Standard tap — soft. Default for chips, list rows, secondary actions.
    static func tap()     { light.impactOccurred() }

    /// Stronger tap — for primary CTAs ("Begin", "Reserve").
    static func bump()    { medium.impactOccurred() }

    /// Selection change — used when the retreat stack scrolls past a new name.
    static func select()  { selection.selectionChanged() }

    /// Success — onboarding complete, reservation confirmed.
    static func success() { notification.notificationOccurred(.success) }

    /// Call when a gesture begins so the engine is fully warmed before impact.
    static func prepare() {
        light.prepare()
        medium.prepare()
        selection.prepare()
        notification.prepare()
    }
}
