//
//  RetreatAssistantViewModel.swift
//  Soulfull Gatherings
//
//  Drives the pre-retreat concierge chat. **Fully mocked** — no backend, no
//  Claude API (the Claude Design prototype's `window.claude.complete` is not
//  wired here). Replies are matched from the curated `assistantReplies` by
//  keyword, with a fallback, behind a short simulated typing delay. Wiring a
//  real assistant later means a Claude API call via an Edge Function (key
//  server-side) — out of scope for now.
//

import SwiftUI

@Observable @MainActor
final class RetreatAssistantViewModel {

    struct Message: Identifiable, Hashable {
        enum Role { case bot, user }
        let id = UUID()
        let role: Role
        let text: String
    }

    private(set) var messages: [Message] = []
    private(set) var isTyping = false
    private(set) var showSuggestions = true

    let suggestions: [String]

    private let replies: [RetreatExperience.PostBooking.CannedReply]
    private let fallback: String

    init(post: RetreatExperience.PostBooking?) {
        let intro = post?.assistantIntro
            ?? "Hi — I'm here for anything about your retreat. What's on your mind?"
        suggestions = post?.assistantSuggestions ?? []
        replies = post?.assistantReplies ?? []
        fallback = post?.assistantFallback
            ?? "I'm not quite sure on that one — our team can help at info@soulfullgatherings.com."
        messages = [Message(role: .bot, text: intro)]
    }

    func send(_ raw: String) {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !isTyping else { return }
        messages.append(Message(role: .user, text: text))
        showSuggestions = false
        isTyping = true
        Task { await respond(to: text) }
    }

    private func respond(to text: String) async {
        // Simulated "thinking" — purely cosmetic; there's no network call.
        try? await Task.sleep(for: .milliseconds(900))
        let reply = match(text)
        isTyping = false
        messages.append(Message(role: .bot, text: reply))
    }

    /// First canned reply whose keyword appears in the message, else the fallback.
    private func match(_ text: String) -> String {
        let lower = text.lowercased()
        for reply in replies where reply.keywords.contains(where: { lower.contains($0) }) {
            return reply.reply
        }
        return fallback
    }
}
