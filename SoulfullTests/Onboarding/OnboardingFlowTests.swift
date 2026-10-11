//
//  OnboardingFlowTests.swift
//  SoulfullTests
//
//  Four questions, each needing an answer before Next moves on — the flow
//  must never advance on empty state. The journey through the real screens
//  is SoulfullUITests/OnboardingTests.
//

import Testing
@testable import SoulfullGatherings

@MainActor
@Suite("Onboarding flow")
struct OnboardingFlowTests {

    @Test func eachQuestionHoldsTheFlowUntilItIsAnswered() {
        let vm = OnboardingViewModel()

        vm.name = "   "
        vm.next()
        #expect(vm.step == .name)
        vm.name = "Mara"
        vm.next()
        #expect(vm.step == .intention)

        vm.next()
        #expect(vm.step == .intention)
        vm.toggleIntention("rest")
        vm.next()
        #expect(vm.step == .state)

        vm.next()
        #expect(vm.step == .state)
        vm.pickState("wired")
        vm.next()
        #expect(vm.step == .frequency)

        vm.next()
        #expect(vm.step == .frequency)
        vm.pickFrequency("daily")
        vm.next()
        #expect(vm.step == .finish)
        #expect(!vm.isQuestionStep)
    }

    @Test func deselectingTheOnlyIntentionTakesAwayNext() {
        let vm = OnboardingViewModel()
        vm.step = .intention
        vm.toggleIntention("rest")

        vm.toggleIntention("rest")

        #expect(!vm.canAdvance)
    }

    @Test func backStepsThroughTheQuestionsAndStopsAtTheFirst() {
        let vm = OnboardingViewModel()
        vm.step = .finish

        vm.back()
        #expect(vm.step == .frequency)
        vm.step = .name
        vm.back()
        #expect(vm.step == .name)
    }

    /// A member who signed in from Welcome and still has no name — Sign in
    /// with Apple shares one only the first time — isn't asked for one after
    /// signing in (App Review rejects asking for what Apple was asked for).
    @Test func aMemberWithoutANameStartsAtIntentionsAndCantGoBackToAName() {
        let vm = OnboardingViewModel(asksName: false)

        vm.back()

        #expect(vm.step == .intention)
        #expect(vm.isFirstStep)
        vm.toggleIntention("rest")
        vm.next()
        #expect(vm.step == .state)
        #expect(!vm.isFirstStep)
    }

    /// Committing the name a member was never asked for pushed
    /// `full_name: ''` to their profile and wiped it, so Home said "Friend".
    @Test func aMemberWhoWasntAskedHasNoNameToCommit() {
        let vm = OnboardingViewModel(asksName: false)
        vm.toggleIntention("rest")

        vm.next()

        #expect(vm.nameAnswer == nil)
    }

    @Test(arguments: ["", "   "])
    func aSkipBeforeTypingHasNoNameToCommit(typed: String) {
        let vm = OnboardingViewModel()

        vm.name = typed

        #expect(vm.nameAnswer == nil)
    }

    @Test func theNameIsCommittedWithoutItsSpaces() {
        let vm = OnboardingViewModel()

        vm.name = "  Mara "

        #expect(vm.nameAnswer == "Mara")
    }
}
