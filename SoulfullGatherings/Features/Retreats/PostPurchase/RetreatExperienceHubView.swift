//
//  RetreatExperienceHubView.swift
//  Soulfull Gatherings
//
//  Post-purchase hub — the landing screen once a retreat is reserved. A dark,
//  all-Geist translation of the Claude Design `mallorca-welcome` brochure card
//  (the mirror is brochure-light; the app uses the existing dark theme): a
//  full-bleed hero, a greeting, the featured pre-trip to-do card with live
//  progress from `RetreatTripStore`, and a grid into the rest of the trip.
//  The "Group chat" tile opens the retreat's external WhatsApp invite
//  (`retreat.groupChatURL`, sourced from Supabase) — group chat is not built
//  in-app (a parked design: `git show a755604:docs/PLAN-group-chat.md`).
//

import SwiftUI

struct RetreatExperienceHubView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @Environment(AppSettings.self) private var settings

    let retreat: Retreat
    var onOpenTodos: () -> Void = {}
    var onOpenGuides: () -> Void = {}
    var onOpenPacking: () -> Void = {}
    var onOpenDetail: () -> Void = {}

    @State private var trip = RetreatTripStore.shared

    private var exp: RetreatExperience? { retreat.experience }
    private var post: RetreatExperience.PostBooking? { exp?.postBooking }

    /// Prefer the signed-in member's name; fall back to the curated mock name.
    private var memberName: String {
        let name = settings.userName.trimmingCharacters(in: .whitespaces)
        if !name.isEmpty { return name }
        return post?.memberName ?? "traveler"
    }

    private var daysToGo: Int {
        let cal = Calendar.current
        let from = cal.startOfDay(for: Date())
        let to = cal.startOfDay(for: retreat.startDate)
        return max(0, cal.dateComponents([.day], from: from, to: to).day ?? 0)
    }

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
            topBar
                .padding(.horizontal, Theme.gutter - 14)
                .padding(.top, 8)
        }
        .preferredColorScheme(.dark)
        .navigationBarBackButtonHidden(true)
        .toolbar(.hidden, for: .navigationBar)
    }

    // MARK: - Hero

    private var hero: some View {
        ZStack(alignment: .bottomLeading) {
            Color.clear
                .frame(height: 380)
                .overlay { TripImage(post?.welcomeImage) }
                .clipped()

            LinearGradient(
                colors: [.black.opacity(0.45), .black.opacity(0.12), RetreatPalette.espresso.opacity(0.0), RetreatPalette.espresso],
                startPoint: .top, endPoint: .bottom
            )
            .frame(height: 380)

            VStack(alignment: .leading, spacing: 14) {
                Text("You're going to \(retreat.country)".uppercased())
                    .font(Theme.eyebrow(10)).tracking(3)
                    .foregroundStyle(RetreatPalette.terracotta)
                Text("Welcome to the \(retreat.name) Experience")
                    .font(Theme.headline(34, weight: .light)).kerning(-0.8)
                    .foregroundStyle(RetreatPalette.cream)
                    .lineLimit(2)
                    .minimumScaleFactor(0.7)
                    .fixedSize(horizontal: false, vertical: true)
                // The particulars in one line — they were three glass pills.
                Text([exp?.dateRange ?? retreat.when, "\(daysToGo) days to go", "Deposit paid"]
                        .joined(separator: "  ·  "))
                    .font(Theme.body(11)).tracking(0.6)
                    .foregroundStyle(RetreatPalette.cream)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .padding(.horizontal, Theme.gutter)
            .padding(.bottom, 22)
        }
        .frame(height: 380)
    }

    // MARK: - Body content

    private var content: some View {
        VStack(alignment: .leading, spacing: 44) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Your place is secured, \(memberName).")
                    .font(Theme.headline(24, weight: .light)).kerning(-0.3)
                    .foregroundStyle(RetreatPalette.cream)
                    .fixedSize(horizontal: false, vertical: true)
                Text("Everything you need lives here. Let's get you ready for the week — start with the essentials below.")
                    .font(Theme.body(14)).foregroundStyle(RetreatPalette.creamSoft).lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if post != nil { featuredTodo }

            experienceGrid
        }
        .padding(.horizontal, Theme.gutter)
        .padding(.top, 28)
        .padding(.bottom, 64)
    }

    private var featuredTodo: some View {
        let total = post?.todos.count ?? 0
        let done = post?.todos.filter { trip.isDone($0.id, retreatID: retreat.id) }.count ?? 0
        return Button(action: onOpenTodos) {
            ZStack(alignment: .leading) {
                Color.clear.overlay { TripImage(post?.featuredTodoImage) }.clipped()
                LinearGradient(colors: [.black.opacity(0.5), .black.opacity(0.8)],
                               startPoint: .top, endPoint: .bottom)
                VStack(alignment: .leading, spacing: 11) {
                    eyebrow("Before You Go")
                    Text("Your pre-retreat to-do's")
                        .font(Theme.headline(24, weight: .light)).kerning(-0.4)
                        .foregroundStyle(RetreatPalette.cream)
                    Text("A short checklist to complete before you go — calls, forms, flights and more.")
                        .font(Theme.body(13)).foregroundStyle(RetreatPalette.cream.opacity(0.85)).lineSpacing(2)
                        .fixedSize(horizontal: false, vertical: true)
                    progressBar(done: done, total: total)
                    HStack {
                        Text("\(done) of \(total) complete")
                            .font(Theme.body(11)).foregroundStyle(RetreatPalette.cream.opacity(0.8))
                        Spacer()
                        HStack(spacing: 6) {
                            Text("OPEN").font(Theme.eyebrow(10)).tracking(1.5)
                            Image(systemName: "arrow.right").font(.system(size: 10, weight: .regular))
                        }
                        .foregroundStyle(RetreatPalette.terracotta)
                    }
                }
                .padding(20)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .clipped()
            .overlay(Rectangle().strokeBorder(RetreatPalette.glassLine, lineWidth: Theme.hairline))
            .contentShape(Rectangle())
        }
        .buttonStyle(.soulPressable)
    }

    /// A hairline track with a solid run across it — no rounded ends.
    private func progressBar(done: Int, total: Int) -> some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Rectangle().fill(RetreatPalette.cream.opacity(0.2))
                Rectangle()
                    .fill(RetreatPalette.terracotta)
                    .frame(width: total == 0 ? 0 : geo.size.width * CGFloat(done) / CGFloat(total))
            }
        }
        .frame(height: 2)
        .animation(Theme.Motion.reveal, value: done)
    }

    // MARK: - Experience grid

    private var experienceGrid: some View {
        VStack(alignment: .leading, spacing: 16) {
            eyebrow("Your Experience")
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)],
                      spacing: 12) {
                gridTile(icon: "clock", title: "Daily rhythm", sub: "Move · Explore · Recover", action: onOpenDetail)
                gridTile(icon: "person.2", title: "Your guides", sub: "Book a 1:1 session", action: onOpenGuides)
                if let url = retreat.groupChatURL {
                    gridTile(icon: "bubble.left.and.bubble.right", title: "Group chat", sub: "Meet your group") {
                        Haptics.tap()
                        openURL(url)
                    }
                }
                gridTile(icon: "checklist", title: "Packing list", sub: "What to bring", action: onOpenPacking)
            }
            supportTile
        }
    }

    private func gridTile(icon: String, title: String, sub: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 0) {
                Image(systemName: icon)
                    .font(.system(size: 17, weight: .light))
                    .foregroundStyle(RetreatPalette.terracotta)
                Spacer(minLength: 18)
                Text(title)
                    .font(Theme.headline(18, weight: .regular)).kerning(-0.3)
                    .foregroundStyle(RetreatPalette.cream)
                Text(sub)
                    .font(Theme.body(11)).foregroundStyle(RetreatPalette.muted)
                    .padding(.top, 2)
            }
            .frame(maxWidth: .infinity, minHeight: 128, alignment: .leading)
            .padding(20)
            .soulGlassCard(tint: RetreatPalette.glassTint, stroke: RetreatPalette.glassLine)
        }
        .buttonStyle(.soulPressable)
    }

    /// This was a mocked "assistant" chat — canned, keyword-matched replies
    /// dressed as a concierge. The app has no AI and will not have one, so the
    /// tile now does the thing the chat only imitated: puts the member in front
    /// of a human. The address sits in the subtitle so the tile still says
    /// something useful on a device with no mail account configured.
    private var supportTile: some View {
        Button {
            Haptics.tap()
            openURL(LegalLinks.supportMail)
        } label: {
            HStack(spacing: 14) {
                Image(systemName: "envelope")
                    .font(.system(size: 17, weight: .light))
                    .foregroundStyle(RetreatPalette.terracotta)
                    .frame(width: 24)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Questions before you arrive?")
                        .font(Theme.headline(17, weight: .regular)).kerning(-0.3)
                        .foregroundStyle(RetreatPalette.cream)
                    Text("Email \(LegalLinks.supportEmail)")
                        .font(Theme.body(11)).foregroundStyle(RetreatPalette.muted)
                }
                Spacer(minLength: 0)
                Image(systemName: "arrow.right")
                    .font(.system(size: 12, weight: .light))
                    .foregroundStyle(RetreatPalette.muted)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(20)
            .soulGlassCard(tint: RetreatPalette.glassTint, stroke: RetreatPalette.glassLine)
        }
        .buttonStyle(.soulPressable)
    }

    // MARK: - Chrome

    private var topBar: some View {
        HStack {
            GlyphButton(systemName: "arrow.left") { dismiss() }
                .accessibilityLabel("Back")
            Spacer()
        }
    }

    private func eyebrow(_ text: String) -> some View {
        Text(text.uppercased())
            .font(Theme.eyebrow(10)).tracking(3)
            .foregroundStyle(RetreatPalette.terracotta)
    }
}

// Its sample content (`Fixtures.swift`) exists only in DEBUG.
#if DEBUG
#Preview {
    NavigationStack {
        RetreatExperienceHubView(retreat: Retreat.mock[0])
            .toolbar(.hidden, for: .navigationBar)
    }
    .environment(AppState().settings)
    .preferredColorScheme(.dark)
}
#endif
