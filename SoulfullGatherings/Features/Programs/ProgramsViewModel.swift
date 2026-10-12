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
    /// A load has answered, with programs or a failure. Until then an empty
    /// catalog is "not here yet" rather than "none yet" — the screen used to
    /// show "New digital retreats are on their way" for the frame before its
    /// load began. A cancelled load doesn't count.
    private(set) var hasLoaded = false

    /// The catalog read. Injectable so the loading states can be tested without
    /// a network (`SoulfullTests/ProgramCatalogLoadTests`); the app always
    /// uses the default.
    private let fetchPrograms: @MainActor () async throws -> [Program]

    init(fetchPrograms: @escaping @MainActor () async throws -> [Program] = {
        try await SupabaseService.shared.fetchPrograms()
    }) {
        self.fetchPrograms = fetchPrograms
    }

    /// The catalog's copy of `program`, curriculum as it is authored now — or
    /// `program` itself when the catalog doesn't list it (taken down while it
    /// was open). Pages pushed with a program draw this, not what was pushed.
    func current(_ program: Program) -> Program {
        programs.first { $0.id == program.id } ?? program
    }

    /// No mock fallback, deliberately — see `RetreatsLoadFailure`. An invented
    /// catalogue of programs nobody can actually be enrolled in is filler, and
    /// filler shown as the real thing is a Guideline 2.1(a) rejection.
    ///
    /// Reads every time the tab appears. The tab now lives for the whole
    /// session, so a load-once guard kept its first catalog for days: a program
    /// published since showed on Home's shelf (which reads the same 5-minute
    /// cache) and its hand-off here found nothing to open. The cache keeps the
    /// repeat cheap, and a catalog on screen is never swapped for a spinner.
    func load() async {
        #if DEBUG
        // Joins the `-preview-*` family: renders the tab against the fixture so
        // the layout can be worked on before the table is seeded. Compiled out
        // of Release, and it is the ONLY path that puts `Program.mock` on
        // screen — a failed fetch never falls back to it.
        if CommandLine.arguments.contains("-preview-programs") {
            programs = Program.mock
            hasLoaded = true
            return
        }
        #endif
        isLoading = programs.isEmpty
        defer { isLoading = false }
        do {
            loadFailure = nil
            programs = try await fetchPrograms()
            hasLoaded = true
        } catch where error.isCancellation {
        } catch {
            Log.data.error("Programs fetch failed: \(error.localizedDescription)")
            if programs.isEmpty {
                loadFailure = error.isOffline ? .offline : .failed
            }
            hasLoaded = true
        }
    }
}
