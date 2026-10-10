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

    private var exp: RetreatExperience? { retreat.experience }
    private var post: RetreatExperience.PostBooking? { exp?.postBooking }
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

            // The glyph sits inside a 44pt target; this lines it up with the gutter.
            topBar.padding(.horizontal, Theme.gutter - 14).padding(.top, 8)
        }
        .preferredColorScheme(.dark)
        .navigationBarBackButtonHidden(true)
        .toolbar(.hidden, for: .navigationBar)
    }

    private var hero: some View {
        ZStack(alignment: .bottomLeading) {
            Color.clear.frame(height: 240)
                .overlay { TripImage(post?.packingImage) }
                .clipped()
            LinearGradient(colors: [.black.opacity(0.45), .black.opacity(0.15), RetreatPalette.espresso.opacity(0.0), RetreatPalette.espresso],
                           startPoint: .top, endPoint: .bottom)
                .frame(height: 240)
            VStack(alignment: .leading, spacing: 8) {
                Text("Before You Go".uppercased())
                    .font(Theme.eyebrow(10)).tracking(3).foregroundStyle(RetreatPalette.terracotta)
                Text("Packing list")
                    .font(Theme.headline(32, weight: .light)).kerning(-0.6)
                    .foregroundStyle(RetreatPalette.cream)
            }
            .padding(.horizontal, Theme.gutter).padding(.bottom, 18)
        }
        .frame(height: 240)
    }

    private var list: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("From riding gear to evening dinners — everything you'll want with you. Tap to tick items off as you pack.")
                .font(Theme.body(13)).foregroundStyle(RetreatPalette.creamSoft).lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.bottom, 24)

            // Rows ruled by hairlines, not boxed one by one.
            ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                row(index: index, item: item)
            }
        }
        .padding(.horizontal, Theme.gutter)
        .padding(.top, 28)
        .padding(.bottom, 64)
    }

    private func row(index: Int, item: String) -> some View {
        let done = trip.isDone(id(index), retreatID: retreat.id)
        return Button {
            Haptics.select()
            trip.toggleTodo(id(index), retreatID: retreat.id)
        } label: {
            HStack(spacing: 16) {
                // A square box, filled when ticked.
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
                Text(item)
                    .font(Theme.body(15))
                    .foregroundStyle(done ? RetreatPalette.muted : RetreatPalette.cream)
                    .strikethrough(done, color: RetreatPalette.muted)
                    .fixedSize(horizontal: false, vertical: true)
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

    private var topBar: some View {
        HStack {
            GlyphButton(systemName: "arrow.left") { dismiss() }
                .accessibilityLabel("Back")
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
