//
//  StatTile.swift
//  Soulfull Gatherings
//
//  One figure of a practice table: the You tab's own four, and a friend's
//  (`FriendView`). Two rows of two, open on the page, a rule between them.
//

import SwiftUI

/// One number, open on the page: the figure, a small caps label beneath with
/// its mark, and a line of caption — Open's "5 / DAY STREAK". The figure
/// fades in once it's known and crossfades when it changes (finishing a
/// practice while the tab is open moves the streak in place).
struct StatTile: View {
    /// Nil until the ledger has loaded: a dash, never a zero that isn't true.
    let value: Int?
    let label: String
    let caption: String
    let systemImage: String
    var accent = false
    /// A live streak kept today: the flame breathes.
    var breathes = false
    let spoken: String
    let spokenValue: String?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Group {
                if let value {
                    Text(value.formatted())
                } else {
                    Text("–")
                }
            }
            .font(Theme.headline(44, weight: .light))
            .kerning(-1)
            .foregroundStyle(Theme.ink)
            .lineLimit(1)
            .minimumScaleFactor(0.6)
            .contentTransition(.opacity)

            HStack(spacing: 6) {
                // The one warm mark on the table: a streak that's alive.
                Image(systemName: systemImage)
                    .font(.system(size: 10, weight: .regular))
                    .foregroundStyle(accent ? Theme.ember : Theme.inkSoft)
                    .symbolEffect(.breathe, options: .repeat(.continuous),
                                  isActive: breathes && !reduceMotion)
                Text(label.uppercased())
                    .font(Theme.eyebrow(10))
                    .tracking(1.8)
                    .foregroundStyle(Theme.inkSoft)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .padding(.top, 6)

            // Two lines, reserved on every tile: the streak captions need the
            // room to say plainly what happened, and reserving it keeps both
            // rows of the table even whichever caption is showing.
            Text(caption)
                .font(Theme.body(12))
                .foregroundStyle(accent ? Theme.inkOnPhoto : Theme.inkSoft)
                .lineLimit(2, reservesSpace: true)
                .lineSpacing(1)
                .padding(.top, 8)
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        // Open on the page's photograph, not a tile.
        .onPhoto()
        .animation(Theme.Motion.reveal, value: value)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spoken)
        // The caption is part of what the tile says (that today is done, what counts
        // as a class), so VoiceOver reads it too.
        .accessibilityValue(spokenValue.map { value in
            let note = caption.trimmingCharacters(in: .whitespaces)
            return note.isEmpty ? value : "\(value), \(note)"
        } ?? "Loading")
    }
}
