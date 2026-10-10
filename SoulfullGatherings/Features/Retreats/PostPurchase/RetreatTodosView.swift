//
//  RetreatTodosView.swift
//  Soulfull Gatherings
//
//  Pre-retreat checklist — dark, all-Geist translation of the Claude Design
//  `retreat-todos` brochure card. Completion is persisted device-locally by
//  `RetreatTripStore` (keyed by retreat id). The brochure's big "You're in."
//  payment celebration lives on the welcome hub instead (the immediate
//  post-pay moment), so this sub-screen opens calmer — a reassurance receipt
//  plus the checklist itself.
//

import SwiftUI

struct RetreatTodosView: View {
    @Environment(\.dismiss) private var dismiss
    let retreat: Retreat
    var onGoHome: () -> Void = {}

    @State private var trip = RetreatTripStore.shared

    private var exp: RetreatExperience? { retreat.experience }
    private var post: RetreatExperience.PostBooking? { exp?.postBooking }
    private var todos: [RetreatExperience.PostBooking.TodoItem] { post?.todos ?? [] }

    private var doneCount: Int { todos.filter { trip.isDone($0.id, retreatID: retreat.id) }.count }
    private var allDone: Bool { !todos.isEmpty && doneCount == todos.count }

    var body: some View {
        ZStack(alignment: .top) {
            RetreatPalette.espresso.ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {
                    hero
                    content
                }
            }
            .ignoresSafeArea(.container, edges: .top)

            // The glyph sits inside a 44pt target; this lines it up with the gutter.
            topBar.padding(.horizontal, Theme.gutter - 14).padding(.top, 8)

            VStack { Spacer(); homeBar }
        }
        .preferredColorScheme(.dark)
        .navigationBarBackButtonHidden(true)
        .toolbar(.hidden, for: .navigationBar)
    }

    // MARK: - Hero

    private var hero: some View {
        ZStack(alignment: .bottom) {
            Color.clear.frame(height: 320)
                .overlay { TripImage(post?.todosImage) }
                .clipped()
            LinearGradient(colors: [.black.opacity(0.5), .black.opacity(0.2), RetreatPalette.espresso.opacity(0.0), RetreatPalette.espresso],
                           startPoint: .top, endPoint: .bottom)
                .frame(height: 320)
            VStack(spacing: 14) {
                Image(systemName: "checkmark")
                    .font(.system(size: 24, weight: .thin))
                    .foregroundStyle(RetreatPalette.cream)
                Text("Your place is secured".uppercased())
                    .font(Theme.eyebrow(10)).tracking(3)
                    .foregroundStyle(RetreatPalette.cream.opacity(0.85))
                Text("A few things before you go")
                    .font(Theme.headline(30, weight: .light)).kerning(-0.6)
                    .foregroundStyle(RetreatPalette.cream)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                if let post {
                    receiptPill(post)
                }
            }
            .padding(.horizontal, Theme.gutter)
            .padding(.bottom, 18)
        }
        .frame(height: 320)
    }

    /// The receipt in one line of type — it was a glass pill.
    private func receiptPill(_ post: RetreatExperience.PostBooking) -> some View {
        Text("\(post.checkout.dueToday) deposit paid  ·  No. \(post.checkout.receiptNumber)")
            .font(Theme.body(11))
            .tracking(0.6)
            .foregroundStyle(RetreatPalette.cream)
    }

    // MARK: - Body

    private var content: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .firstTextBaseline) {
                Text("Before You Go".uppercased())
                    .font(Theme.eyebrow(10)).tracking(3).foregroundStyle(RetreatPalette.terracotta)
                Spacer()
                Text("\(doneCount) of \(todos.count) done")
                    .font(Theme.body(13)).foregroundStyle(RetreatPalette.creamSoft)
            }
            Text("Work through these at your own pace — your guide is notified as you go. Start with your enrollment call; everything else can follow.")
                .font(Theme.body(13)).foregroundStyle(RetreatPalette.creamSoft).lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)

            progressBar

            // Rows ruled by hairlines, not boxed one by one.
            VStack(spacing: 0) {
                ForEach(todos) { todo in
                    todoRow(todo)
                }
            }
            .padding(.top, 14)

            if allDone { allDoneCard }
        }
        .padding(.horizontal, Theme.gutter)
        .padding(.top, 28)
        .padding(.bottom, 150)
    }

    /// A hairline track with a solid run across it — no rounded ends.
    private var progressBar: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Rectangle().fill(RetreatPalette.coffee)
                Rectangle()
                    .fill(RetreatPalette.terracotta)
                    .frame(width: todos.isEmpty ? 0 : geo.size.width * CGFloat(doneCount) / CGFloat(todos.count))
            }
        }
        .frame(height: 2)
        .animation(Theme.Motion.reveal, value: doneCount)
    }

    private func todoRow(_ todo: RetreatExperience.PostBooking.TodoItem) -> some View {
        let done = trip.isDone(todo.id, retreatID: retreat.id)
        return Button {
            Haptics.select()
            trip.toggleTodo(todo.id, retreatID: retreat.id)
        } label: {
            HStack(alignment: .top, spacing: 14) {
                checkBox(done: done)
                VStack(alignment: .leading, spacing: 4) {
                    Text(todo.title)
                        .font(Theme.body(15))
                        .foregroundStyle(done ? RetreatPalette.muted : RetreatPalette.cream)
                        .strikethrough(done, color: RetreatPalette.muted)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(todo.detail)
                        .font(Theme.body(12)).foregroundStyle(RetreatPalette.muted).lineSpacing(2)
                        .fixedSize(horizontal: false, vertical: true)
                        .opacity(done ? 0.6 : 1)
                    if let tag = todo.tag {
                        Text(tag.uppercased())
                            .font(Theme.eyebrow(9)).tracking(1)
                            .foregroundStyle(todo.isMust ? RetreatPalette.espresso : RetreatPalette.terracotta)
                            .padding(.horizontal, 9).padding(.vertical, 4)
                            .background(
                                Rectangle().fill(todo.isMust ? RetreatPalette.terracotta : Color.clear)
                                    .overlay(Rectangle().strokeBorder(RetreatPalette.glassLine,
                                                                      lineWidth: todo.isMust ? 0 : Theme.hairline))
                            )
                            .opacity(done ? 0.55 : 1)
                            .padding(.top, 5)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(.vertical, 18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .overlay(alignment: .top) {
                Rectangle().fill(RetreatPalette.glassLine).frame(height: 0.5)
            }
            .contentShape(Rectangle())
            .animation(Theme.Motion.settle, value: done)
        }
        .buttonStyle(.soulPressableQuiet)
    }

    /// A square box, filled when ticked.
    private func checkBox(done: Bool) -> some View {
        ZStack {
            Rectangle()
                .fill(done ? RetreatPalette.olive : Color.clear)
                .overlay(Rectangle().strokeBorder(done ? RetreatPalette.olive : RetreatPalette.muted,
                                                  lineWidth: Theme.hairline))
            if done {
                Image(systemName: "checkmark").font(.system(size: 10, weight: .medium))
                    .foregroundStyle(RetreatPalette.cream)
            }
        }
        .frame(width: 18, height: 18)
        .padding(.top, 2)
    }

    private var allDoneCard: some View {
        VStack(spacing: 6) {
            Text("See you in \(retreat.country).")
                .font(Theme.headline(26, weight: .light)).italic().kerning(-0.3)
                .foregroundStyle(RetreatPalette.gold)
            Text("You're all set. We'll be in touch with the final details soon.")
                .font(Theme.body(13)).foregroundStyle(RetreatPalette.creamSoft)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(24)
        .overlay(Rectangle()
            .strokeBorder(RetreatPalette.glassLine, style: StrokeStyle(lineWidth: Theme.hairline, dash: [4, 4])))
        .padding(.top, 20)
    }

    // MARK: - Chrome

    private var topBar: some View {
        HStack {
            GlyphButton(systemName: "arrow.left") { dismiss() }
                .accessibilityLabel("Back")
            Spacer()
        }
    }

    private var homeBar: some View {
        VStack {
            Button {
                Haptics.tap(); onGoHome()
            } label: {
                Text("Go to my home")
                    .font(Theme.body(16, weight: .medium)).tracking(0.4)
                    .foregroundStyle(RetreatPalette.espresso)
                    .frame(maxWidth: .infinity).padding(.vertical, 18)
                    .background(Rectangle().fill(RetreatPalette.terracotta))
            }
            .buttonStyle(SoulPressableStyle(hapticOnPress: false))
        }
        .padding(.horizontal, Theme.gutter).padding(.top, 16).padding(.bottom, 28)
        .background(LinearGradient(colors: [RetreatPalette.espresso.opacity(0), RetreatPalette.espresso], startPoint: .top, endPoint: .bottom))
    }
}

#Preview {
    NavigationStack {
        RetreatTodosView(retreat: Retreat.mock[0])
            .toolbar(.hidden, for: .navigationBar)
    }
    .preferredColorScheme(.dark)
}
