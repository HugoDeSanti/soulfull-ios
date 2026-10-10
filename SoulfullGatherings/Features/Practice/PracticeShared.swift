//
//  PracticeShared.swift
//  Soulfull Gatherings
//
//  Shared chrome for the Practice feature: the back bar used on every pushed
//  screen, and the list scaffold (blurred backdrop + back bar + header) that
//  every category / section list is built on.
//

import SwiftUI

// MARK: - Back bar (pops the current pushed screen)

struct PracticeBackBar: View {
    var label: String = "Practices"
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        HStack {
            Button {
                Haptics.tap()
                dismiss()
            } label: {
                // A bare ← and the page it returns to, as Open draws it.
                HStack(spacing: 10) {
                    Image(systemName: "arrow.left").font(.system(size: 15, weight: .light))
                    Text(label)
                        .font(Theme.body(13))
                }
                .foregroundStyle(Theme.ink)
                // It sits on the page's photograph.
                .onPhoto()
                // A 44pt-tall target, gap included — the link answered only on
                // its arrow and its 13pt text. The negative padding below
                // gives the layout its old height back.
                .padding(.vertical, 14)
                .padding(.trailing, 16)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.vertical, -14)
            .accessibilityIdentifier("back-bar")
            Spacer()
        }
    }
}

// MARK: - List scaffold (backdrop + back bar + icon/title/blurb header)

struct PracticeListScaffold<Content: View>: View {
    let title: String
    let blurb: String
    let systemImage: String
    let backdrop: String
    var backLabel: String = "Practices"
    @ViewBuilder var content: Content

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                PracticeBackBar(label: backLabel)
                header
                    .padding(.top, 32)
                    .padding(.bottom, 44)
                content
                Color.clear.frame(height: 120)
            }
            .padding(.top, 8)
            .padding(.horizontal, Theme.gutter)
        }
        .scrollIndicators(.hidden)
        .statusBarFade()
        .background {
            PhotoBackdrop(imageName: backdrop, blur: 22, darken: 0.78)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: systemImage)
                    .font(.system(size: 12, weight: .regular))
                Text(title.uppercased())
                    .font(Theme.eyebrow(11))
                    .tracking(3)
            }
            .foregroundStyle(Theme.inkSoft)

            Text(title)
                .font(Theme.headline(34, weight: .light))
                .foregroundStyle(Theme.ink)
                .kerning(-0.8)
            Text(blurb)
                .font(Theme.body(14))
                .foregroundStyle(Theme.inkOnPhoto)
                .lineSpacing(3)
                .padding(.top, 4)
        }
        // Laid straight on the category's photograph.
        .onPhoto()
    }
}

// MARK: - Hairline rule

/// The rule between rows and sections on a Practice page — Open's divider:
/// a half-point line of `Theme.line` across the measure, in place of a box
/// around each row.
struct PracticeRule: View {
    var body: some View {
        Rectangle()
            .fill(Theme.line)
            .frame(height: 0.5)
            .frame(maxWidth: .infinity)
            .accessibilityHidden(true)
    }
}

// MARK: - A written library with nothing to list

/// What a written library's list shows in place of rows it doesn't have: a
/// spinner while the first read is under way, why it failed — offline or our
/// end, see `Error.isOffline` — with a retry, or an honest "nothing here yet"
/// once the table has answered empty. Only ever before a first successful
/// read: after one, the library is remembered and the rows show offline too.
struct WrittenLibraryPlaceholder: View {
    let item: PracticeMenuItem
    /// What the list holds, in the plural: "prompts", "sequences", "recipes".
    let noun: String
    private let store = WrittenPracticeStore.shared

