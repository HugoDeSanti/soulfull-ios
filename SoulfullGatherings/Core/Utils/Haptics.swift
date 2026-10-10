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

    /// Soft, not light/medium: a damped, rounded knock rather than a click,
    /// so a touch feels like the screen settling under the finger.
    private static let soft         = UIImpactFeedbackGenerator(style: .soft)
    private static let selection    = UISelectionFeedbackGenerator()
    private static let notification = UINotificationFeedbackGenerator()

    /// Standard tap — faint. Default for chips, list rows, secondary actions.
    static func tap()     { soft.impactOccurred(intensity: 0.55) }

    /// Fuller tap — for primary CTAs ("Begin", "Request a place").
    static func bump()    { soft.impactOccurred(intensity: 1.0) }

    /// Selection change — used when the retreat stack scrolls past a new name.
    static func select()  { selection.selectionChanged() }

    /// Success — onboarding complete, reservation confirmed.
    static func success() { notification.notificationOccurred(.success) }

    /// Call when a gesture begins so the engine is fully warmed before impact.
    static func prepare() {
        soft.prepare()
        selection.prepare()
        notification.prepare()
    }
}
