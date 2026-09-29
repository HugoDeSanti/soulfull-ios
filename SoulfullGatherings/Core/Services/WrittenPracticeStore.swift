//
//  WrittenPracticeStore.swift
//  Soulfull Gatherings
//
//  The written libraries — journal prompts, movement sequences, recipes —
//  read from their tables (0021) and shared by every screen that shows one:
//  the three Practice lists, a digital retreat's days, a guide's library.
//
//  Two things set it apart from a plain fetch:
//
//  * It keeps the last library it read, on disk. These pages worked with no
//    connection while they were compiled in — someone on a plane could still
//    open a prompt and write — and moving them to a table must not take that
//    away. The copy is public catalog content, not anyone's data: it lives in
//    Caches, which the system may clear and never backs up.
//
//  * It knows "not there" from "not heard yet". Something absent from
//    `library` is only really absent once this launch has read the tables
//    (`isAuthoritative`). A program day drops an activity whose practice is
//    gone, but must wait on one that simply hasn't loaded — or a day could be
//    marked done, and that is latched, around a practice nobody had seen.
//

import Foundation

@Observable @MainActor
final class WrittenPracticeStore {

    static let shared = WrittenPracticeStore()

    /// This launch's read of the tables.
    enum ReadStatus: Equatable {
        case notYet
        case done
        /// The read failed and nothing this launch has succeeded. `offline`
        /// picks the words — see `Error.isOffline`.
        case failed(offline: Bool)
    }

    /// What the lists show: this launch's read, or until then the copy from
    /// the last one. Empty only before anything has ever loaded.
    private(set) var library: WrittenLibrary
    private(set) var status: ReadStatus = .notYet
    private(set) var isLoading = false

    /// Whether an absence from `library` is an answer. Before the tables have
    /// been read this launch, a practice missing from the remembered copy may
    /// simply be newer than it.
    var isAuthoritative: Bool { status == .done }

    private let fetch: @MainActor () async throws -> WrittenLibrary
    private let cacheURL: URL?
    private var inFlight: Task<Void, Never>?

    /// Both injectable so the rules above can be tested without a network or
    /// a file (`SoulfullTests/WrittenPracticeStoreTests`); the app always uses
    /// the defaults.
    init(fetch: @escaping @MainActor () async throws -> WrittenLibrary = {
             try await SupabaseService.shared.fetchWrittenLibrary()
         },
         cacheURL: URL? = WrittenPracticeStore.defaultCacheURL) {
        self.fetch = fetch
        self.cacheURL = cacheURL
        library = cacheURL.flatMap(Self.remembered(at:)) ?? .empty
    }

    /// Cheap from every screen that needs a library: concurrent callers share
    /// one request, and `SupabaseService` caches the tables for five minutes —
    /// after which this is also how an edit in the dashboard arrives.
    func refresh() async {
        if let inFlight { await inFlight.value; return }
        let task = Task { await load() }
        inFlight = task
        await task.value
        inFlight = nil
    }

    private func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            let fresh = try await fetch()
            library = fresh
            status = .done
            remember(fresh)
        } catch where error.isCancellation {
        } catch {
            Log.data.error("Written practices unavailable: \(error.localizedDescription)")
            // A failed refresh after a good read changes nothing: the library
            // on screen is still this launch's answer.
            if status != .done { status = .failed(offline: error.isOffline) }
        }
    }

    // MARK: - The remembered copy

    /// Where the last library is kept. None under `-uitest-reset`, so a UI
    /// test always reads the tables themselves — a copy left by an earlier run
    /// would hide a decode that had broken since.
    nonisolated static var defaultCacheURL: URL? {
        #if DEBUG
        if CommandLine.arguments.contains("-uitest-reset") { return nil }
        #endif
        return FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first?
            .appendingPathComponent("written-library-v1.json")
    }

    /// Nil when there's no copy or it doesn't decode — an older app's format,
    /// say. Either way the tables are read next.
    private static func remembered(at url: URL) -> WrittenLibrary? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(WrittenLibrary.self, from: data)
    }

    /// Best-effort: a copy that can't be written costs the next offline
    /// launch, not this one.
    private func remember(_ library: WrittenLibrary) {
        guard let cacheURL else { return }
        do {
            try JSONEncoder().encode(library).write(to: cacheURL, options: .atomic)
        } catch {
            Log.data.info("Couldn't keep the written practices: \(error.localizedDescription)")
        }
    }
}