    var body: some View {
        Group {
            switch store.status {
            case .failed(let offline) where !store.isLoading:
                message(offline ? "wifi.slash" : "exclamationmark.circle",
                        title: offline ? "No internet connection" : "Couldn't load the \(noun)",
                        detail: offline ? "You'll need to be online to load the \(noun) the first time. Reconnect and try again."
                                        : "Something went wrong at our end. Please try again in a moment.",
                        retry: true)
            case .done where !store.isLoading:
                message(item.systemImage, title: "Nothing here yet.",
                        detail: "New \(noun) are on the way.", retry: false)
            default:
                ProgressView()
                    .tint(Theme.ink)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 60)
            }
        }
    }

    private func message(_ systemImage: String, title: String, detail: String, retry: Bool) -> some View {
        VStack(spacing: 12) {
            // On the list's photograph: the type carries its own ground.
            Group {
                Image(systemName: systemImage)
                    .font(.system(size: 30, weight: .light))
                    .foregroundStyle(Theme.inkSoft)
                Text(title)
                    .font(Theme.headline(20, weight: .light))
                    .foregroundStyle(Theme.ink)
                Text(detail)
                    .font(Theme.body(13))
                    .foregroundStyle(Theme.inkOnPhoto)
                    .multilineTextAlignment(.center)
            }
            .onPhoto()
            if retry {
                Button {
                    Haptics.tap()
                    Task { await store.refresh() }
                } label: {
                    Text("Try again")
                        .font(Theme.body(13, weight: .medium))
                        .foregroundStyle(Theme.ink)
                        .padding(.horizontal, 22)
                        .padding(.vertical, 12)
                        .soulGlassCard()
                }
                .buttonStyle(.soulPressableQuiet)
                .padding(.top, 4)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 60)
    }
}

// MARK: - Numbered step row (shared by movement sequences and recipes)

/// A step with its number set as a folio ("01"), the way the landing numbers
/// its cards — a numeral in the margin, not a numeral in a disc.
struct NumberedStepRow: View {
    let index: Int
    let title: String
    var detail: String? = nil

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 16) {
            Text(String(format: "%02d", index))
                .font(Theme.body(12, weight: .medium))
                .tracking(1.5)
                // inkSoft, not muted: on a movement page the row sits on the
                // sequence's photograph, where muted sinks.
                .foregroundStyle(Theme.inkSoft)
                .frame(width: 26, alignment: .leading)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(Theme.body(15))
                    .foregroundStyle(Theme.ink)
                    .fixedSize(horizontal: false, vertical: true)
                if let detail {
                    Text(detail)
                        .font(Theme.eyebrow(11))
                        .tracking(1)
                        .textCase(.uppercase)
                        .foregroundStyle(Theme.inkSoft)
                }
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Progress rule

/// A hairline showing how far into a practice the member got. Quiet by design:
/// it sits under a row's metadata and reads as an underline until you look at
/// it, which is the right weight for something that shouldn't feel like a task
/// tracker.
struct ProgressRule: View {
    /// 0–1.
    let fraction: Double
    var width: CGFloat = 92

    var body: some View {
        ZStack(alignment: .leading) {
            Rectangle()
                .fill(Theme.ink.opacity(0.18))
                .frame(width: width, height: 1)
            Rectangle()
                .fill(Theme.ember.opacity(0.85))
                .frame(width: max(3, width * min(1, max(0, fraction))), height: 1)
        }
        .accessibilityHidden(true)
    }
}

// MARK: - Safety note

/// "Before you begin", above a track whose practices can affect the body
/// (`PracticeCategory.safetyNote`): breathwork and somatic work. Set open on
/// the ground under a hairline, like a note at the head of a page, and read
/// once on the way in — not a modal to dismiss every time.
struct SafetyNoteCard: View {
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: "heart.text.square")
                .font(.system(size: 15, weight: .light))
                .foregroundStyle(Theme.ember)
                .padding(.top, 1)
            VStack(alignment: .leading, spacing: 8) {
                Text("BEFORE YOU BEGIN")
                    .font(Theme.eyebrow(10))
                    .tracking(2)
                    .foregroundStyle(Theme.inkSoft)
                Text(text)
                    .font(Theme.body(13))
                    .foregroundStyle(Theme.inkOnPhoto)
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
            }
            // Open on the list's photograph, not on glass.
            .onPhoto()
            Spacer(minLength: 0)
        }
        .padding(.top, 20)
        .overlay(alignment: .top) { PracticeRule() }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("safety-note")
    }
}
