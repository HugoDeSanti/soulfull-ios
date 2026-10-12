//
//  ProgramStoreTests.swift
//  SoulfullTests
//
//  A member's digital retreats as the app holds them: a read that set off for
//  someone who has since signed out can't put their programs on the next
//  person's Home. The unlock rule itself is ProgramUnlockRuleTests.
//

import Foundation
import Testing
@testable import SoulfullGatherings

@MainActor
@Suite("Program store")
struct ProgramStoreTests {

    @MainActor final class FakeProgramState {
        var me: UUID? = UUID()
        var enrollments: [ProgramEnrollment] = []
        /// Runs while the read is in flight: a sign-out, say.
        var duringRead: (() -> Void)?

        func store() -> ProgramStore {
            ProgramStore(backend: ProgramStateBackend(
                currentUserID: { self.me },
                fetchState: { _ in
                    self.duringRead?()
                    return (self.enrollments, [])
                }
            ))
        }
    }

    let joined = ProgramEnrollment(programID: "finding-ground",
                                   enrolledAt: Calendar.gregorian(in: "Europe/Madrid").at(2026, 9, 14, 18),
                                   completedAt: nil)

    @Test func aReadThatAnswersAfterTheMemberLeftIsDropped() async {
        let fake = FakeProgramState()
        fake.enrollments = [joined]
        let store = fake.store()
        fake.duringRead = {
            fake.me = nil
            store.clear()
        }

        await store.refresh()

        #expect(!store.isEnrolled("finding-ground"))
        #expect(store.loadedFor == nil)
        #expect(store.status == .notLoaded)
    }

    @Test func aReadForTheSameMemberLands() async {
        let fake = FakeProgramState()
        fake.enrollments = [joined]
        let store = fake.store()

        await store.refresh()

        #expect(store.isEnrolled("finding-ground"))
        #expect(store.loadedFor == fake.me)
        #expect(store.status == .loaded)
    }
}
