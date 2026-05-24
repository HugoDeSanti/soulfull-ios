//
//  RetreatsStackView.swift
//  Soulfull Gatherings
//
//  Foodle-style scrolling stack of retreat names with crossfading photo
//  backdrops. Tap an inactive row to scroll it to center; tap the active
//  row (or the bottom reserve card) to push the detail view.
//

import SwiftUI

struct RetreatsStackView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var vm = RetreatsViewModel()

    let onSelect: (Retreat) -> Void

    private let rowHeight: CGFloat = 84

    var body: some View {
        ZStack {
            // Crossfading photo backdrop
            backdrop

            // Top vignette
            LinearGradient(
                colors: [.black.opacity(0.30), .black.opacity(0.15), .black.opacity(0.45), .black.opacity(0.78)],
                startPoint: .top, endPoint: .bottom
            )
            .ignoresSafeArea()

            // Warm corner glow keyed to the active tone
            warmGlow

            VStack(spacing: 0) {
                header
                    .padding(.horizontal, 24)
                    .padding(.top, 16)

                stackScroller

                bottomCard
                    .padding(.horizontal, 16)
                    .padding(.bottom, 16)
            }
        }
        .preferredColorScheme(.dark)
        .navigationBarBackButtonHidden(true)
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 14) {
                Text("SOULFULL")
                    .font(Theme.body(14, weight: .medium))
                    .tracking(4)
                    .foregroundStyle(.white)
                Text("Intimate, luxurious gatherings around the world. Carefully chosen places, small groups, and practices that open the way.")
                    .font(Theme.body(12))
                    .foregroundStyle(Color.white.opacity(0.78))
                    .lineSpacing(2)
                    .frame(maxWidth: 240, alignment: .leading)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 10) {
                CircleIconButton(systemName: "xmark", size: 42) { dismiss() }
                ZStack {
                    Circle().strokeBorder(Color.white.opacity(0.40), lineWidth: 1)
                    Text(String(format: "%02d", vm.retreats.count))
                        .font(Theme.body(12))
                        .foregroundStyle(.white)
                }
                .frame(width: 42, height: 42)
            }
        }
    }

    // MARK: - Stack scroller

    private var stackScroller: some View {
        GeometryReader { geo in
            ScrollViewReader { proxy in
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 0) {
                        // Leading spacer so first row can center.
                        Color.clear.frame(height: max(0, geo.size.height / 2 - rowHeight / 2))

                        ForEach(Array(vm.retreats.enumerated()), id: \.element.id) { idx, r in
                            row(idx: idx, retreat: r)
                                .id(idx)
                                .onTapGesture {
                                    if idx == vm.activeIndex {
                                        Haptics.bump()
                                        onSelect(r)
                                    } else {
                                        withAnimation(.spring(response: 0.45, dampingFraction: 0.85)) {
                                            vm.setActive(idx)
                                            proxy.scrollTo(idx, anchor: .center)
                                        }
                                    }
                                }
                        }

                        Color.clear.frame(height: max(0, geo.size.height / 2 - rowHeight / 2))
                    }
                }
                .scrollTargetBehavior(.viewAligned)
                .mask(
                    LinearGradient(
                        colors: [.clear, .black, .black, .clear],
                        startPoint: .top, endPoint: .bottom
                    )
                )
            }
        }
    }

    private func row(idx: Int, retreat r: Retreat) -> some View {
        let isActive = idx == vm.activeIndex
        return HStack(alignment: .lastTextBaseline, spacing: 8) {
            Text(r.name)
                .font(.system(size: isActive ? 54 : 44, weight: isActive ? .semibold : .light))
                .kerning(-1.4)
                .foregroundStyle(.white)
                .underline(isActive, color: .white)
            Text("\(r.guests)")
                .font(Theme.body(12, weight: .medium))
                .baselineOffset(28)
                .foregroundStyle(isActive ? Color(red: 1, green: 0.82, blue: 0.6) : Color.white.opacity(0.7))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(height: rowHeight)
        .padding(.horizontal, 24)
        .opacity(isActive ? 1 : 0.42)
        .animation(.easeInOut(duration: 0.3), value: vm.activeIndex)
    }

    // MARK: - Bottom card

    private var bottomCard: some View {
        let r = vm.active
        return HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text("\(r.when) · \(r.country)".uppercased())
                    .font(Theme.eyebrow(10))
                    .tracking(2.5)
                    .foregroundStyle(Color.white.opacity(0.75))
                Text(r.tag)
                    .font(Theme.body(15, weight: .medium))
                    .foregroundStyle(.white)
                    .kerning(-0.2)
                    .lineLimit(1)
            }
            Spacer(minLength: 12)
            Button {
                Haptics.bump()
                onSelect(r)
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "play.fill").font(.system(size: 10))
                    Text("Reserve").font(Theme.body(13, weight: .medium))
                }
                .foregroundStyle(Color.black)
                .padding(.horizontal, 18)
                .padding(.vertical, 11)
                .background(Capsule().fill(Color.white))
            }
            .buttonStyle(.plain)
        }
        .padding(16)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 22)
                .strokeBorder(Color.white.opacity(0.18), lineWidth: 1)
        )
        .contentShape(Rectangle())
        .onTapGesture {
            Haptics.bump()
            onSelect(r)
        }
    }

    // MARK: - Backdrop crossfade

    private var backdrop: some View {
        ZStack {
            vm.active.tone.base.ignoresSafeArea()
            ForEach(Array(vm.retreats.enumerated()), id: \.element.id) { idx, r in
                Image(r.image)
                    .resizable().scaledToFill()
                    .opacity(idx == vm.activeIndex ? 1 : 0)
                    .animation(.easeInOut(duration: 0.7), value: vm.activeIndex)
                    .ignoresSafeArea()
            }
        }
    }

    private var warmGlow: some View {
        RadialGradient(
            colors: [vm.active.tone.top.opacity(0.55), .clear],
            center: UnitPoint(x: 0.22, y: -0.05),
            startRadius: 10, endRadius: 360
        )
        .blendMode(.screen)
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .animation(.easeInOut(duration: 0.7), value: vm.activeIndex)
    }
}

#Preview {
    NavigationStack {
        RetreatsStackView(onSelect: { _ in })
            .toolbar(.hidden, for: .navigationBar)
    }
    .preferredColorScheme(.dark)
}
