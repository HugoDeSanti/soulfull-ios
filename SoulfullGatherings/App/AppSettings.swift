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
    }

    var hasOnboarded: Bool { didSet { UserDefaults.standard.set(hasOnboarded, forKey: Keys.hasOnboarded) } }
    var userName: String   { didSet { UserDefaults.standard.set(userName,     forKey: Keys.userName) } }
    var bodyState: String  { didSet { UserDefaults.standard.set(bodyState,    forKey: Keys.bodyState) } }
    var frequency: String  { didSet { UserDefaults.standard.set(frequency,    forKey: Keys.frequency) } }

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
    }

    func reset() {
        hasOnboarded  = false
        userName      = ""
        intentionsRaw = ""
        bodyState     = ""
        frequency     = ""
    }
}
