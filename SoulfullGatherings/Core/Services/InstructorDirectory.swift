//
//  InstructorDirectory.swift
//  Soulfull Gatherings
//
//  Every published guide, read once and shared: the Practice tab's Guides
//  shelf draws from it, and a digital retreat's "with …" credit looks its
//  guide up here to show a face and open the profile.
//
//  Fails soft and silently, like presence. Before migration 0019 is applied —
//  or offline — there is simply no shelf, and every credit stays the plain
//  "with Alma Guerra" it has always been. Nothing else on a screen waits for it.
//

import SwiftUI

@Observable @MainActor
final class InstructorDirectory {

    static let shared = InstructorDirectory()

    /// Published guides, in the team's order.
    private(set) var instructors: [Instructor] = []
    private var inFlight: Task<Void, Never>?

    func instructor(id: String?) -> Instructor? {
        guard let id else { return nil }
        return instructors.first { $0.id == id }
    }

    /// Cheap from every screen that shows a guide: concurrent callers share one
    /// request, and `SupabaseService` caches the catalog for five minutes.
    func refresh() async {
        if let inFlight { await inFlight.value; return }
        let task = Task { await load() }
        inFlight = task
        await task.value
        inFlight = nil
    }

    private func load() async {
        #if DEBUG
        if Self.isPreview { instructors = Self.fixture; return }
        #endif
        do {
            instructors = try await SupabaseService.shared.fetchInstructors()
        } catch where error.isCancellation {
            return
        } catch {
            // Keep what we had: a dropped request must not empty the shelf.
            Log.data.info("Instructors unavailable: \(error.localizedDescription)")
        }
    }

    // MARK: - DEBUG fixture

    /// `-preview-instructors`: three guides with a library, followers and
    /// faces, so the profile can be seen (and tested) before the team has
    /// written a single `instructors` row. Always false in Release.
    nonisolated static var isPreview: Bool {
        #if DEBUG
        CommandLine.arguments.contains("-preview-instructors")
        #else
        false
        #endif
    }

    /// With `-preview-guest` as well, the fixture is browsed as a guest, so
    /// Follow meets the account gate — what `InstructorProfileTests` checks.
    nonisolated static var isPreviewMember: Bool {
        #if DEBUG
        isPreview && !CommandLine.arguments.contains("-preview-guest")
        #else
        false
        #endif
    }

    #if DEBUG
    static let previewSelf = UUID(uuidString: "00000000-0000-0000-0000-00000000bbbb")!

    static let fixture: [Instructor] = [
        Instructor(id: "alma-guerra", name: "Alma Guerra", title: "Breathwork · Somatic therapy",
                   // Fixture copy: about the teaching, never a biography —
                   // these names also appear on real content.
                   bio: "Slow, trauma-aware breathwork that meets the body where it actually is. Less about pushing through, more about noticing what is already here.\n\nThe guide behind Finding Ground. Every session is recorded in one take, in the room where it is taught.",
                   photoUrl: nil),
        Instructor(id: "mara-sole", name: "Mara Solé", title: "Meditation · Movement",
                   bio: "Stillness for people who are sure they can't sit still.",
                   photoUrl: nil),
        Instructor(id: "rodrigo-pean", name: "Rodrigo Peán", title: "Breathwork",
                   bio: nil, photoUrl: nil),
    ]

    private static func member(_ n: Int, _ name: String) -> CommunityMember {
        CommunityMember(id: UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", n))!,
                        displayName: name, avatarUrl: nil)
    }

    /// Alma: 212 followers — small enough that one follow visibly moves the
    /// number — following 12 guides, three faces. Mara: large, compacted.
    /// Rodrigo: no followers, no bio, no library — the empty states.
    static func fixtureSocial(for id: String) -> InstructorSocial? {
        switch id {
        case "alma-guerra":
            return InstructorSocial(followers: 212, following: 12, followedByMe: false, isMe: false,
                                    faces: [member(1, "Theo R."), member(2, "Nia K."), member(3, "Mateo V.")])
        case "mara-sole":
            return InstructorSocial(followers: 75_712, following: 3, followedByMe: true, isMe: false,
                                    faces: [member(1, "Theo R.")])
        case "rodrigo-pean":
            return InstructorSocial(followers: 0, following: 0, followedByMe: false, isMe: false, faces: [])
        default:
            return nil
        }
    }

    static func fixtureLibrary(for id: String) -> InstructorLibrary {
        switch id {
        case "alma-guerra":
            let sessions: [PracticeSession] = [
                .init(id: 6, category: .breathwork, title: "Breath of Fire", lead: "Alma Guerra", mediaKind: .video, storagePath: "", durationSeconds: 540, imageUrl: "retreat-images/kyoto-2026-05.jpg", blurb: "An energizing kundalini practice to wake the body.", instructorID: id),
                .init(id: 21, category: .somatic, title: "Settling the Nervous System", lead: "Alma Guerra", mediaKind: .audio, storagePath: "", durationSeconds: 780, imageUrl: "retreat-images/sedona-2026-06.jpg", blurb: "", instructorID: id),
                .init(id: 22, category: .meditation, title: "Resting in the Exhale", lead: "Alma Guerra", mediaKind: .audio, storagePath: "", durationSeconds: 600, imageUrl: "retreat-images/dolomites-2027-09.jpg", blurb: "", instructorID: id),
            ]
            return InstructorLibrary(sessions: sessions, programs: Program.mock.filter { $0.instructorID == id })
        case "mara-sole":
            return InstructorLibrary(sessions: PracticeSession.mock.filter { $0.lead == "Mara Solé" }, programs: [])
        default:
            return InstructorLibrary(sessions: [], programs: [])
        }
    }
    #endif
}
