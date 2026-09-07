//
//  LocalUserStore.swift
//  Soulfull Gatherings
//
//  Device-local private data, namespaced per member.
//
//  Some things deliberately never leave the phone — journal reflections above
//  all (the privacy policy makes that an explicit promise), plus the
//  post-purchase trip checklists. They were stored under flat keys
//  (`sg.journal.3`, `sg.trip.todos`), which meant they were keyed to the
//  *device* rather than to the person: sign out, let someone else sign in on
//  the same iPhone, and they were reading the previous member's reflections.
//  Deleting your account didn't remove them either, so the deletion dialog's
//  promise to erase "saved data" wasn't true.
//
//  Every key now lives under `sg.u.<user id>.…`, and `AuthManager` tells this
//  store whose data is in scope whenever the session identity changes.
//

import SwiftUI

@Observable @MainActor
final class LocalUserStore {

    static let shared = LocalUserStore()

    /// The member whose data is currently addressable, as a key-safe string.
    /// Empty before the first session is established.
    private(set) var scope: String = ""

    private let defaults: UserDefaults

    /// Root of every namespaced key, and the prefix a purge sweeps.
    private static let root = "sg.u."
    /// Remembers the scope across launches so a guest→account upgrade that
    /// spans a relaunch still hands the data over.
    private static let scopeKey = "sg.scope.id"
    private static let scopeAnonymousKey = "sg.scope.anonymous"

