//
//  PracticeListView.swift
//  Soulfull Gatherings
//
//  Lists every audio / video session for one practice category. The list is
//  open to anyone; tapping a row opens `PracticePlayerView` — which is a
//  practice, so it goes through `requireAccount` first.
//

import SwiftUI

struct PracticeListView: View {
    let category: PracticeCategory
    /// Injected by `PracticeRoot` so this view stays unaware of auth. The
    /// default runs straight through, which keeps previews working.
    var requireAccount: (@escaping () -> Void) -> Void = { $0() }

    @State private var vm = PracticeViewModel()
    @State private var nowPlaying: PracticeSession?
    /// Shared history, so a row can say "resume" instead of starting over.
    /// Reading it inside `body` is what registers the observation.
    private let history = PracticeProgressStore.shared

    var body: some View {
        PracticeListScaffold(
            title: category.title,
            blurb: category.blurb,
            systemImage: category.systemImage
        ) {
            // A reload (the tab coming back) keeps the rows it has: swapping
            // them for a spinner jumped the scroll back to the top. The
            // spinner is for a list with nothing in it yet — including before
            // the first load has begun, which is not yet "nothing here".
            if vm.sessions.isEmpty && (vm.isLoading || !vm.hasLoaded) {
                ProgressView()
                    .tint(Theme.ink)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 60)
            } else if let failure = vm.loadFailure {
                errorState(failure)
            } else if vm.isEmpty {
                emptyState
            } else {
                VStack(spacing: 0) {
                    if let note = category.safetyNote {
                        SafetyNoteCard(text: note)
                            .padding(.bottom, 36)
                    }
                    // Open rows on the ground, divided by hairlines, rather
                    // than a stack of boxes.
                    ForEach(vm.sessions) { session in
                        PressableCard(action: { requireAccount { nowPlaying = session } }) {
                            sessionRow(session)
                        }
                        .listReveal()
                    }
                    PracticeRule()
                }
            }
        }
        .task(id: category) { await vm.load(category: category) }
        .task { await history.refresh() }
        // No re-read when the player closes. Its last write lands in
        // `onDisappear`, after `nowPlaying` has already gone nil, and
        // `PracticeProgressStore.record` folds every write into `history`
        // the moment it's made. A forced read here started before that
        // write reached the server, could answer after it, and put the
        // older row back: "N MIN LEFT" went stale and the next resume
        // started early.
        .sheet(item: $nowPlaying) { session in
            PracticePlayerView(media: session.media)
        }
    }

    private func progress(_ session: PracticeSession) -> PracticeProgress? {
        history.progress(kind: .session, contentID: session.id)
    }

    // MARK: - Session row

    private func sessionRow(_ session: PracticeSession) -> some View {
        HStack(spacing: 16) {
            ZStack {
                CatalogImage(session.imageUrl) { $0.resizable().scaledToFill() }
                    .frame(width: 68, height: 68)
                    .clipped()
                Image(systemName: session.mediaKind == .video ? "play.fill" : "waveform")
                    .font(.system(size: 14, weight: .regular))
                    .foregroundStyle(Theme.ink)
                    .shadow(color: .black.opacity(0.5), radius: 4)
            }
            .overlay(
                Rectangle()
                    .strokeBorder(Theme.glassBorder, lineWidth: Theme.hairline)
            )

            VStack(alignment: .leading, spacing: 4) {
                Text(session.title)
                    .font(Theme.headline(17))
                    .foregroundStyle(Theme.ink)
                    .kerning(-0.2)
                    .lineLimit(1)
                Text("with \(session.lead)")
                    .font(Theme.body(12))
                    .foregroundStyle(Theme.muted)
                    .lineLimit(1)
                HStack(spacing: 6) {
                    Label(session.mediaKind.label, systemImage: session.mediaKind.systemImage)
                        .labelStyle(.titleAndIcon)
                    Text("·")
                    if let remaining = progress(session)?.remainingLabel, progress(session)?.isResumable == true {
                        Text(remaining)
                            .foregroundStyle(Theme.ember)
                    } else {
                        Text(session.durationLabel)
                    }
                }
                .font(Theme.eyebrow(10))
                .tracking(1)
                .textCase(.uppercase)
                .foregroundStyle(Theme.inkSoft)
                .padding(.top, 1)

                // A hairline of how far in they got. Only for a practice
                // genuinely under way — a finished one gets the seal instead.
                if let p = progress(session), p.isResumable {
                    ProgressRule(fraction: p.fraction)
                        .padding(.top, 5)
                }
                PresenceLine(kind: .session, contentID: session.id, faceSize: 18)
                    .padding(.top, 4)
            }
            Spacer()
            if progress(session)?.completed == true {
                Image(systemName: "checkmark.seal.fill")
                    .font(.system(size: 15))
                    .foregroundStyle(Theme.ember.opacity(0.85))
                    .accessibilityLabel("Completed")
            } else {
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .light))
                    .foregroundStyle(Theme.muted)
            }
        }
        .padding(.vertical, 18)
        .frame(maxWidth: .infinity)
        .overlay(alignment: .top) { PracticeRule() }
        .contentShape(Rectangle())
    }

    // MARK: - Empty state

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: category.systemImage)
                .font(.system(size: 30, weight: .light))
                .foregroundStyle(Theme.muted)
            Text("Nothing here yet.")
                .font(Theme.headline(20, weight: .light))
                .foregroundStyle(Theme.ink)
            Text("New \(category.title.lowercased()) sessions are on the way.")
                .font(Theme.body(13))
                .foregroundStyle(Theme.inkSoft)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 60)
    }

    /// The fetch itself failed — say why (offline, or our end) and offer a way
    /// back, rather than implying the library is empty.
    private func errorState(_ failure: PracticeLoadFailure) -> some View {
        VStack(spacing: 12) {
            Image(systemName: failure.systemImage)
                .font(.system(size: 30, weight: .light))
                .foregroundStyle(Theme.muted)
            Text(failure.title)
                .font(Theme.headline(20, weight: .light))
                .foregroundStyle(Theme.ink)
            Text(failure.detail)
                .font(Theme.body(13))
                .foregroundStyle(Theme.inkSoft)
                .multilineTextAlignment(.center)
            Button {
                Haptics.tap()
                Task { await vm.load(category: category) }
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
        .frame(maxWidth: .infinity)
        .padding(.top, 60)
    }
}

#Preview {
    NavigationStack {
        PracticeListView(category: .somatic)
            .toolbar(.hidden, for: .navigationBar)
    }
    .preferredColorScheme(.dark)
}
