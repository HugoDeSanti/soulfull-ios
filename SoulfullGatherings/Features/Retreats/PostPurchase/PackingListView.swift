//
//  PackingListView.swift
//  Soulfull Gatherings
//
//  Pre-retreat packing checklist — dark, all-Geist. The brochure folded packing
//  into the to-do's screen; here it's its own tile/screen off the experience
//  hub. Checked items persist device-locally via `RetreatTripStore` under
//  `pack-`-prefixed ids so they stay separate from the to-do count.
//

import SwiftUI

struct PackingListView: View {
    @Environment(\.dismiss) private var dismiss
    let retreat: Retreat

    @State private var trip = RetreatTripStore.shared

    private var exp: RetreatExperience? { retreat.experience ?? RetreatExperience.curated(for: retreat) }
    private var items: [String] { exp?.postBooking?.packing ?? [] }

    private func id(_ index: Int) -> String { "pack-\(index)" }

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

    private var hero: some View {
        ZStack(alignment: .bottomLeading) {
            Color.clear.frame(height: 240)
                .overlay { Image("mb-villa").resizable().scaledToFill() }
                .clipped()
            LinearGradient(colors: [.black.opacity(0.45), .black.opacity(0.15), RetreatPalette.espresso.opacity(0.0), RetreatPalette.espresso],
                           startPoint: .top, endPoint: .bottom)
                .frame(height: 240)
            VStack(alignment: .leading, spacing: 8) {
                Text("Before You Go".uppercased())
                    .font(Theme.eyebrow(10)).tracking(3).foregroundStyle(RetreatPalette.terracotta)
                Text("Packing list")
                    .font(Theme.headline(32, weight: .semibold)).kerning(-0.5)
                    .foregroundStyle(.white)
            }
            .padding(.horizontal, 24).padding(.bottom, 18)
        }
        .frame(height: 240)
    }

    private var list: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("From riding gear to evening dinners — everything you'll want with you. Tap to tick items off as you pack.")
                .font(Theme.body(13)).foregroundStyle(RetreatPalette.creamSoft).lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.bottom, 6)

            ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                row(index: index, item: item)
            }
        }
        .padding(.horizontal, 24)
        .padding(.top, 22)
        .padding(.bottom, 60)
    }

    private func row(index: Int, item: String) -> some View {
        let done = trip.isDone(id(index), retreatID: retreat.id)
        return Button {
            Haptics.select()
            trip.toggleTodo(id(index), retreatID: retreat.id)
        } label: {
            HStack(spacing: 14) {
                ZStack {
                    Circle()
                        .fill(done ? RetreatPalette.olive : Color.clear)
                        .overlay(Circle().strokeBorder(done ? RetreatPalette.olive : RetreatPalette.muted, lineWidth: 1.5))
                    if done {
                        Image(systemName: "checkmark").font(.system(size: 12, weight: .bold)).foregroundStyle(.white)
                    }
                }
                .frame(width: 26, height: 26)
                Text(item)
                    .font(Theme.body(15))
                    .foregroundStyle(done ? RetreatPalette.muted : RetreatPalette.cream)
                    .strikethrough(done, color: RetreatPalette.muted)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .soulGlassCard(radius: 14, tint: RetreatPalette.glassTint, stroke: RetreatPalette.glassLine)
        }
        .buttonStyle(.soulPressableQuiet)
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
}

#Preview {
    NavigationStack {
        PackingListView(retreat: Retreat.mock[0])
            .toolbar(.hidden, for: .navigationBar)
    }
    .preferredColorScheme(.dark)
}
