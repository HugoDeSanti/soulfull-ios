//
//  InstructorProfileViewModel.swift
//  Soulfull Gatherings
//
//  One guide's page: who they are, who follows them, whom they follow, and
//  what they have published — and the Follow button.
//
//  Nothing here is invented or kept locally. The numbers are
//  `instructor_social()`, the library is the same `practice_sessions` and
//  `programs` rows the other tabs read, and a follow is a row on
//  `instructor_follows`. Reading is open to a guest; following needs an
//  account, which the view asks for through `AccountGate` and the server
//  enforces anyway.
//

import SwiftUI

/// Why a guide's page, or its library, couldn't be read.
enum InstructorLoadFailure: Equatable {
    case offline
    case failed

    init(offline: Bool) { self = offline ? .offline : .failed }

    var title: String {
        switch self {
        case .offline: "No internet connection"
        case .failed:  "Couldn't load this profile"
        }
    }

    var detail: String {
        switch self {
        case .offline: "You'll need to be online to see this guide. Reconnect and try again."
        case .failed:  "Something went wrong at our end. Please try again in a moment."
        }
    }
}

@Observable @MainActor
final class InstructorProfileViewModel {

    /// Everything the page reads and writes. Injectable so the follow rules
    /// can be tested without a network (`SoulfullTests/InstructorFollowTests`);
    /// the app always uses `.standard`.
    struct Backend {
        var instructor: @MainActor (String) async throws -> Instructor?
        var social: @MainActor (String) async throws -> InstructorSocial?
        var library: @MainActor (String) async throws -> InstructorLibrary
        var follow: @MainActor (String, UUID) async throws -> Void
        var unfollow: @MainActor (String, UUID) async throws -> Void
        /// The signed-in member, or nil. Following needs one.
        var userID: @MainActor () -> UUID?
    }

    let instructorID: String

    private(set) var instructor: Instructor?
    /// Nil until the first read lands, and after a read that failed — the
    /// page then shows "–" rather than a zero it doesn't know to be true.
    private(set) var social: InstructorSocial?
    private(set) var library: InstructorLibrary?

    /// The guide isn't published (taken down, or never was).
    private(set) var notFound = false
    private(set) var profileFailure: InstructorLoadFailure?
    private(set) var libraryFailure: InstructorLoadFailure?

    private(set) var isFollowBusy = false
    /// A follow or unfollow that didn't go through. Cleared on the next one.
    private(set) var followError: String?

    private let backend: Backend
    /// Bumped by every follow and unfollow. A read that started before one
    /// must not land after it: it would put back the numbers the tap just
    /// moved, and the button would flip back under the member's thumb.
    private var socialVersion = 0

    init(instructorID: String, instructor: Instructor? = nil, backend: Backend = .standard) {
        self.instructorID = instructorID
        self.instructor = instructor
        self.backend = backend
    }

    var isFollowing: Bool { social?.followedByMe ?? false }

    // MARK: - Loading

    /// Everything on the page. Re-run when the viewer's identity changes —
    /// "followed by me" and "is me" belong to whoever is asking.
    func load() async {
        await loadInstructor()
        guard instructor != nil else { return }
        async let social: Void = refreshSocial()
        async let library: Void = loadLibrary()
        _ = await (social, library)
    }

    private func loadInstructor() async {
        do {
            if let found = try await backend.instructor(instructorID) {
                instructor = found
                notFound = false
            } else if instructor == nil {
                notFound = true
            }
            profileFailure = nil
        } catch where error.isCancellation {
            return
        } catch {
            Log.data.info("Instructor unavailable: \(error.localizedDescription)")
            // A guide handed in by the directory is still worth showing.
            if instructor == nil { profileFailure = InstructorLoadFailure(offline: error.isOffline) }
        }
    }

