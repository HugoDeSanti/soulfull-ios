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

    private var exp: RetreatExperience? { retreat.experience ?? RetreatExperience.curated(for: retreat) }
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

            topBar.padding(.horizontal, 20).padding(.top, 8)

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
                .overlay { Image("mb-boats").resizable().scaledToFill() }
                .clipped()
            LinearGradient(colors: [.black.opacity(0.5), .black.opacity(0.2), RetreatPalette.espresso.opacity(0.0), RetreatPalette.espresso],
                           startPoint: .top, endPoint: .bottom)
                .frame(height: 320)
            VStack(spacing: 14) {
                Image(systemName: "checkmark")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 58, height: 58)
                    .soulGlass(in: Circle(), tint: RetreatPalette.glassTint, stroke: RetreatPalette.glassLine)
                Text("Your place is secured".uppercased())
                    .font(Theme.eyebrow(10)).tracking(3)
                    .foregroundStyle(.white.opacity(0.85))
                Text("A few things before you go")
                    .font(Theme.headline(30, weight: .semibold)).kerning(-0.5)
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                if let post {
                    receiptPill(post)
                }
            }
            .padding(.horizontal, 26)
            .padding(.bottom, 18)
        }
        .frame(height: 320)
    }

    private func receiptPill(_ post: RetreatExperience.PostBooking) -> some View {
        HStack(spacing: 8) {
            Text("\(post.checkout.dueToday) deposit paid")
                .font(Theme.body(11, weight: .medium))
            Circle().fill(.white.opacity(0.6)).frame(width: 3, height: 3)
            Text("No. \(post.checkout.receiptNumber)")
                .font(Theme.body(11))
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 14).padding(.vertical, 8)
        .soulGlassCapsule(tint: RetreatPalette.glassTint, stroke: RetreatPalette.glassLine)
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

            VStack(spacing: 12) {
                ForEach(todos) { todo in
                    todoRow(todo)
                }
            }
            .padding(.top, 6)

            if allDone { allDoneCard }
        }
        .padding(.horizontal, 24)
        .padding(.top, 24)
        .padding(.bottom, 150)
    }

    private var progressBar: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(RetreatPalette.espresso2)
                Capsule()
                    .fill(LinearGradient(colors: [RetreatPalette.olive, RetreatPalette.terracotta],
                                         startPoint: .leading, endPoint: .trailing))
                    .frame(width: todos.isEmpty ? 0 : geo.size.width * CGFloat(doneCount) / CGFloat(todos.count))
            }
        }
        .frame(height: 5)
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
                                Capsule().fill(todo.isMust ? RetreatPalette.terracotta : Color.clear)
                                    .overlay(Capsule().strokeBorder(RetreatPalette.glassLine, lineWidth: todo.isMust ? 0 : 1))
                            )
                            .opacity(done ? 0.55 : 1)
                            .padding(.top, 5)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .soulGlassCard(radius: 14, tint: RetreatPalette.glassTint, stroke: RetreatPalette.glassLine)
        }
        .buttonStyle(.soulPressableQuiet)
    }

    private func checkBox(done: Bool) -> some View {
        ZStack {
            Circle()
                .fill(done ? RetreatPalette.olive : Color.clear)
                .overlay(Circle().strokeBorder(done ? RetreatPalette.olive : RetreatPalette.muted, lineWidth: 1.5))
            if done {
                Image(systemName: "checkmark").font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.white)
            }
        }
        .frame(width: 26, height: 26)
        .padding(.top, 1)
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
        .padding(22)
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous)
            .strokeBorder(RetreatPalette.glassLine, style: StrokeStyle(lineWidth: 1, dash: [4, 4])))
        .padding(.top, 10)
    }

    // MARK: - Chrome

    private var topBar: some View {
        HStack {
            Button {
                Haptics.tap(); dismiss()
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 14, weight: .semibold)).foregroundStyle(.white)
                    .frame(width: 38, height: 38)
                    .soulGlass(in: Circle(), tint: RetreatPalette.glassTint, interactive: true, stroke: RetreatPalette.glassLine)
            }
            .buttonStyle(.soulPressableChip)
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
                    .frame(maxWidth: .infinity).padding(.vertical, 16)
                    .background(Capsule().fill(RetreatPalette.terracotta))
            }
            .buttonStyle(SoulPressableStyle(scale: 0.985, hapticOnPress: false, dim: false))
        }
        .padding(.horizontal, 22).padding(.top, 16).padding(.bottom, 28)
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
