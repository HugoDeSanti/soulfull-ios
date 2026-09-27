//
//  ProgramsViewModel.swift
//  Soulfull Gatherings
//
//  Loads the program catalog. Membership state (what you have joined, which
//  days you have done) is NOT here — that is `ProgramStore`, because it is
//  shared by Home, the tab, and every screen underneath.
//

import SwiftUI

/// Why the program catalog is empty.
///
/// The twin of `RetreatsLoadFailure`, kept separate only so the words are the
/// right words — "browse our retreats" is wrong on this tab. The split itself
/// matters for the same reason it does there: telling someone on a train to
/// "try again" is useless, and telling someone with a working connection to
/// check it sends them after the wrong problem.
enum ProgramsLoadFailure: Equatable {
    case offline
    case failed

    var title: String {
        switch self {
        case .offline: "No internet connection"
        case .failed:  "Couldn't load digital retreats"
        }
    }

    var detail: String {
        switch self {
        case .offline:
            "You'll need to be online to browse our digital retreats. Reconnect and try again."
        case .failed:
            "Something went wrong at our end. Please try again in a moment."
        }
    }
}

@Observable @MainActor
final class ProgramsViewModel {

    var programs: [Program] = []
    var isLoading = false
    var loadFailure: ProgramsLoadFailure?

    /// No mock fallback, deliberately — see `RetreatsLoadFailure`. An invented
    /// catalogue of programs nobody can actually be enrolled in is filler, and
    /// filler shown as the real thing is a Guideline 2.1(a) rejection.
    func load(force: Bool = false) async {
        guard force || programs.isEmpty else { return }
        #if DEBUG
        // Joins the `-preview-*` family: renders the tab against the fixture so
        // the layout can be worked on before the table is seeded. Compiled out
        // of Release, and it is the ONLY path that puts `Program.mock` on
        // screen — a failed fetch never falls back to it.
        if CommandLine.arguments.contains("-preview-programs") {
            programs = Program.mock
            return
        }
        #endif
        isLoading = programs.isEmpty
        defer { isLoading = false }
        do {
            loadFailure = nil
            programs = try await SupabaseService.shared.fetchPrograms()
        } catch where error.isCancellation {
        } catch {
            Log.data.error("Programs fetch failed: \(error.localizedDescription)")
            if programs.isEmpty {
                loadFailure = error.isOffline ? .offline : .failed
            }
        }
    }
}
