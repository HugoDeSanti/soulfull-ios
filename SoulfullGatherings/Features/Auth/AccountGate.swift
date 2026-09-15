//
//  AccountGate.swift
//  Soulfull Gatherings
//
//  Just-in-time account gating. Browsing is free — the retreat catalog, the
//  Practice landing and every list screen open for an anonymous guest. An
//  account is only asked for at the moment the user reaches for something
//  personal: playing a session, opening a journal prompt, a movement
//  sequence or a recipe.
//
//  This replaced a hard gate at the end of onboarding (2026-09-03), which put
//  the app in scope for App Store Guideline 5.1.1(i) — registration may not be
//  required unless it's directly relevant to core functionality. Gating the
//  *doing* rather than the *browsing* keeps that argument easy to make.
//
//  The gate holds the interrupted action and replays it once the account
//  exists, so signing in never costs the user the tap they were making.
//
//  It owns only the pending action; the presentation flag is a plain `@State`
//  Bool in `MainTabView`, matching every other sheet in the app. (An earlier
//  version stored `isPresenting` here and bound the sheet to
//  `$gate.isPresenting`. That was *suspected* of making the sheet
//  undismissable and restructured on that theory — wrongly: the real cause was
//  `CircleIconButton` hit-testing, see gotcha #5. This shape is kept because
//  it's the more conventional one, not because the binding was broken.)
//

import SwiftUI

@MainActor
final class AccountGate {

    private var pending: (() -> Void)?

    /// Records what the user was reaching for and reports whether the caller
    /// needs to raise the account sheet. When an account already exists the
    /// action runs immediately and this returns `false`.
    ///
    /// - Parameter signedIn: the caller's `auth.hasAccount`. Pass that, not
    ///   `isAuthenticated` — anonymous guests are authenticated too.
    func require(signedIn: Bool, _ action: @escaping () -> Void) -> Bool {
        guard !signedIn else {
            action()
            return false
        }
        pending = action
        Haptics.tap()
        return true
    }

    /// Call from the sheet's `onDismiss`. Replays the held action only if the
    /// user actually signed in — backing out of the sheet drops it silently,
    /// which is what someone who changed their mind expects.
    func resume(signedIn: Bool) {
        let action = pending
        pending = nil
        guard signedIn else { return }
        action?()
    }
}
