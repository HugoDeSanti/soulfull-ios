//
//  RetreatsStackView.swift
//  Soulfull Gatherings
//
//  Two ways to browse the gatherings:
//
//  STACK — the signature typographic scroller: retreat names snap to center
//  over a crossfading full-bleed photo.
//
//  CATALOG — pinch out (or tap the grid button) and the stack recedes into a
//  magazine contact sheet of covers. Tap a cover to fly back into the stack
//  focused on that retreat; pinch in to leave the catalog.
//
//  The pinch is interactive: the live magnification scrubs scale/blur before
//  committing with a spring, so the zoom feels attached to the fingers.
//

import SwiftUI

struct RetreatsStackView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var vm = RetreatsViewModel()
    @State private var scrollerHeight: CGFloat = 0

    // Browse mode + live pinch scrub.
    private enum Mode { case stack, catalog }
    @State private var mode: Mode = .stack
    @State private var pinch: CGFloat = 1

    let onSelect: (Retreat) -> Void

    private let rowHeight: CGFloat = 84
    private let commitSpring = Animation.spring(response: 0.5, dampingFraction: 0.82)

    var body: some View {
        ZStack {
            backdrop

            if vm.isLoading {
                ProgressView().tint(.white)
            } else if let msg = vm.loadError {
                errorState(msg)
            } else {
                // The stack stays mounted under the catalog so its scroll
                // state survives — tapping a cover animates the live
                // scroller to the chosen retreat as the catalog lifts.
                stackMode
                    .allowsHitTesting(mode == .stack)

                if mode == .catalog {
                    catalogMode
                        .transition(.editorialRise)
                }
            }
        }
        .ignoresSafeArea()
        // High priority so the two-finger pinch never doubles as a tap on
        // rows/covers underneath; single-finger interactions pass through.
        .highPriorityGesture(pinchGesture)
        .task { await vm.load() }
        .preferredColorScheme(.dark)
        .navigationBarBackButtonHidden(true)
    }

    // MARK: - Pinch (zoom out to catalog / back in to stack)

    private var pinchGesture: some Gesture {
        MagnifyGesture()
            .onChanged { value in
                pinch = value.magnification
                if pinch < 0.97 || pinch > 1.03 { Haptics.prepare() }
            }
            .onEnded { value in
                let m = value.magnification
                withAnimation(commitSpring) {
                    if mode == .stack, m < 0.82 {
                        Haptics.bump()
                        mode = .catalog
                    } else if mode == .catalog, m > 1.22 {
                        Haptics.bump()
                        mode = .stack
                    }
                    pinch = 1
                }
            }
    }

    /// Live scrub applied while the fingers are down — recede when pinching
    /// out of the stack, swell slightly when pinching out of the catalog.
    private var scrub: CGFloat {
        switch mode {
        case .stack:   return min(1, max(0.88, 0.88 + 0.12 * pinch))
        case .catalog: return max(1, min(1.06, pinch))
        }
    }

    // MARK: - Stack mode

    private var stackMode: some View {
        VStack(spacing: 0) {
            header
            stackScroller
            bottomCard
                .padding(.horizontal, 16)
                .padding(.bottom, 110)
        }
        .scaleEffect(mode == .catalog ? 0.92 : scrub)
        .blur(radius: mode == .catalog ? 22 : (1 - scrub) * 24)
        .opacity(mode == .catalog ? 0.25 : 1)
    }

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
                CircleIconButton(systemName: "xmark", size: 42) { Haptics.tap(); dismiss() }
                    .accessibilityLabel("Close")
                CircleIconButton(systemName: "square.grid.2x2", size: 42) {
                    withAnimation(commitSpring) { mode = .catalog }
                }
                .accessibilityLabel("Catalog")
                ZStack {
                    Circle().strokeBorder(Color.white.opacity(0.40), lineWidth: 1)
                    Text(String(format: "%02d", vm.retreats.count))
                        .font(Theme.body(12))
                        .foregroundStyle(.white)
                }
                .frame(width: 42, height: 42)
            }
        }
        .safeAreaPadding(.top)
        .padding(.top, 36)
        .padding(.horizontal, 24)
    }

    private var stackScroller: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 0) {
                ForEach(Array(vm.retreats.enumerated()), id: \.element.id) { idx, r in
                    row(idx: idx, retreat: r)
                        .id(idx)
                        .onTapGesture {
                            if idx == vm.activeIndex {
                                Haptics.bump()
                                onSelect(r)
                            } else {
                                Haptics.select()
                                withAnimation(.spring(response: 0.45, dampingFraction: 0.85)) {
                                    vm.activeIndex = idx
                                }
                            }
                        }
                }
            }
            .scrollTargetLayout()
        }
        .scrollTargetBehavior(.viewAligned)
        .scrollPosition(id: activeIndexBinding, anchor: .center)
        // Symmetric inset (half the viewport, minus half a row) lets the first
        // and last rows scroll all the way to center — the same job the manual
        // spacers used to do, but understood by `viewAligned` so its snap and
        // our centering agree instead of fighting.
        .contentMargins(.vertical, max(0, (scrollerHeight - rowHeight) / 2), for: .scrollContent)
        .onGeometryChange(for: CGFloat.self) { proxy in
            proxy.size.height
        } action: { newHeight in
            scrollerHeight = newHeight
        }
        .mask(
            LinearGradient(
                colors: [.clear, .black, .black, .clear],
                startPoint: .top, endPoint: .bottom
            )
        )
    }

    /// Bridges the view-model's non-optional `activeIndex` to the optional id
    /// binding `scrollPosition` expects, so the centered row and the highlighted
    /// row are always the same value.
    private var activeIndexBinding: Binding<Int?> {
        Binding(
            get: { vm.activeIndex },
            set: { newValue in
                guard let newValue, vm.retreats.indices.contains(newValue) else { return }
                vm.activeIndex = newValue
            }
        )
    }

    private func row(idx: Int, retreat r: Retreat) -> some View {
        let isActive = idx == vm.activeIndex
        return HStack(alignment: .lastTextBaseline, spacing: 8) {
            Text(r.name)
                .font(Theme.headline(isActive ? 54 : 44, weight: isActive ? .semibold : .light))
                .kerning(-1.4)
                .foregroundStyle(.white)
            Text("\(r.maxGuests)")
                .font(Theme.body(12, weight: .medium))
                .foregroundStyle(isActive ? Color(red: 1, green: 0.82, blue: 0.6) : Color.white.opacity(0.7))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(height: rowHeight)
        // Unblurred photography in stack mode — see View.onPhoto().
        .onPhoto()
        .opacity(isActive ? 1 : 0.42)
        .animation(.easeInOut(duration: 0.3), value: vm.activeIndex)
    }

    @ViewBuilder
    private var bottomCard: some View {
        if let r = vm.active {
            let year = Calendar.current.component(.year, from: r.startDate)
            PressableCard(action: { onSelect(r) }) {
                HStack(spacing: 14) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("\(r.when), \(year) · \(r.country)".uppercased())
                            .font(Theme.eyebrow(10))
                            .tracking(2.5)
                            .foregroundStyle(Color.white.opacity(0.75))
                        Text(r.tags.joined(separator: " · "))
                            .font(Theme.body(15, weight: .medium))
                            .foregroundStyle(.white)
                            .kerning(-0.2)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 12)
                    HStack(spacing: 8) {
                        Image(systemName: "arrow.up.right").font(.system(size: 11, weight: .semibold))
                        Text("Reserve").font(Theme.body(13, weight: .medium))
                    }
                    .foregroundStyle(Color.black)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 11)
                    .background(Capsule().fill(Color.white))
                }
                .padding(16)
                .frame(maxWidth: .infinity)
                .soulGlassCard(radius: 22, stroke: Theme.glassBorderHigh)
            }
        }
    }

    // MARK: - Catalog mode (magazine contact sheet)

    private var catalogMode: some View {
        VStack(spacing: 0) {
            catalogHeader

            ScrollView(showsIndicators: false) {
                LazyVGrid(
                    columns: [GridItem(.flexible(), spacing: 14), GridItem(.flexible(), spacing: 14)],
                    spacing: 14
                ) {
                    ForEach(Array(vm.retreats.enumerated()), id: \.element.id) { idx, r in
                        coverTile(idx: idx, retreat: r)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)
                Color.clear.frame(height: 60)
            }
            .mask(
                LinearGradient(colors: [.black, .black, .black, .clear],
                               startPoint: .top, endPoint: .bottom)
            )
        }
        .scaleEffect(scrub)
        .blur(radius: max(0, (scrub - 1) * 60))
    }

    private var catalogHeader: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 8) {
                Text("THE CATALOG")
                    .font(Theme.body(14, weight: .medium))
                    .tracking(4)
                    .foregroundStyle(.white)
                Text("Every gathering, side by side. Pinch in — or tap a cover — to return.")
                    .font(Theme.body(12))
                    .foregroundStyle(Color.white.opacity(0.82))
                    .lineSpacing(2)
                    .frame(maxWidth: 230, alignment: .leading)
            }
            .onPhoto()
            Spacer()
            CircleIconButton(systemName: "rectangle.portrait", size: 42) {
                withAnimation(commitSpring) { mode = .stack }
            }
            .accessibilityLabel("Stack")
        }
        .safeAreaPadding(.top)
        .padding(.top, 36)
        .padding(.horizontal, 24)
        .padding(.bottom, 18)
    }

    private func coverTile(idx: Int, retreat r: Retreat) -> some View {
        PressableCard(haptic: false, action: {
            Haptics.bump()
            withAnimation(commitSpring) {
                vm.activeIndex = idx
                mode = .stack
            }
        }) {
            ZStack(alignment: .bottomLeading) {
                Image(r.imageUrl)
                    .resizable().scaledToFill()
                    .frame(height: 224)
                    .frame(maxWidth: .infinity)
                    .clipped()

                LinearGradient(
                    colors: [.black.opacity(0.05), .clear, .black.opacity(0.66)],
                    startPoint: .top, endPoint: .bottom
                )

                // Folio number, magazine-style.
                VStack {
                    HStack {
                        Spacer()
                        Text(String(format: "%02d", idx + 1))
                            .font(Theme.body(11, weight: .medium))
                            .tracking(1.5)
                            .foregroundStyle(Color.white.opacity(0.85))
                            .padding(10)
                    }
                    Spacer()
                }

                VStack(alignment: .leading, spacing: 3) {
                    Text("\(r.country) · \(r.when)".uppercased())
                        .font(Theme.eyebrow(8.5))
                        .tracking(1.8)
                        .foregroundStyle(Color.white.opacity(0.78))
                    Text(r.name)
                        .font(Theme.headline(21, weight: .semibold))
                        .kerning(-0.5)
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
                .padding(12)
            }
            .frame(height: 224)
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(
                        idx == vm.activeIndex ? Theme.honey.opacity(0.7) : Theme.glassBorder,
                        lineWidth: 1
                    )
            )
            .shadow(color: .black.opacity(0.35), radius: 14, y: 8)
        }
        .scrollTransition(.interactive(timingCurve: .easeOut), axis: .vertical) { view, phase in
            let entering = max(phase.value, 0)
            return view
                .opacity(1 - entering * 0.5)
                .scaleEffect(1 - entering * 0.06)
                .offset(y: entering * 18)
        }
    }

    // MARK: - Error state

    private func errorState(_ msg: String) -> some View {
        VStack(spacing: 20) {
            Text(msg)
                .font(Theme.body(13))
                .foregroundStyle(Theme.inkSoft)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            Button {
                Task { await vm.load() }
            } label: {
                Text("Try again")
                    .font(Theme.body(13, weight: .medium))
                    .foregroundStyle(Theme.ink)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 10)
                    .overlay(Capsule().strokeBorder(Theme.glassBorder, lineWidth: 1))
            }
            .buttonStyle(.soulPressableChip)
        }
    }

    // MARK: - Backdrop (crossfade)

    private var backdrop: some View {
        // All retreat photos are stacked full-bleed; only the active one is
        // opaque, so changing `activeIndex` simply crossfades between them.
        // The tone-tinted floor prevents a black flash while images load.
        GeometryReader { proxy in
            ZStack {
                (vm.active?.tone.base ?? Theme.bg)
                ZStack {
                    ForEach(Array(vm.retreats.enumerated()), id: \.element.id) { idx, r in
                        Image(r.imageUrl)
                            .resizable().scaledToFill()
                            .frame(width: proxy.size.width, height: proxy.size.height, alignment: .topLeading)
                            .clipped()
                            .opacity(idx == vm.activeIndex ? 1 : 0)
                    }
                }
                .blur(radius: mode == .catalog ? 16 : 0)

                LinearGradient(
                    colors: [.black.opacity(0.30), .black.opacity(0.15), .black.opacity(0.45), .black.opacity(0.78)],
                    startPoint: .top, endPoint: .bottom
                )
                .ignoresSafeArea()

                if mode == .catalog {
                    Color.black.opacity(0.32).transition(.opacity)
                }
            }
        }
        .ignoresSafeArea()
        .animation(.easeInOut(duration: 0.7), value: vm.activeIndex)
        .animation(.easeInOut(duration: 0.5), value: mode)
    }
}

#Preview {
    NavigationStack {
        RetreatsStackView(onSelect: { _ in })
            .toolbar(.hidden, for: .navigationBar)
    }
    .preferredColorScheme(.dark)
}