    func refreshSocial() async {
        let version = socialVersion
        do {
            let fresh = try await backend.social(instructorID)
            guard version == socialVersion else { return }
            // No row while the guide row exists means it was unpublished
            // between the two reads; zeros are the honest answer for the page.
            social = fresh ?? .empty
        } catch where error.isCancellation {
            return
        } catch {
            // Keep what we had. The numbers are the least important thing on
            // the page and must not blank it.
            Log.data.info("Instructor social unavailable: \(error.localizedDescription)")
        }
    }

    func loadLibrary() async {
        do {
            library = try await backend.library(instructorID)
            libraryFailure = nil
        } catch where error.isCancellation {
            return
        } catch {
            Log.data.info("Instructor library unavailable: \(error.localizedDescription)")
            if library == nil { libraryFailure = InstructorLoadFailure(offline: error.isOffline) }
        }
    }

    // MARK: - Following

    /// Follows or unfollows — the state asked for, never a toggle. The account
    /// gate replays this after sign-in, and by then the page may have learned
    /// that the new account already follows this guide: a toggle would then
    /// unfollow on a tap that said "Follow".
    ///
    /// Optimistic: the button and the count move at once, and go back if the
    /// server says no. On success the numbers are re-read, so the faces and
    /// count settle on the server's.
    func setFollowing(_ follow: Bool) async {
        guard let userID = backend.userID(), !isFollowBusy else { return }
        let original = social
        let current = original ?? .empty
        guard !current.isMe, current.followedByMe != follow else { return }

        isFollowBusy = true
        followError = nil
        socialVersion += 1
        var next = current
        next.followedByMe = follow
        next.followers = max(0, current.followers + (follow ? 1 : -1))
        social = next

        do {
            if follow {
                try await backend.follow(instructorID, userID)
            } else {
                try await backend.unfollow(instructorID, userID)
            }
        } catch where error.isCancellation {
            // Whether it landed is unknown; the next read settles it.
            isFollowBusy = false
            return
        } catch {
            Log.data.info("Follow failed: \(error.localizedDescription)")
            social = original
            followError = error.isOffline
                ? "You're offline. Reconnect and try again."
                : "That didn't go through. Please try again."
            isFollowBusy = false
            return
        }
        isFollowBusy = false
        await refreshSocial()
    }
}

// MARK: - Backends

extension InstructorProfileViewModel.Backend {

    static var standard: Self {
        #if DEBUG
        if InstructorDirectory.isPreview { return .preview }
        #endif
        return .live
    }

    static let live = Self(
        instructor: { id in
            try await SupabaseService.shared.fetchInstructors().first { $0.id == id }
        },
        social: { try await SupabaseService.shared.fetchInstructorSocial(id: $0) },
        library: { try await SupabaseService.shared.fetchInstructorLibrary(id: $0) },
        follow: { try await SupabaseService.shared.followInstructor(id: $0, userID: $1) },
        unfollow: { try await SupabaseService.shared.unfollowInstructor(id: $0, userID: $1) },
        userID: { SupabaseService.shared.client.auth.currentUser?.id }
    )

    #if DEBUG
    /// `-preview-instructors`: the fixture in `InstructorDirectory`, with
    /// follows kept in memory for the launch so a follow survives a pop and a
    /// push, the way the real one does.
    static let preview = Self(
        instructor: { id in InstructorDirectory.fixture.first { $0.id == id } },
        social: { id in PreviewFollows.shared.social(for: id) },
        library: { InstructorDirectory.fixtureLibrary(for: $0) },
        follow: { id, _ in PreviewFollows.shared.set(id, following: true) },
        unfollow: { id, _ in PreviewFollows.shared.set(id, following: false) },
        userID: { InstructorDirectory.previewSelf }
    )
    #endif
}

#if DEBUG
@MainActor
private final class PreviewFollows {
    static let shared = PreviewFollows()
    private var changed: [String: InstructorSocial] = [:]

    func social(for id: String) -> InstructorSocial? {
        changed[id] ?? InstructorDirectory.fixtureSocial(for: id)
    }

    func set(_ id: String, following: Bool) {
        guard var social = social(for: id), social.followedByMe != following else { return }
        social.followedByMe = following
        social.followers += following ? 1 : -1
        changed[id] = social
    }
}
#endif
