//
//  AppSettings.swift
//  Soulfull Gatherings
//
//  Single home for all persisted UserDefaults values.
//  Injected into the environment alongside AppState so any view can
//  read/write settings without touching AppState's routing logic.
//

import SwiftUI

@Observable @MainActor
final class AppSettings {

    enum Keys {
        static let hasOnboarded = "sg.hasOnboarded"
        static let userName     = "sg.userName"
        static let intentions   = "sg.intentions"
        static let bodyState    = "sg.bodyState"
        static let frequency    = "sg.frequency"
        static let avatarUrl    = "sg.avatarUrl"
    }

    var hasOnboarded: Bool { didSet { UserDefaults.standard.set(hasOnboarded, forKey: Keys.hasOnboarded) } }
    var userName: String   { didSet { UserDefaults.standard.set(userName,     forKey: Keys.userName) } }
    var bodyState: String  { didSet { UserDefaults.standard.set(bodyState,    forKey: Keys.bodyState) } }
    var frequency: String  { didSet { UserDefaults.standard.set(frequency,    forKey: Keys.frequency) } }
    /// This member's `profiles.avatar_url`, mirrored so the You tab and the
    /// Community header can paint the face before the server answers. Not the
    /// source of truth — the row is; hydrated on sign-in and on every You tab load.
    var avatarUrl: String?  { didSet { UserDefaults.standard.set(avatarUrl,    forKey: Keys.avatarUrl) } }

    private var intentionsRaw: String { didSet { UserDefaults.standard.set(intentionsRaw, forKey: Keys.intentions) } }

    /// Comma-joined intention ids exposed as a Set for ergonomic read/write.
    var intentions: Set<String> {
        get { Set(intentionsRaw.split(separator: ",").map(String.init)) }
        set { intentionsRaw = newValue.sorted().joined(separator: ",") }
    }

    init() {
        let ud = UserDefaults.standard
        hasOnboarded  = ud.bool(forKey: Keys.hasOnboarded)
        userName      = ud.string(forKey: Keys.userName)    ?? ""
        bodyState     = ud.string(forKey: Keys.bodyState)   ?? ""
        frequency     = ud.string(forKey: Keys.frequency)   ?? ""
        intentionsRaw = ud.string(forKey: Keys.intentions)  ?? ""
        avatarUrl     = ud.string(forKey: Keys.avatarUrl)
    }

    func reset() {
        hasOnboarded  = false
        clearPersonalAnswers()
    }

    /// Everything here that describes **a person** rather than this install.
    ///
    /// Called on sign-out and account deletion. Without it these outlived the
    /// session that produced them, with two consequences. The You tab still
    /// greeted a deleted user by name and listed their intentions — after a
    /// dialog that promised to delete "saved data". Worse, the next person to
    /// sign in on the same phone had the previous member's answers **uploaded
    /// to their `profiles` row**: `AccountViewModel.mergeProfile` sees a server
    /// row with no answers, takes the "this is a new account" branch, and
    /// pushes whatever is in `AppSettings`.
    ///
    /// `hasOnboarded` deliberately survives — it describes the install, and
    /// clearing it would throw a returning user back through onboarding.
    func clearPersonalAnswers() {
        userName      = ""
        intentionsRaw = ""
        bodyState     = ""
        frequency     = ""
        avatarUrl     = nil
    }
}