    /// Whether the scope in hand belongs to an anonymous guest. Guest data is
    /// handed forward when that guest becomes a member, and swept when it is
    /// abandoned instead.
    private var scopeIsAnonymous: Bool

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        scope = defaults.string(forKey: Self.scopeKey) ?? ""
        scopeIsAnonymous = defaults.bool(forKey: Self.scopeAnonymousKey)
    }

    // MARK: - Scope

    /// Adopts the signed-in identity, migrating or sweeping the previous scope
    /// as appropriate. Called from `AuthManager.apply(_:)` on every identity
    /// refresh, so the unchanged case has to stay free.
    ///
    /// Returns `true` when the scope actually moved, which is the caller's cue
    /// to reload anything holding this data in memory.
    @discardableResult
    func adopt(userID: UUID?, isAnonymous: Bool) -> Bool {
        let next = userID?.uuidString ?? ""
        guard next != scope else {
            // Same person; the anonymity flag can still flip underneath us when
            // a guest confirms their email (the id is preserved by that path).
            if scopeIsAnonymous != isAnonymous { setScope(next, isAnonymous: isAnonymous) }
            return false
        }

        let previous = scope
        let previousWasGuest = scopeIsAnonymous

        // A guest who just became a member — or whose session was reissued — is
        // the same human, so their reflections and checklists follow them.
        // A permanent account's data is left where it is: they may sign back in.
        if !previous.isEmpty, previousWasGuest {
            if !next.isEmpty { migrate(from: previous, to: next) }
            purge(scope: previous)
        }

        setScope(next, isAnonymous: isAnonymous)
        return true
    }

    /// Erases everything this member has stored on the device. Called from
    /// account deletion, which promises exactly that.
    func purgeCurrentScope() {
        guard !scope.isEmpty else { return }
        purge(scope: scope)
    }

    // MARK: - Values

    func string(forKey suffix: String) -> String? {
        guard !scope.isEmpty else { return nil }
        return defaults.string(forKey: key(suffix))
    }

    func set(_ value: String?, forKey suffix: String) {
        guard !scope.isEmpty else { return }
        if let value, !value.isEmpty {
            defaults.set(value, forKey: key(suffix))
        } else {
            defaults.removeObject(forKey: key(suffix))
        }
    }

    func dictionary(forKey suffix: String) -> [String: Any]? {
        guard !scope.isEmpty else { return nil }
        return defaults.dictionary(forKey: key(suffix))
    }

    func set(_ value: [String: Any], forKey suffix: String) {
        guard !scope.isEmpty else { return }
        defaults.set(value, forKey: key(suffix))
    }

    // MARK: - Private text (journal reflections)

    /// Storage for text the privacy policy promises is *private*, as distinct
    /// from the merely device-local values above.
    ///
    /// `UserDefaults` was the wrong home for it. A plist in `Preferences/` is
    /// unencrypted at rest beyond the container default, and — the part that
    /// contradicted the policy outright — it is **included in encrypted iCloud
    /// and Finder backups**. `website/legal/privacy-policy.md` tells the user
    /// reflections "do not move with you to a new phone"; restoring a backup
    /// moved them, and anyone with a trusted machine could read them in
    /// plaintext. The screen itself promises "No one but you sees this."
    ///
    /// These land in Application Support instead, written with
    /// `NSFileProtectionComplete` (unreadable while the device is locked —
    /// which costs nothing, since a journal is only ever read in the
    /// foreground) and in a directory flagged `isExcludedFromBackup`.

    func privateText(forKey suffix: String) -> String? {
        guard let url = privateFileURL(suffix) else { return nil }
        migrateLegacyPrivateText(suffix, to: url)
        guard let data = try? Data(contentsOf: url) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    func setPrivateText(_ value: String?, forKey suffix: String) {
        guard let url = privateFileURL(suffix) else { return }
        guard let value, !value.isEmpty else {
            try? FileManager.default.removeItem(at: url)
            return
        }
        do {
            try Data(value.utf8).write(to: url, options: [.atomic, .completeFileProtection])
        } catch {
            Log.data.error("Couldn't save private text: \(error.localizedDescription)")
        }
    }

    /// One-time move of anything written before this store had file-backed
    /// private text, so nobody loses a reflection to the fix. Clears the plist
    /// copy — leaving it behind would defeat the point.
    private func migrateLegacyPrivateText(_ suffix: String, to url: URL) {
        let legacyKey = key(suffix)
        guard let legacy = defaults.string(forKey: legacyKey) else { return }
        if !FileManager.default.fileExists(atPath: url.path), !legacy.isEmpty {
            try? Data(legacy.utf8).write(to: url, options: [.atomic, .completeFileProtection])
        }
        defaults.removeObject(forKey: legacyKey)
    }

    /// `…/Application Support/private/<scope>/<suffix>.txt`, creating the
    /// directory (protected, backup-excluded) on first use.
    private func privateFileURL(_ suffix: String) -> URL? {
        guard !scope.isEmpty, let directory = privateDirectory() else { return nil }
        // Suffixes are internal ("journal.3"), but never build a path from one
        // without neutralising separators.
        let name = suffix.replacingOccurrences(of: "/", with: "_")
                         .replacingOccurrences(of: "..", with: "_")
        return directory.appending(path: "\(name).txt", directoryHint: .notDirectory)
    }

    private func privateDirectory(scope id: String? = nil) -> URL? {
        let scopeID = id ?? scope
        guard !scopeID.isEmpty else { return nil }
        var directory = URL.applicationSupportDirectory
            .appending(path: "private", directoryHint: .isDirectory)
            .appending(path: scopeID, directoryHint: .isDirectory)
        do {
            try FileManager.default.createDirectory(
                at: directory, withIntermediateDirectories: true,
                attributes: [.protectionKey: FileProtectionType.complete]
            )
            var values = URLResourceValues()
            values.isExcludedFromBackup = true      // the policy promises this
            try directory.setResourceValues(values)
        } catch {
            Log.data.error("Couldn't prepare private storage: \(error.localizedDescription)")
            return nil
        }
        return directory
    }

    // MARK: - Private

    /// `sg.u.<scope>.<suffix>`
    private func key(_ suffix: String) -> String { "\(Self.root)\(scope).\(suffix)" }

    private func setScope(_ id: String, isAnonymous: Bool) {
        scope = id
        scopeIsAnonymous = isAnonymous
        defaults.set(id, forKey: Self.scopeKey)
        defaults.set(isAnonymous, forKey: Self.scopeAnonymousKey)
    }

    /// Copies every key from one namespace to the other without overwriting
    /// anything already there — the destination is the newer, more authoritative
    /// identity.
    private func migrate(from old: String, to new: String) {
        let oldPrefix = "\(Self.root)\(old)."
        let newPrefix = "\(Self.root)\(new)."
        for (storedKey, value) in defaults.dictionaryRepresentation() where storedKey.hasPrefix(oldPrefix) {
            let destination = newPrefix + storedKey.dropFirst(oldPrefix.count)
            guard defaults.object(forKey: destination) == nil else { continue }
            defaults.set(value, forKey: destination)
        }
        migratePrivateFiles(from: old, to: new)
    }

    /// Private text lives outside `UserDefaults`, so a guest→member handover
    /// has to carry the files as well — otherwise becoming a member silently
    /// loses everything the guest wrote.
    private func migratePrivateFiles(from old: String, to new: String) {
        let fm = FileManager.default
        guard let source = privateDirectory(scope: old),
              let destination = privateDirectory(scope: new),
              let files = try? fm.contentsOfDirectory(at: source, includingPropertiesForKeys: nil)
        else { return }
        for file in files {
            let target = destination.appending(path: file.lastPathComponent, directoryHint: .notDirectory)
            guard !fm.fileExists(atPath: target.path) else { continue }  // newer identity wins
            try? fm.moveItem(at: file, to: target)
        }
    }

    private func purge(scope id: String) {
        let prefix = "\(Self.root)\(id)."
        for storedKey in defaults.dictionaryRepresentation().keys where storedKey.hasPrefix(prefix) {
            defaults.removeObject(forKey: storedKey)
        }
        // "Delete my account" promises the writing goes too, and it no longer
        // lives in UserDefaults.
        if let directory = privateDirectory(scope: id) {
            try? FileManager.default.removeItem(at: directory)
        }
    }
}
