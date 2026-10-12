//
//  EditNameTests.swift
//  SoulfullTests
//
//  A member changing their name from the You tab. What can be saved (a name,
//  and a different one; trimmed and cut to 64 as stored), what a failure says,
//  and the shortened form other members will see, shown as it is typed.
//

import Foundation
import Testing
@testable import SoulfullGatherings

@MainActor
@Suite("You tab · changing your name")
struct EditNameTests {

    @MainActor final class FakeProfile {
        var saved: [String] = []
        var error: (any Error)?

        func viewModel(current: String = "Mara Lopez") -> EditNameViewModel {
            EditNameViewModel(current: current) { name in
                if let error = self.error { throw error }
                self.saved.append(name)
            }
        }
    }

    @Test func theSameNameCantBeSaved() {
        let vm = FakeProfile().viewModel()

        vm.draft = "  Mara Lopez "

        #expect(!vm.canSave)
    }

    @Test func aBlankNameCantBeSaved() {
        let vm = FakeProfile().viewModel()

        vm.draft = "   "

        #expect(!vm.canSave)
    }

    @Test func aNewNameIsSavedTrimmed() async {
        let profile = FakeProfile()
        let vm = profile.viewModel()
        vm.draft = "  Mara López  "

        let saved = await vm.save()

        #expect(saved)
        #expect(profile.saved == ["Mara López"])
    }

    @Test func aNameIsCutToTheLimitAsItIsTyped() {
        let vm = FakeProfile().viewModel()

        vm.draft = String(repeating: "a", count: MemberName.maxLength + 10)

        #expect(vm.draft.count == MemberName.maxLength)
    }

    /// A name Sign in with Apple never shared can be added.
    @Test func aMemberWithNoNameCanAddOne() async {
        let profile = FakeProfile()
        let vm = profile.viewModel(current: "")
        vm.draft = "Mara"

        #expect(await vm.save())
        #expect(profile.saved == ["Mara"])
    }

    @Test(arguments: [
        (URLError(.notConnectedToInternet), EditNameViewModel.Failure.offline),
        (URLError(.timedOut), .failed),
    ])
    func aFailedSaveSaysWhyAndKeepsTheName(_ error: URLError, _ failure: EditNameViewModel.Failure) async {
        let profile = FakeProfile()
        profile.error = error
        let vm = profile.viewModel()
        vm.draft = "Mara L"

        let saved = await vm.save()

        #expect(!saved)
        #expect(vm.failure == failure)
        #expect(vm.draft == "Mara L")
        #expect(vm.canSave)
    }

    @Test func typingAgainClearsTheFailure() async {
        let profile = FakeProfile()
        profile.error = URLError(.notConnectedToInternet)
        let vm = profile.viewModel()
        vm.draft = "Mara L"
        _ = await vm.save()

        vm.draft = "Mara Lo"

        #expect(vm.failure == nil)
    }

    // MARK: - How Community shows it

    @Test(arguments: [
        ("Hugo De Santiago", "Hugo D."),
        ("Mara Lopez", "Mara L."),
        ("Mara", "Mara"),
        ("  Mara   Lopez ", "Mara L."),
    ])
    func communityShowsTheFirstNameAndTheSecondWordsInitial(_ name: String, _ shown: String) {
        #expect(MemberName.shownInCommunity(name) == shown)
    }

    @Test func noNameShowsNothing() {
        #expect(MemberName.shownInCommunity("  ") == nil)
    }
}
