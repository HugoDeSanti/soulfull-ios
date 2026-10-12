//
//  EditNameTests.swift
//  SoulfullTests
//
//  A member changing their name from the You tab. What can be saved (both
//  parts, and a different name; trimmed and cut to 64 together as stored),
//  what a failure says, and the shortened form other members will see, shown
//  as it is typed.
//

import Foundation
import Testing
@testable import SoulfullGatherings

@MainActor
@Suite("You tab · changing your name")
struct EditNameTests {

    @MainActor final class FakeProfile {
        var saved: [MemberName] = []
        var error: (any Error)?

        func viewModel(current: MemberName = MemberName(first: "Mara", last: "Lopez")) -> EditNameViewModel {
            EditNameViewModel(current: current) { name, _ in
                if let error = self.error { throw error }
                self.saved.append(name)
            }
        }
    }

    @Test func theFieldsOpenOnTheCurrentName() {
        let vm = FakeProfile().viewModel()

        #expect(vm.first == "Mara")
        #expect(vm.last == "Lopez")
    }

    @Test func theSameNameCantBeSaved() {
        let vm = FakeProfile().viewModel()

        vm.first = "  Mara "
        vm.last = "Lopez  "

        #expect(!vm.canSave)
    }

    @Test func aBlankFirstNameCantBeSaved() {
        let vm = FakeProfile().viewModel()

        vm.first = "   "

        #expect(!vm.canSave)
    }

    /// As at sign-up, a name has both parts.
    @Test func aBlankLastNameCantBeSaved() {
        let vm = FakeProfile().viewModel()

        vm.last = "  "

        #expect(!vm.canSave)
    }

    @Test func aNewNameIsSavedTrimmed() async {
        let profile = FakeProfile()
        let vm = profile.viewModel()
        vm.first = "  Mara "
        vm.last = " López  "

        let saved = await vm.save()

        #expect(saved)
        #expect(profile.saved == [MemberName(first: "Mara", last: "López")])
    }

    @Test func eachPartIsCutToTheLimitAsItIsTyped() {
        let vm = FakeProfile().viewModel()

        vm.first = String(repeating: "a", count: MemberName.maxLength + 10)
        vm.last = String(repeating: "b", count: MemberName.maxLength + 10)

        #expect(vm.first.count == MemberName.maxLength)
        #expect(vm.last.count == MemberName.maxLength)
    }

    /// A name Sign in with Apple never shared can be added.
    @Test func aMemberWithNoNameCanAddOne() async {
        let profile = FakeProfile()
        let vm = profile.viewModel(current: MemberName())
        vm.first = "Mara"
        vm.last = "Lopez"

        #expect(await vm.save())
        #expect(profile.saved == [MemberName(first: "Mara", last: "Lopez")])
    }

    /// A name from before the parts was one word: the editor completes it.
    @Test func aOneWordNameIsCompletedWithALastName() async {
        let profile = FakeProfile()
        let vm = profile.viewModel(current: MemberName(first: "Mara"))
        #expect(!vm.canSave)

        vm.last = "Lopez"

        #expect(await vm.save())
        #expect(profile.saved == [MemberName(first: "Mara", last: "Lopez")])
    }

    @Test(arguments: [
        (URLError(.notConnectedToInternet), EditNameViewModel.Failure.offline),
        (URLError(.timedOut), .failed),
    ])
    func aFailedSaveSaysWhyAndKeepsTheName(_ error: URLError, _ failure: EditNameViewModel.Failure) async {
        let profile = FakeProfile()
        profile.error = error
        let vm = profile.viewModel()
        vm.last = "Lo"

        let saved = await vm.save()

        #expect(!saved)
        #expect(vm.failure == failure)
        #expect(vm.last == "Lo")
        #expect(vm.canSave)
    }

    @Test func typingAgainClearsTheFailure() async {
        let profile = FakeProfile()
        profile.error = URLError(.notConnectedToInternet)
        let vm = profile.viewModel()
        vm.last = "Lo"
        _ = await vm.save()

        vm.first = "Marina"

        #expect(vm.failure == nil)
    }

    // MARK: - How Community shows it

    @Test(arguments: [
        (MemberName(first: "Hugo", last: "De Santiago"), "Hugo D."),
        (MemberName(first: "Mary Ann", last: "Smith"), "Mary Ann S."),
        (MemberName(first: "Hugo", last: "de Santiago"), "Hugo D."),
        (MemberName(first: "Mara"), "Mara"),
        (MemberName(first: "  Mara ", last: "  Lopez "), "Mara L."),
    ])
    func communityShowsTheFirstNameAndTheLastInitial(_ name: MemberName, _ shown: String) {
        #expect(name.shownInCommunity == shown)
    }

    @Test func noNameShowsNothing() {
        #expect(MemberName(first: "  ", last: "").shownInCommunity == nil)
    }
}
