//
//  PracticeComment.swift
//  Soulfull Gatherings
//
//  What members say under a practice: the conversation on a movement
//  sequence, a recipe or a session (0032). Journal prompts have none.
//

import Foundation

extension PracticeContentKind {
    /// Whether members can comment on this library. Not on a journal prompt: a
    /// reflection is private, a prompt's title says what someone is working
    /// through (the feed leaves prompts out for the same reason), and a public
    /// box beside the private one invites writing the wrong thing in the wrong
    /// place. Exhaustive on purpose, like `creditsCreator`. The server holds
    /// the same rule (`practice_comments.content_kind`).
    var takesComments: Bool {
        switch self {
        case .session, .exercise, .recipe: return true
        case .journal:                     return false
        }
    }
}

/// The practice a conversation is under, and what its sheet shows of it.
struct CommentThread: Hashable, Sendable {
    let kind: PracticeContentKind
    let contentID: Int
    /// The practice's title, the sheet's heading.
    let title: String
    /// The practice's photograph, the sheet's ground.
    let imageUrl: String

    /// Nil for a library that takes no comments (`takesComments`).
    init?(kind: PracticeContentKind, contentID: Int, title: String, imageUrl: String) {
        guard kind.takesComments else { return nil }
        self.kind = kind
        self.contentID = contentID
        self.title = title
        self.imageUrl = imageUrl
    }

    init(_ exercise: Exercise) {
        self.init(kind: .exercise, contentID: exercise.id, title: exercise.title, imageUrl: exercise.imageUrl)!
    }

    init(_ recipe: Recipe) {
        self.init(kind: .recipe, contentID: recipe.id, title: recipe.title, imageUrl: recipe.imageUrl)!
    }

    /// Nil for media from a library that takes no comments.
    init?(_ media: MediaItem) {
        self.init(kind: media.contentKind, contentID: media.id, title: media.title, imageUrl: media.imageUrl)
    }
}

/// One comment, as `practice_comment_thread` serves it: the author as the
/// Community tab shows them ("Mara L."), never anyone either side has blocked.
struct PracticeComment: Identifiable, Hashable, Sendable {
    let id: UUID
    let author: CommunityMember
    let body: String
    let createdAt: Date
    /// Written by the member reading it: it reads "You", and offers Delete
    /// rather than Report and Block.
    let isMine: Bool
    /// Written by the guide this practice is credited to.
    let isGuide: Bool
}

/// What a comment may be before it's sent. The server holds the same limits
/// (`practice_comments.body`) and the rules no client can be trusted with:
/// links, language, the hourly allowance (`CommentRefusal`).
enum CommentDraft {
    /// Counted in Unicode scalars, as Postgres's `char_length` counts code
    /// points: an emoji with a skin tone is two, an accented letter typed as
    /// a base and a combining mark is two.
    static let maxLength = 500

    /// For the text field: cut to the limit as it's typed.
    static func capped(_ text: String) -> String {
        var scalars = 0
        for index in text.indices {
            scalars += text[index].unicodeScalars.count
            if scalars > maxLength { return String(text[..<index]) }
        }
        return text
    }

    /// What is sent: trimmed as the server trims it, or nil when nothing is
    /// left to say or there is too much.
    static func postable(_ text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.unicodeScalars.count <= maxLength else { return nil }
        return trimmed
    }

    /// How many characters are left, as the limit counts them.
    static func remaining(_ text: String) -> Int {
        maxLength - text.unicodeScalars.count
    }
}

/// A comment the server turned down for what it says, rather than failing to
/// take it (0032's `enforce_practice_comment_integrity`, which raises exactly
/// these messages). Each is worded for the person who wrote it: asked again
/// unchanged, the server says the same.
enum CommentRefusal: Error, Equatable, Sendable {
    case link
    case language
    case tooMany

    /// From the database's message for a refused insert (`Error.commentRefusal`
    /// reads it off the SDK's error). Nil for anything else.
    init?(message: String?) {
        switch message {
        case "comment_link":          self = .link
        case "comment_objectionable": self = .language
        case "comment_rate_limit":    self = .tooMany
        default:                      return nil
        }
    }

    var message: String {
        switch self {
        case .link:     "Comments can't include links. Take it out and post again."
        case .language: "Comments can't include that kind of language. Reword it and post again."
        case .tooMany:  "You've posted a lot in the last hour. Take a breath, and try again a little later."
        }
    }
}
