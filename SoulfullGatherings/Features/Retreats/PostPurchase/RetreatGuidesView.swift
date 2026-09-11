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

            topBar.padding(.horizontal, 20).padding(.top, 8)
        }
        .preferredColorScheme(.dark)
        .navigationBarBackButtonHidden(true)
        .toolbar(.hidden, for: .navigationBar)
    }

    // MARK: - Hero

    private var hero: some View {
        ZStack(alignment: .bottomLeading) {
            Color.clear.frame(height: 300)
                .overlay { Image("mb-massage").resizable().scaledToFill() }
                .clipped()
            LinearGradient(colors: [.black.opacity(0.45), .black.opacity(0.18), RetreatPalette.espresso.opacity(0.0), RetreatPalette.espresso],
                           startPoint: .top, endPoint: .bottom)
                .frame(height: 300)
            VStack(alignment: .leading, spacing: 10) {
                Text("Your Guides".uppercased())
                    .font(Theme.eyebrow(10)).tracking(3).foregroundStyle(RetreatPalette.terracotta)
                Text("Book a 1:1 session")
                    .font(Theme.headline(32, weight: .semibold)).kerning(-0.5)
                    .foregroundStyle(.white)
                Text("Each guide opens private sessions across the week. Reserve time with whoever you'd like to go deeper with.")
                    .font(Theme.body(13)).foregroundStyle(.white.opacity(0.9)).lineSpacing(2)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: 300, alignment: .leading)
            }
            .padding(.horizontal, 24).padding(.bottom, 18)
        }
        .frame(height: 300)
    }

    // MARK: - List

    private var list: some View {
        VStack(spacing: 14) {
            ForEach(guides) { guide in
                guideCard(guide)
            }
            Text("Sessions take place at the villa during the retreat week. Times can be rescheduled with your guide on arrival.")
                .font(Theme.body(11)).foregroundStyle(RetreatPalette.muted)
                .multilineTextAlignment(.center).lineSpacing(2)
                .frame(maxWidth: .infinity)
                .padding(.top, 6)
        }
        .padding(.horizontal, 24)
        .padding(.top, 22)
        .padding(.bottom, 60)
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
                Rectangle().fill(RetreatPalette.glassLine).frame(height: 1).padding(.vertical, 14)
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
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .soulGlassCard(radius: 18, tint: RetreatPalette.glassTint, stroke: RetreatPalette.glassLine)
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
                    Capsule().fill(booked ? RetreatPalette.terracotta : Color.clear)
                        .overlay(Capsule().strokeBorder(booked ? Color.clear : RetreatPalette.cream, lineWidth: 1))
                )
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
                            .padding(.horizontal, 12).padding(.vertical, 9)
                            .soulGlassCapsule(tint: RetreatPalette.glassTint, stroke: RetreatPalette.glassLine)
                    }
                    .buttonStyle(.soulPressableChip)
                }
            }
        }
        .padding(.top, 14)
    }

    private func confirmationRow(guide: RetreatExperience.Guide, time: String) -> some View {
        HStack(spacing: 10) {
            ZStack {
                Circle().fill(RetreatPalette.olive)
                Image(systemName: "checkmark").font(.system(size: 11, weight: .bold)).foregroundStyle(.white)
            }
            .frame(width: 24, height: 24)
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

    private func toggle(_ name: String) {
        if expanded.contains(name) { expanded.remove(name) } else { expanded.insert(name) }
    }
}

#Preview {
    NavigationStack {
        RetreatGuidesView(retreat: Retreat.mock[0])
            .toolbar(.hidden, for: .navigationBar)
    }
    .preferredColorScheme(.dark)
}
