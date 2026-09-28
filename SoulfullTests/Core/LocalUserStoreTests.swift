//
//  LocalUserStoreTests.swift
//  SoulfullTests
//
//  Device-local private data, namespaced per member. The privacy policy
//  promises journal reflections never leave the phone; these pin down the
//  rest of that promise — two people sharing an iPhone can't read each
//  other's, a guest who signs up keeps what they wrote, and deleting an
//  account deletes the writing.
//
//  Each test gets its own `UserDefaults` suite and temporary directory.
//

import Foundation
import Testing
@testable import SoulfullGatherings

@MainActor
@Suite("Local user store")
struct LocalUserStoreTests {

    /// An isolated `UserDefaults` suite and private-text directory, removed
    /// when the test ends.
    final class Sandbox {
        let suite = "sg.tests.\(UUID().uuidString)"
        let root = URL.temporaryDirectory.appending(path: "private-\(UUID().uuidString)",
                                                    directoryHint: .isDirectory)
        lazy var defaults = UserDefaults(suiteName: suite)!

        @MainActor func store() -> LocalUserStore {
            LocalUserStore(defaults: defaults, privateRoot: root)
        }

        deinit {
            UserDefaults().removePersistentDomain(forName: suite)
            try? FileManager.default.removeItem(at: root)
        }
    }

    let sandbox = Sandbox()
    let alma = UUID(), theo = UUID(), guest = UUID()

    @Test func withoutASessionNothingIsStoredOrRead() {
        let store = sandbox.store()

        store.set("Linen", forKey: "trip.packing")
        store.setPrivateText("Dear diary", forKey: "journal.1")

        #expect(store.string(forKey: "trip.packing") == nil)
        #expect(store.privateText(forKey: "journal.1") == nil)
    }

    @Test func oneMemberCannotReadAnothersButFindsTheirOwnOnReturn() {
        let store = sandbox.store()
        store.adopt(userID: alma, isAnonymous: false)
        store.set("Linen", forKey: "trip.packing")
        store.setPrivateText("Alma's reflection", forKey: "journal.1")

        #expect(store.adopt(userID: theo, isAnonymous: false))
        #expect(store.string(forKey: "trip.packing") == nil)
        #expect(store.privateText(forKey: "journal.1") == nil)

        store.adopt(userID: alma, isAnonymous: false)
        #expect(store.string(forKey: "trip.packing") == "Linen")
        #expect(store.privateText(forKey: "journal.1") == "Alma's reflection")
    }

    @Test func adoptingTheSameMemberAgainChangesNothing() {
        let store = sandbox.store()
        store.adopt(userID: alma, isAnonymous: false)

        #expect(!store.adopt(userID: alma, isAnonymous: false))
    }

    @Test func aGuestWhoBecomesAMemberKeepsWhatTheyWroteAndTheGuestCopyGoes() {
        let store = sandbox.store()
        store.adopt(userID: guest, isAnonymous: true)
        store.set("Linen", forKey: "trip.packing")
        store.setPrivateText("Written as a guest", forKey: "journal.1")

        store.adopt(userID: alma, isAnonymous: false)
        #expect(store.string(forKey: "trip.packing") == "Linen")
        #expect(store.privateText(forKey: "journal.1") == "Written as a guest")

        store.adopt(userID: guest, isAnonymous: true)
        #expect(store.string(forKey: "trip.packing") == nil)
        #expect(store.privateText(forKey: "journal.1") == nil)
    }

    @Test func onHandoverTheMembersOwnDataWins() {
        let store = sandbox.store()
        store.adopt(userID: alma, isAnonymous: false)
        store.set("Alma's list", forKey: "trip.packing")
        store.setPrivateText("Alma's reflection", forKey: "journal.1")
        store.adopt(userID: guest, isAnonymous: true)
        store.set("Guest's list", forKey: "trip.packing")
        store.setPrivateText("Guest's reflection", forKey: "journal.1")

        store.adopt(userID: alma, isAnonymous: false)

        #expect(store.string(forKey: "trip.packing") == "Alma's list")
        #expect(store.privateText(forKey: "journal.1") == "Alma's reflection")
    }

    /// The scope is remembered across launches, so an upgrade that spans a
    /// relaunch still hands the guest's data over.
    @Test func aGuestUpgradeSpanningARelaunchStillHandsOver() {
        let beforeRelaunch = sandbox.store()
        beforeRelaunch.adopt(userID: guest, isAnonymous: true)
        beforeRelaunch.set("Linen", forKey: "trip.packing")

        let afterRelaunch = sandbox.store()
        afterRelaunch.adopt(userID: alma, isAnonymous: false)

        #expect(afterRelaunch.string(forKey: "trip.packing") == "Linen")
    }

    @Test func anAbandonedGuestIsSweptWhenTheirSessionEnds() {
        let store = sandbox.store()
        store.adopt(userID: guest, isAnonymous: true)
        store.setPrivateText("Written as a guest", forKey: "journal.1")

        store.adopt(userID: nil, isAnonymous: false)
        store.adopt(userID: guest, isAnonymous: true)

        #expect(store.privateText(forKey: "journal.1") == nil)
    }

    @Test func deletingAnAccountErasesItsValuesAndItsWriting() {
        let store = sandbox.store()
        store.adopt(userID: alma, isAnonymous: false)
        store.set("Linen", forKey: "trip.packing")
        store.setPrivateText("Alma's reflection", forKey: "journal.1")

        store.purgeCurrentScope()

        #expect(store.string(forKey: "trip.packing") == nil)
        #expect(store.privateText(forKey: "journal.1") == nil)
    }

    /// Reflections used to live in the plist, which iCloud and Finder backups
    /// include. The first read moves one to the protected file and deletes the
    /// plist copy.
    @Test func aReflectionLeftInThePlistMovesOutOfItOnFirstRead() {
        let store = sandbox.store()
        store.adopt(userID: alma, isAnonymous: false)
        let legacyKey = "sg.u.\(alma.uuidString).journal.3"
        sandbox.defaults.set("Written before the fix", forKey: legacyKey)

        #expect(store.privateText(forKey: "journal.3") == "Written before the fix")
        #expect(sandbox.defaults.string(forKey: legacyKey) == nil)
        #expect(store.privateText(forKey: "journal.3") == "Written before the fix")
    }
}
