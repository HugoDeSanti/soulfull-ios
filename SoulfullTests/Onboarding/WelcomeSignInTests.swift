//
//  WelcomeSignInTests.swift
//  SoulfullTests
//
//  Where Welcome's "I already have an account" leads. It used to do exactly
//  what Begin did, so a returning member answered four questions and landed
//  as a guest. Now a sign-in whose profile brings a name down goes straight
//  to Home, one without a name is asked, and closing the sheet stays put:
//  it's an offer, never a gate.
//

import Testing
@testable import SoulfullGatherings

@MainActor
@Suite("Welcome sign-in")
struct WelcomeSignInTests {

    @Test func closingTheSheetWithoutSigningInStaysOnWelcome() {
        let next = AppState.stageAfterWelcomeSignIn(hasAccount: false, name: MemberName(first: "Mara"))

        #expect(next == nil)
    }

    @Test func aMemberWhoseProfileHasANameGoesStraightHome() {
        let next = AppState.stageAfterWelcomeSignIn(hasAccount: true, name: MemberName(first: "Mara"))

        #expect(next == .main)
    }

    @Test(arguments: ["", "   "])
    func aMemberWithNoNameOnTheirProfileIsAsked(name: String) {
        let next = AppState.stageAfterWelcomeSignIn(hasAccount: true, name: MemberName(first: name, last: name))

        #expect(next == .onboarding)
    }
}
