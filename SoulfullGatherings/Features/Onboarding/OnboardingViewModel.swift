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

    var step: Step = .name

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

    var isFirstStep: Bool { step == .name }
    var isQuestionStep: Bool { step != .finish }

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
        withAnimation(.spring(response: 0.45, dampingFraction: 0.85)) {
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
        withAnimation(.spring(response: 0.45, dampingFraction: 0.85)) {
            switch step {
            case .name:      break
            case .intention: step = .name
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
