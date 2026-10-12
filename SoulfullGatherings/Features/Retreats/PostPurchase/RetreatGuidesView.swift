//
//  RetreatGuidesView.swift
//  Soulfull Gatherings
//
//  Book a 1:1 session with a retreat guide — dark, all-Geist translation of the
//  Claude Design `mallorca-guides` brochure card. Joins the existing
//  `RetreatExperience.guides` with `PostBooking.offers` (matched by name);
//  bookings persist device-locally via `RetreatTripStore`.
//

import SwiftUI

struct RetreatGuidesView: View {
    @Environment(\.dismiss) private var dismiss
    let retreat: Retreat

    @State private var trip = RetreatTripStore.shared
    /// Guide names whose time-slot picker is currently open.
    @State private var expanded: Set<String> = []

    private typealias Offer = RetreatExperience.PostBooking.GuideOffer

    private var exp: RetreatExperience? { retreat.experience }
    private var post: RetreatExperience.PostBooking? { exp?.postBooking }
    private var guides: [RetreatExperience.Guide] { exp?.guides ?? [] }
    private var offers: [Offer] { exp?.postBooking?.offers ?? [] }

    private func offer(for guide: RetreatExperience.Guide) -> Offer? {
        offers.first { $0.guideName == guide.name }
    }

    var body: some View {
        ZStack(alignment: .top) {
            RetreatPalette.espresso.ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {
                    hero
                    list
                }
            }
            .ignoresSafeArea(.container, edges: .top)

            // The glyph sits inside a 44pt target; this lines it up with the gutter.
            topBar.padding(.horizontal, Theme.gutter - 14).padding(.top, 8)
        }
        .preferredColorScheme(.dark)
        .navigationBarBackButtonHidden(true)
        .toolbar(.hidden, for: .navigationBar)
    }

    // MARK: - Hero

    private var hero: some View {
        ZStack(alignment: .bottomLeading) {
            Color.clear.frame(height: 300)
                .overlay { TripImage(post?.guidesImage) }
                .clipped()
            LinearGradient(colors: [.black.opacity(0.45), .black.opacity(0.18), RetreatPalette.espresso.opacity(0.0), RetreatPalette.espresso],
                           startPoint: .top, endPoint: .bottom)
                .frame(height: 300)
            VStack(alignment: .leading, spacing: 10) {
                Text("Your Guides".uppercased())
                    .font(Theme.eyebrow(10)).tracking(3).foregroundStyle(RetreatPalette.terracotta)
                Text("Book a 1:1 session")
                    .font(Theme.headline(32, weight: .light)).kerning(-0.6)
                    .foregroundStyle(RetreatPalette.cream)
                Text("Each guide opens private sessions across the week. Reserve time with whoever you'd like to go deeper with.")
                    .font(Theme.body(13)).foregroundStyle(RetreatPalette.cream.opacity(0.9)).lineSpacing(2)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: 300, alignment: .leading)
            }
            .padding(.horizontal, Theme.gutter).padding(.bottom, 18)
        }
        .frame(height: 300)
    }

    // MARK: - List

    private var list: some View {
        VStack(spacing: 16) {
            ForEach(guides) { guide in
                guideCard(guide)
            }
            Text("Sessions take place at the villa during the retreat week. Times can be rescheduled with your guide on arrival.")
                .font(Theme.body(11)).foregroundStyle(RetreatPalette.muted)
                .multilineTextAlignment(.center).lineSpacing(2)
                .frame(maxWidth: .infinity)
                .padding(.top, 6)
        }
        .padding(.horizontal, Theme.gutter)
        .padding(.top, 28)
        .padding(.bottom, 64)
    }

    private func guideCard(_ guide: RetreatExperience.Guide) -> some View {
        let booked = trip.bookedSlot(guide: guide.name, retreatID: retreat.id)
        let isOpen = expanded.contains(guide.name)
        let theOffer = offer(for: guide)
        return VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 14) {
                Text(guide.initials)
                    .font(Theme.body(13, weight: .medium)).foregroundStyle(RetreatPalette.cream)
                    .frame(width: 46, height: 46).soulGlass(in: Circle(), tint: RetreatPalette.glassTint, stroke: RetreatPalette.glassLine)
                VStack(alignment: .leading, spacing: 3) {
                    Text(guide.name.uppercased())
                        .font(Theme.body(13, weight: .medium)).tracking(0.6).foregroundStyle(RetreatPalette.cream)
                    Text(guide.role)
                        .font(Theme.eyebrow(10)).tracking(1).textCase(.uppercase).foregroundStyle(RetreatPalette.muted)
                }
                Spacer(minLength: 8)
                bookButton(guide: guide, booked: booked != nil)
            }

            if let theOffer {
                Rectangle().fill(RetreatPalette.glassLine).frame(height: 0.5).padding(.vertical, 16)
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(theOffer.session).font(Theme.body(14)).foregroundStyle(RetreatPalette.cream)
                        Text(theOffer.duration).font(Theme.body(11)).foregroundStyle(RetreatPalette.muted)
                    }
                    Spacer()
                }

                if let booked {
                    confirmationRow(guide: guide, time: booked)
                }
                if isOpen {
                    slotPicker(guide: guide, offer: theOffer)
                }
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .soulGlassCard(tint: RetreatPalette.glassTint, stroke: RetreatPalette.glassLine)
    }

    private func bookButton(guide: RetreatExperience.Guide, booked: Bool) -> some View {
        Button {
            Haptics.tap()
            toggle(guide.name)
        } label: {
            Text(booked ? "Booked" : "Book 1:1")
                .font(Theme.eyebrow(11)).tracking(1.2).textCase(.uppercase)
                .foregroundStyle(booked ? RetreatPalette.espresso : RetreatPalette.cream)
                .padding(.horizontal, 16).padding(.vertical, 9)
                .background(
                    Rectangle().fill(booked ? RetreatPalette.terracotta : Color.clear)
                        .overlay(Rectangle().strokeBorder(booked ? Color.clear : RetreatPalette.cream.opacity(0.7),
                                                          lineWidth: Theme.hairline))
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.soulPressableQuiet)
    }

    private func slotPicker(guide: RetreatExperience.Guide, offer: Offer) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            Text("Choose a time".uppercased())
                .font(Theme.eyebrow(9)).tracking(1.5).foregroundStyle(RetreatPalette.terracotta)
            HStack(spacing: 8) {
                ForEach(offer.slots, id: \.self) { slot in
                    Button {
                        Haptics.success()
                        trip.book(guide: guide.name, slot: slot, retreatID: retreat.id)
                        expanded.remove(guide.name)
                    } label: {
                        Text(slot)
                            .font(Theme.body(12)).foregroundStyle(RetreatPalette.cream)
                            .lineLimit(1)
                            .padding(.horizontal, 12).padding(.vertical, 10)
                            .soulGlassCard(tint: RetreatPalette.glassTint, stroke: RetreatPalette.glassLine)
                    }
                    .buttonStyle(.soulPressable)
                }
            }
        }
        .padding(.top, 14)
    }

    private func confirmationRow(guide: RetreatExperience.Guide, time: String) -> some View {
        HStack(spacing: 10) {
            ZStack {
                Rectangle().fill(RetreatPalette.olive)
                Image(systemName: "checkmark").font(.system(size: 10, weight: .medium)).foregroundStyle(RetreatPalette.cream)
            }
            .frame(width: 20, height: 20)
            (Text("Booked · ").font(Theme.body(13)).foregroundStyle(RetreatPalette.creamSoft)
                + Text(time).font(Theme.body(13, weight: .medium)).foregroundStyle(RetreatPalette.cream))
            Spacer()
            Button {
                Haptics.tap()
                trip.cancelBooking(guide: guide.name, retreatID: retreat.id)
                expanded.remove(guide.name)
            } label: {
                Text("Cancel").font(Theme.body(11)).underline().foregroundStyle(RetreatPalette.muted)
            }
            .buttonStyle(.plain)
        }
        .padding(.top, 14)
    }

    private var topBar: some View {
        HStack {
            GlyphButton(systemName: "arrow.left") { dismiss() }
                .accessibilityLabel("Back")
            Spacer()
        }
    }

    private func toggle(_ name: String) {
        if expanded.contains(name) { expanded.remove(name) } else { expanded.insert(name) }
    }
}

// Its sample content (`Fixtures.swift`) exists only in DEBUG.
#if DEBUG
#Preview {
    NavigationStack {
        RetreatGuidesView(retreat: Retreat.mock[0])
            .toolbar(.hidden, for: .navigationBar)
    }
    .preferredColorScheme(.dark)
}
#endif
