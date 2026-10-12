//
//  Instructor.swift
//  Soulfull Gatherings
//
//  Guides: their row, their followers, and their library.
//

import Foundation

// MARK: - Instructors

/// A guide who teaches in the app, from the `instructors` table (0019).
///
/// A row the team writes, the way a retreat is — not a member account. A guide
/// who also has an account is linked to it server-side, and that link never
/// reaches the app (see 0019).
struct Instructor: Identifiable, Hashable, Sendable {
    /// A slug ("alma-guerra"): what `practice_sessions.instructor_id` and
    /// `programs.instructor_id` point at.
    let id: String
    let name: String
    /// What they teach, in a few words: "Breathwork · Somatic therapy".
    let title: String?
    let bio: String?
    /// `instructor-photos/<id>.jpg`, resolved by `ImageSource`; nil for the
    /// initial on its tone.
    let photoUrl: String?

    /// "Alma" — for copy that speaks about them ("Practices with Alma").
    var firstName: String {
        name.split(whereSeparator: \.isWhitespace).first.map(String.init) ?? name
    }
}

/// The numbers on a guide's page, from `instructor_social()`.
///
/// `following` is the guides this guide's own member account follows —
/// members follow guides, so that is what a guide can follow. Zero for a guide
/// with no account linked. `faces` never includes the viewer and only ever
/// holds members who share their practice, so it can be shorter than
/// `followers` suggests, or empty.
struct InstructorSocial: Hashable, Sendable {
    var followers: Int
    var following: Int
    var followedByMe: Bool
    /// The viewer IS this guide: no Follow button on your own page.
    var isMe: Bool
    var faces: [CommunityMember]

    static let empty = InstructorSocial(followers: 0, following: 0, followedByMe: false,
                                        isMe: false, faces: [])

    /// "Followed by Alma G., Theo R. and 1,203 others".
    ///
    /// At most two names, "you" first when the viewer follows too — the
    /// server leaves the viewer out of `faces`, so without it they would be
    /// hidden in "others". Nil when nobody can be named: the count alone says
    /// it. `others` is clamped, because the count and the faces come from one
    /// read but an optimistic follow moves only the count.
    func followedByLine(locale: Locale = .current) -> String? {
        var names: [String] = followedByMe ? ["you"] : []
        names += faces.prefix(2 - names.count).map(\.displayName)
        guard !names.isEmpty else { return nil }
        let others = max(0, followers - names.count)
        let named = names.count == 1 ? names[0] : names.joined(separator: others == 0 ? " and " : ", ")
        switch others {
        case 0:  return "Followed by \(named)"
        case 1:  return "Followed by \(named) and 1 other"
        default: return "Followed by \(named) and \(others.formatted(.number.locale(locale))) others"
        }
    }
}

/// What a guide has published: their digital retreats, their sessions on the
/// Practice tab, and the written practices that name them.
struct InstructorLibrary: Hashable, Sendable {
    var programs: [Program]
    var sessions: [PracticeSession]
    var exercises: [Exercise] = []
    var recipes: [Recipe] = []
    var journals: [JournalPrompt] = []

    var isEmpty: Bool { count == 0 }
    var count: Int { programs.count + sessions.count + exercises.count + recipes.count + journals.count }

    /// Takes the guide's own practices from the written libraries, in each
    /// library's order. The libraries hold published rows only, so a practice
    /// that has been taken down isn't listed.
    init(programs: [Program], sessions: [PracticeSession], written: WrittenLibrary,
         instructorID: String) {
        self.programs = programs
        self.sessions = sessions
        self.exercises = written.exercises.filter { $0.instructorID == instructorID }
        self.recipes = written.recipes.filter { $0.instructorID == instructorID }
        self.journals = written.journals.filter { $0.instructorID == instructorID }
    }
}
