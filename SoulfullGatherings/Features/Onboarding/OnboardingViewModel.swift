//
//  OnboardingViewModel.swift
//  Soulfull Gatherings
//
//  Drives the multi-step onboarding flow: step index, validation,
//  next/back, and the final commit into AppState.
//

import SwiftUI

@Observable @MainActor
final class OnboardingViewModel {

    enum Step: Int, CaseIterable {
        case name
        case intention
        case state
        case frequency
        case finish

        var index: Int { rawValue }
        static let questionCount = 4
    }

    var step: Step

    /// Where the questions start. A member who signed in from Welcome
    /// (`AppState.stageAfterWelcomeSignIn`) and still reaches onboarding has an
    /// account with no name on it — Sign in with Apple shares one only the
    /// first time, and not at all if they chose not to. Asking for it then is
    /// the "name after Sign in with Apple" pattern App Review rejects, so their
    /// questions start at intentions and the name stays theirs to leave out.
    let firstStep: Step

    init(asksName: Bool = true) {
        firstStep = asksName ? .name : .intention
        step = firstStep
    }

    // Working answers — committed to AppState on `complete()`.
    var name: String = ""
    var intentions: Set<String> = []
    var bodyState: String? = nil
    var frequency: String? = nil

    var canAdvance: Bool {
        switch step {
        case .name:      return !name.trimmingCharacters(in: .whitespaces).isEmpty
        case .intention: return !intentions.isEmpty
        case .state:     return bodyState != nil
        case .frequency: return frequency != nil
        case .finish:    return true
        }
    }

    var isFirstStep: Bool { step == firstStep }
    var isQuestionStep: Bool { step.index < Step.questionCount }

    func toggleIntention(_ id: String) {
        Haptics.select()
        if intentions.contains(id) { intentions.remove(id) }
        else { intentions.insert(id) }
    }

    func pickState(_ id: String) {
        Haptics.select()
        bodyState = id
    }

    func pickFrequency(_ id: String) {
        Haptics.select()
        frequency = id
    }

    func next() {
        guard canAdvance else { return }
        Haptics.bump()
        withAnimation(Theme.Motion.settle) {
            switch step {
            case .name:      step = .intention
            case .intention: step = .state
            case .state:     step = .frequency
            case .frequency: step = .finish
            case .finish:    break
            }
        }
    }

    func back() {
        Haptics.tap()
        withAnimation(Theme.Motion.settle) {
            switch step {
            case .name:      break
            case .intention: if firstStep == .name { step = .name }
            case .state:     step = .intention
            case .frequency: step = .state
            case .finish:    step = .frequency
            }
        }
    }

    /// Persist into AppSettings and route to Main.
    func complete(into app: AppState) {
        app.settings.userName   = name.trimmingCharacters(in: .whitespaces)
        app.settings.intentions = intentions
        app.settings.bodyState  = bodyState ?? ""
        app.settings.frequency  = frequency ?? ""
        app.finishOnboarding()
    }
}
