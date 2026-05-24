//
//  HomeViewModel.swift
//  Soulfull Gatherings
//
//  Drives the Home screen — derives the greeting from the current hour
//  and surfaces mock content collections to the view.
//

import SwiftUI

@Observable @MainActor
final class HomeViewModel {

    var selectedMood: String? = nil

    let circles: [CommunityCircle] = CommunityCircle.mock
    let programs: [Program] = Program.mock
    let retreats: [Retreat] = Retreat.mock
    let moods: [MoodChip] = MoodChip.all

    var greeting: String {
        let h = Calendar.current.component(.hour, from: .now)
        switch h {
        case ..<12:  return "Good morning,"
        case 12..<18: return "Good afternoon,"
        default:      return "Good evening,"
        }
    }

    func tapMood(_ id: String) {
        Haptics.select()
        selectedMood = selectedMood == id ? nil : id
    }
}
