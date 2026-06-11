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
    var retreats: [Retreat] = []
    let moods: [MoodChip] = MoodChip.all

    var greeting: String {
        let h = Calendar.current.component(.hour, from: .now)
        switch h {
        case ..<12:  return "Good morning,"
        case 12..<18: return "Good afternoon,"
        default:      return "Good evening,"
        }
    }

    func load() async {
        print("[HomeViewModel] Fetching retreats from Supabase…")
        do {
            retreats = try await SupabaseService.shared.fetchRetreats()
            print("[HomeViewModel] Fetched \(retreats.count) retreats")
        } catch is CancellationError {
            // View was dismissed mid-fetch; leave existing data intact.
        } catch {
            print("[HomeViewModel] fetchRetreats failed: \(error)")
            // Same graceful fallback as practice sessions: never an empty shelf.
            if retreats.isEmpty { retreats = Retreat.mock }
        }
    }

    func tapMood(_ id: String) {
        Haptics.select()
        selectedMood = selectedMood == id ? nil : id
    }
}
