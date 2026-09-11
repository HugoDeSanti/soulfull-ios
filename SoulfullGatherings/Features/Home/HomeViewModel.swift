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

    /// DEBUG launch hook, matching the `-tab` / `-preview-*` family:
    /// `-mood anxious` starts with that chip selected, for visual passes on the
    /// mood-driven ritual card. Always nil in Release.
    var selectedMood: String? = {
        #if DEBUG
        let args = CommandLine.arguments
        if let i = args.firstIndex(of: "-mood"), i + 1 < args.count { return args[i + 1] }
        #endif
        return nil
    }()

    /// Curated programs, loaded from Supabase. Empty until the `programs` table
    /// exists and has rows — the shelf then hides itself rather than presenting
    /// `Program.mock` as though it were a real catalogue.
    var programs: [Program] = []
    var retreats: [Retreat] = []
    /// Set when the retreat shelf has nothing to show and why — the shelf
    /// renders the reason instead of quietly disappearing.
    var retreatsFailure: RetreatsLoadFailure? = nil
    let moods: [MoodChip] = MoodChip.all

    /// The chip currently selected, if any.
    var mood: MoodChip? {
        guard let selectedMood else { return nil }
        return moods.first { $0.id == selectedMood }
    }

    /// Ritual-card content, following the selected mood.
    var ritualTitle: String { mood?.ritual ?? MoodChip.defaultRitual.title }
    var ritualLead: String { mood?.ritualLead ?? MoodChip.defaultRitual.lead }
    /// Where "Begin now" goes.
    var ritualDestination: PracticeMenuItem { mood?.suggests ?? MoodChip.defaultRitual.destination }

    var greeting: String {
        let h = Calendar.current.component(.hour, from: .now)
        switch h {
        case ..<12:  return "Good morning,"
        case 12..<18: return "Good afternoon,"
        default:      return "Good evening,"
        }
    }

    func load() async {
        do {
            retreatsFailure = nil
            retreats = try await SupabaseService.shared.fetchRetreats()
        } catch where error.isCancellation {
            // View was dismissed mid-fetch; leave existing data intact.
            // `is CancellationError` never matched — the SDK surfaces
            // cancellation as URLError(.cancelled). See Error.isCancellation.
        } catch {
            Log.data.error("Home retreats fetch failed: \(error.localizedDescription)")
            // No fallback: the shelf used to fill with `Retreat.mock`, which
            // put already-finished retreats in front of an offline user as
            // though they were the live catalog. See `RetreatsLoadFailure`.
            if retreats.isEmpty {
                retreatsFailure = error.isOffline ? .offline : .failed
            }
        }

        // Programs are additive: the shelf only appears once the table is
        // seeded. No mock fallback — an invented catalogue of programs nobody
        // can enrol in is exactly the kind of filler App Review rejects.
        do {
            programs = try await SupabaseService.shared.fetchPrograms()
        } catch where error.isCancellation {
        } catch {
            Log.data.info("Programs unavailable: \(error.localizedDescription)")
            programs = []
        }
    }

    func tapMood(_ id: String) {
        Haptics.select()
        selectedMood = selectedMood == id ? nil : id
    }
}
