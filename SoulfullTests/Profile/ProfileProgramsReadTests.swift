//
//  ProfileProgramsReadTests.swift
//  SoulfullTests
//
//  When the You tab reads the digital retreats a member has joined. A failed
//  read must always be retried: it once left "You're offline" on the section
//  after the connection came back, because the joined set matched what was on
//  screen (both empty) and the read was skipped before the failure cleared.
//
//  The view model itself reads `ProgramStore.shared` and the live session, so
//  the rule is tested as the pure function it delegates to; the section on a
//  populated account is SoulfullUITests/ProfileTests.
//

import Testing
@testable import SoulfullGatherings

@Suite("You tab · joined programs read")
struct ProfileProgramsReadTests {

    @Test func anEarlierFailureIsReadAgainEvenWhenNothingSeemsToHaveChanged() {
        let needed = ProfileViewModel.needsProgramsRead(force: false, loaded: true, failure: .offline,
                                                        joined: [], shown: [])

        #expect(needed)
    }

    @Test func aLoadedSectionWithTheSameProgramsIsLeftAlone() {
        let needed = ProfileViewModel.needsProgramsRead(force: false, loaded: true, failure: nil,
                                                        joined: ["finding-ground"], shown: ["finding-ground"])

        #expect(!needed)
    }

    @Test(arguments: [
        (true, true, Set<String>(), Set<String>()),                 // pull to refresh
        (false, false, Set<String>(), Set<String>()),               // never read
        (false, true, Set(["finding-ground"]), Set<String>()),      // joined one since
    ])
    func itIsReadWhenForcedNeverReadOrTheJoinedSetMoved(force: Bool, loaded: Bool,
                                                         joined: Set<String>, shown: Set<String>) {
        let needed = ProfileViewModel.needsProgramsRead(force: force, loaded: loaded, failure: nil,
                                                        joined: joined, shown: shown)

        #expect(needed)
    }
}
