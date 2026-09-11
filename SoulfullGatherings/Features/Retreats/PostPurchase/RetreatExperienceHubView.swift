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
//  in-app (see docs/PLAN-group-chat.md).
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

    private var exp: RetreatExperience? { retreat.experience ?? RetreatExperience.curated(for: retreat) }
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

            topBar
                .padding(.horizontal, 20)
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
                .overlay { Image("mb-welcome").resizable().scaledToFill() }
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
                    .font(Theme.headline(34, weight: .semibold)).kerning(-0.6)
                    .foregroundStyle(.white)
                    .lineLimit(2)
                    .minimumScaleFactor(0.7)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 8) {
                    pill(exp?.dateRange ?? retreat.when)
                    pill("\(daysToGo) days to go")
                    pill("Deposit paid", icon: "checkmark")
                }
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 22)
        }
        .frame(height: 380)
    }

    // MARK: - Body content

    private var content: some View {
        VStack(alignment: .leading, spacing: 28) {
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
        .padding(.horizontal, 24)
        .padding(.top, 26)
        .padding(.bottom, 60)
    }

    private var featuredTodo: some View {
        let total = post?.todos.count ?? 0
        let done = post?.todos.filter { trip.isDone($0.id, retreatID: retreat.id) }.count ?? 0
        return Button(action: onOpenTodos) {
            ZStack(alignment: .leading) {
                Color.clear.overlay { Image("mb-todos").resizable().scaledToFill() }.clipped()
                LinearGradient(colors: [.black.opacity(0.5), .black.opacity(0.8)],
                               startPoint: .top, endPoint: .bottom)
                VStack(alignment: .leading, spacing: 11) {
                    eyebrow("Before You Go")
                    Text("Your pre-retreat to-do's")
                        .font(Theme.headline(24, weight: .semibold)).kerning(-0.4)
                        .foregroundStyle(.white)
                    Text("A short checklist to complete before you go — calls, forms, flights and more.")
                        .font(Theme.body(13)).foregroundStyle(.white.opacity(0.85)).lineSpacing(2)
                        .fixedSize(horizontal: false, vertical: true)
                    progressBar(done: done, total: total)
                    HStack {
                        Text("\(done) of \(total) complete")
                            .font(Theme.body(11)).foregroundStyle(.white.opacity(0.8))
                        Spacer()
                        HStack(spacing: 5) {
                            Text("OPEN").font(Theme.eyebrow(10)).tracking(1.5)
                            Image(systemName: "chevron.right").font(.system(size: 10, weight: .semibold))
                        }
                        .foregroundStyle(RetreatPalette.terracotta)
                    }
                }
                .padding(20)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(RetreatPalette.glassLine, lineWidth: 1))
        }
        .buttonStyle(.soulPressable)
    }

    private func progressBar(done: Int, total: Int) -> some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.2))
                Capsule()
                    .fill(LinearGradient(colors: [RetreatPalette.olive, RetreatPalette.terracotta],
                                         startPoint: .leading, endPoint: .trailing))
                    .frame(width: total == 0 ? 0 : geo.size.width * CGFloat(done) / CGFloat(total))
            }
        }
        .frame(height: 5)
    }

    // MARK: - Experience grid

    private var experienceGrid: some View {
        VStack(alignment: .leading, spacing: 14) {
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
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(RetreatPalette.terracotta)
                    .frame(width: 36, height: 36)
                    .soulGlass(in: Circle(), tint: RetreatPalette.glassTint, stroke: RetreatPalette.glassLine)
                Spacer(minLength: 14)
                Text(title)
                    .font(Theme.headline(18, weight: .semibold)).kerning(-0.3)
                    .foregroundStyle(RetreatPalette.cream)
                Text(sub)
                    .font(Theme.body(11)).foregroundStyle(RetreatPalette.muted)
                    .padding(.top, 2)
            }
            .frame(maxWidth: .infinity, minHeight: 128, alignment: .leading)
            .padding(16)
            .soulGlassCard(radius: 16, tint: RetreatPalette.glassTint, stroke: RetreatPalette.glassLine)
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
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(RetreatPalette.terracotta)
                    .frame(width: 36, height: 36)
                    .soulGlass(in: Circle(), tint: RetreatPalette.glassTint, stroke: RetreatPalette.glassLine)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Questions before you arrive?")
                        .font(Theme.headline(17, weight: .semibold)).kerning(-0.3)
                        .foregroundStyle(RetreatPalette.cream)
                    Text("Email \(LegalLinks.supportEmail)")
                        .font(Theme.body(11)).foregroundStyle(RetreatPalette.muted)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(RetreatPalette.muted)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .soulGlassCard(radius: 16, tint: RetreatPalette.glassTint, stroke: RetreatPalette.glassLine)
        }
        .buttonStyle(.soulPressable)
    }

    // MARK: - Chrome

    private var topBar: some View {
        HStack {
            Button {
                Haptics.tap()
                dismiss()
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 38, height: 38)
                    .soulGlass(in: Circle(), tint: RetreatPalette.glassTint, interactive: true, stroke: RetreatPalette.glassLine)
            }
            .buttonStyle(.soulPressableChip)
            Spacer()
        }
    }

    private func pill(_ text: String, icon: String? = nil) -> some View {
        HStack(spacing: 6) {
            if let icon {
                Image(systemName: icon).font(.system(size: 10, weight: .bold))
            }
            Text(text).font(Theme.body(11)).tracking(0.3)
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .soulGlassCapsule(tint: RetreatPalette.glassTint, stroke: RetreatPalette.glassLine)
    }

    private func eyebrow(_ text: String) -> some View {
        Text(text.uppercased())
            .font(Theme.eyebrow(10)).tracking(3)
            .foregroundStyle(RetreatPalette.terracotta)
    }
}

#Preview {
    NavigationStack {
        RetreatExperienceHubView(retreat: Retreat.mock[0])
            .toolbar(.hidden, for: .navigationBar)
    }
    .environment(AppState().settings)
    .preferredColorScheme(.dark)
}
