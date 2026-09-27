//
//  RetreatsStackView.swift
//  Soulfull Gatherings
//
//  Two ways to browse the gatherings:
//
//  STACK — the signature typographic scroller: retreat names snap to center
//  over a crossfading full-bleed photo. The centre line is a focus lens — a
//  name grows to full size and full ink as it reaches it, continuously with
//  the scroll rather than on arrival, and each name that settles there ticks
//  like a picker detent.
//
//  CATALOG — pinch out (or tap the grid button) and the stack recedes into a
//  magazine contact sheet of covers. Tap a cover to fly back into the stack
//  focused on that retreat; pinch in to leave the catalog.
//
//  The pinch is interactive: the live magnification scrubs scale/blur before
//  committing with a spring, so the zoom feels attached to the fingers.
//
//  The chrome (Back, and the one button that toggles the two modes) sits
//  above both and never scales, blurs or moves between them — and is there
//  while loading or failed too, so the screen always has a way out. As the
//  root of the Gatherings tab there is nothing to go back to, so Back goes and
//  the tab bar is the way out.
//
//  A row carries the retreat's name and nothing else. It used to trail a bare
//  number — the guest count — which read as a footnote marker, said nothing
//  on its own, and put a number on a gathering before its place or its dates.
//  Size lives on the detail screen, where it is labelled.
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

    /// The root of the Gatherings tab rather than a push: no Back, and the
    /// docked tab bar to keep clear of at the bottom.
    var isTabRoot = false
    /// A retreat another tab asked to open (a card on Home's shelf). Consumed
    /// once the catalog is in, then cleared — see `consumePending()`.
    var pending: Binding<Retreat?> = .constant(nil)
    let onSelect: (Retreat) -> Void
    /// The first load has finished, one way or the other.
    @State private var loaded = false

    private let rowHeight: CGFloat = 84
    private var navClearance: CGFloat { isTabRoot ? BottomNav.height : 0 }
    private let commitSpring = Animation.spring(response: 0.5, dampingFraction: 0.82)

    /// There is a catalog to browse — the mode toggle and the pinch mean
    /// nothing while loading, failed, or empty.
    private var hasCatalog: Bool {
        !vm.isLoading && vm.loadFailure == nil && !vm.retreats.isEmpty
    }

    var body: some View {
        ZStack {
            backdrop

            if vm.isLoading {
                ProgressView().tint(Theme.ink)
            } else if let failure = vm.loadFailure {
                errorState(failure)
            } else if vm.retreats.isEmpty {
                emptyState
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
        .safeAreaInset(edge: .top, spacing: 0) { topBar }
        // High priority so the two-finger pinch never doubles as a tap on
        // rows/covers underneath; single-finger interactions pass through.
        .highPriorityGesture(pinchGesture, isEnabled: hasCatalog)
        .task {
            await vm.load()
            loaded = true
            consumePending()
        }
        .onChange(of: pending.wrappedValue) { consumePending() }
        .preferredColorScheme(.dark)
        .navigationBarBackButtonHidden(true)
    }

    /// Opens whatever another tab handed us, focused in the stack so Back
    /// lands on it, then clears it.
    ///
    /// Not until the first load is done. Pushing in the same update the tab
    /// appears builds this screen underneath the retreat without it ever
    /// having been on screen, and the scroll position then re-evaluates
    /// forever — the app hung at 100% CPU on the Home hand-off. Waiting for
    /// the catalog is also what the digital retreats hand-off does, so both
    /// shelves on Home behave the same way.
    private func consumePending() {
        guard loaded, let retreat = pending.wrappedValue else { return }
        pending.wrappedValue = nil
        if let index = vm.retreats.firstIndex(where: { $0.id == retreat.id }) {
            vm.activeIndex = index
        }
        onSelect(retreat)
    }

    // MARK: - Chrome (shared by both modes)

    /// Back on the left, the mode toggle on the right — the same anatomy as
    /// the retreat detail's top bar, which is where this screen leads.
    private var topBar: some View {
        HStack {
            if !isTabRoot { backButton }

            Spacer()

            if hasCatalog {
                CircleIconButton(systemName: mode == .stack ? "square.grid.2x2" : "text.alignleft",
                                 size: 42) {
                    withAnimation(commitSpring) { mode = mode == .stack ? .catalog : .stack }
                }
                .contentTransition(.symbolEffect(.replace))
                .accessibilityLabel(mode == .stack ? "Show all retreats" : "Show as a list")
                .transition(.opacity)
            }
        }
        // Holds Back's height when there is no Back, so the intro sits in the
        // same place whether or not the toggle has arrived yet.
        .frame(minHeight: 44)
        .padding(.horizontal, 24)
        .padding(.top, 4)
        .animation(.easeInOut(duration: 0.3), value: hasCatalog)
    }

    private var backButton: some View {
        Button {
            Haptics.tap()
            dismiss()
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "chevron.left").font(.system(size: 12, weight: .semibold))
                Text("Back")
                    .font(Theme.body(13))
                    .underline()
            }
            .foregroundStyle(.white)
            .onPhoto()
            // The drawn label is ~20pt tall; give the thumb the full bar.
            .frame(minWidth: 44, minHeight: 44, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
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
            stackIntro
            stackScroller
            bottomCard
                .padding(.horizontal, 16)
                .padding(.bottom, 8 + navClearance)
        }
        .scaleEffect(mode == .catalog ? 0.92 : scrub)
        .blur(radius: mode == .catalog ? 22 : (1 - scrub) * 24)
        .opacity(mode == .catalog ? 0.25 : 1)
    }

    /// What this list is, and where in it you are.
    private var stackIntro: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text("Upcoming gatherings")
                    .sgEyebrow(color: Theme.inkSoft, tracking: 3)
                Spacer()
                folio
            }
            Text("Small groups, in carefully chosen places.")
                .font(Theme.body(14))
                .foregroundStyle(Theme.inkOnPhoto)
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
        }
        .onPhoto()
        .padding(.horizontal, 24)
        .padding(.top, 18)
        .padding(.bottom, 10)
    }

    /// "01 / 04" — the magazine folio, following the centred name. Replaces a
    /// static count in a circle that looked like a button and wasn't one.
    ///
    /// One `Text`, so VoiceOver meets one element ("Retreat 1 of 4"). As an
    /// HStack of three the digits were still exposed as bare numbers beneath
    /// the combined label.
    private var folio: some View {
        let current = Text(String(format: "%02d", vm.activeIndex + 1))
            .foregroundStyle(Theme.ink)
        return Text("\(current)  /  \(String(format: "%02d", vm.retreats.count))")
            .font(Theme.body(12, weight: .medium))
            .foregroundStyle(Theme.inkSoft)
            .monospacedDigit()
            .tracking(1)
            .contentTransition(.numericText(value: Double(vm.activeIndex)))
            .animation(.snappy(duration: 0.3), value: vm.activeIndex)
            .accessibilityLabel("Retreat \(vm.activeIndex + 1) of \(vm.retreats.count)")
    }

    private var stackScroller: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 0) {
                ForEach(Array(vm.retreats.enumerated()), id: \.element.id) { idx, r in
                    row(idx: idx, retreat: r)
                        .id(idx)
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
        // The names share the header's 24pt margin. Without it they ran to the
        // very edge of the glass and the first letter sat under the bezel.
        .contentMargins(.horizontal, 24, for: .scrollContent)
        .onGeometryChange(for: CGFloat.self) { proxy in
            proxy.size.height
        } action: { newHeight in
            scrollerHeight = newHeight
        }
        .mask(
            LinearGradient(
                stops: [
                    .init(color: .clear, location: 0),
                    .init(color: .black, location: 0.28),
                    .init(color: .black, location: 0.72),
                    .init(color: .clear, location: 1),
                ],
                startPoint: .top, endPoint: .bottom
            )
        )
    }

    /// Bridges the view-model's non-optional `activeIndex` to the optional id
    /// binding `scrollPosition` expects, so the centered row and the highlighted
    /// row are always the same value.
    ///
    /// Only a *scroll* comes through the setter — a tap writes `activeIndex`
    /// directly — so this is where each name settling on the centre line
    /// gets its detent tick, and a tap doesn't tick twice.
    private var activeIndexBinding: Binding<Int?> {
        Binding(
            get: { vm.activeIndex },
            set: { newValue in
                guard let newValue, vm.retreats.indices.contains(newValue),
                      newValue != vm.activeIndex else { return }
                Haptics.select()
                vm.activeIndex = newValue
            }
        )
    }

    private func row(idx: Int, retreat r: Retreat) -> some View {
        let isActive = idx == vm.activeIndex
        // A local copy: `visualEffect` runs off the main actor and can't read
        // the view's properties.
        let height = rowHeight
        return Button {
            if isActive {
                Haptics.bump()
                onSelect(r)
            } else {
                Haptics.select()
                withAnimation(.spring(response: 0.45, dampingFraction: 0.85)) {
                    vm.activeIndex = idx
                }
            }
        } label: {
            Text(r.name)
                .font(Theme.headline(54, weight: isActive ? .semibold : .light))
                .kerning(-1.6)
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.5)
                // Display type in a fixed-height row: let it grow with the
                // reader's text size, but not past where rows would collide.
                .dynamicTypeSize(...DynamicTypeSize.xxLarge)
                .frame(maxWidth: .infinity, alignment: .leading)
                .frame(height: height)
                .contentShape(Rectangle())
                // Unblurred photography in stack mode — see View.onPhoto().
                .onPhoto()
                .animation(.easeInOut(duration: 0.3), value: isActive)
        }
        .buttonStyle(.soulPressableQuiet)
        // The focus lens. `focus` is 1 on the centre line and 0 a row away,
        // read from the row's live position, so size and ink track the finger
        // instead of jumping when the centred index changes. Only the weight
        // switches discretely — Geist ships static weights, not a variable axis.
        .visualEffect { content, proxy in
            let viewport = proxy.bounds(of: .scrollView(axis: .vertical)) ?? .zero
            let distance = abs(viewport.midY - proxy.size.height / 2) / height
            let focus = max(0, 1 - distance)
            return content
                .scaleEffect(0.8 + 0.2 * focus, anchor: .leading)
                .opacity(0.4 + 0.6 * focus)
        }
        .accessibilityLabel("\(r.name), \(r.country)")
        .accessibilityValue(Self.dateLine(r))
        .accessibilityHint(isActive ? "Opens the retreat" : "Brings it into focus")
        .accessibilityAddTraits(isActive ? .isSelected : [])
    }

    /// The centred retreat's particulars and the way in. Its details crossfade
    /// as the stack moves; the card itself holds still.
    @ViewBuilder
    private var bottomCard: some View {
        if let r = vm.active {
            PressableCard(haptic: false, action: {
                Haptics.bump()
                onSelect(r)
            }) {
                HStack(spacing: 14) {
                    ZStack(alignment: .leading) {
                        cardDetails(r)
                            .id(r.id)
                            .transition(.opacity.combined(with: .offset(y: 5)))
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .animation(.easeInOut(duration: 0.28), value: r.id)

                    HStack(spacing: 6) {
                        Text("Explore").font(Theme.body(13, weight: .medium))
                        Image(systemName: "arrow.right").font(.system(size: 11, weight: .semibold))
                    }
                    .foregroundStyle(Color.black)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 11)
                    .background(Capsule().fill(Color.white))
                }
                .padding(16)
                .frame(maxWidth: .infinity)
                .soulGlassCard(radius: Theme.cardRadius, stroke: Theme.glassBorderHigh)
                // The whole card is the target. On iOS 26 `glassEffect` adds no
                // hit-testable fill, so without this only the glyphs and the
                // white pill answered — a tap on the glass between them did
                // nothing (CLAUDE.md, rendering gotcha #5).
                .contentShape(RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
            }
            .accessibilityLabel("Explore \(r.name). \(r.country), \(Self.dateLine(r))")
        }
    }

    /// Place, dates, then the character of it — one fact per line, so nothing
    /// wraps. (Date and country shared an eyebrow and the country dropped to a
    /// second line on its own.)
    private func cardDetails(_ r: Retreat) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(r.country.uppercased())
                .font(Theme.eyebrow(10))
                .tracking(2.5)
                .foregroundStyle(Theme.inkSoft)
                .lineLimit(1)
            Text(Self.dateLine(r))
                .font(Theme.body(16, weight: .medium))
                .kerning(-0.2)
                .foregroundStyle(Theme.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            if !r.tags.isEmpty {
                Text(r.tags.joined(separator: " · "))
                    .font(Theme.body(13))
                    .foregroundStyle(Theme.inkSoft)
                    .lineLimit(1)
            }
        }
    }

    /// "January 10–15, 2027" — the same line the detail screen's Dates cell
    /// shows, so the two screens agree.
    private static func dateLine(_ r: Retreat) -> String {
        "\(r.when), \(Calendar.current.component(.year, from: r.startDate))"
    }

    // MARK: - Catalog mode (magazine contact sheet)

    private var catalogMode: some View {
        VStack(spacing: 0) {
            catalogIntro

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
                Color.clear.frame(height: 60 + navClearance)
            }
            .mask(
                LinearGradient(colors: [.black, .black, .black, .clear],
                               startPoint: .top, endPoint: .bottom)
            )
            .ignoresSafeArea(edges: .bottom)
        }
        .scaleEffect(scrub)
        .blur(radius: max(0, (scrub - 1) * 60))
    }

    private var catalogIntro: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("All gatherings")
                .sgEyebrow(color: Theme.inkSoft, tracking: 3)
            Text("Every retreat, side by side. Tap a cover to bring it into focus.")
                .font(Theme.body(14))
                .foregroundStyle(Theme.inkOnPhoto)
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
        }
        .onPhoto()
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 24)
        .padding(.top, 18)
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
                CatalogImage(r.imageUrl) { image in
                    image
                        .resizable().scaledToFill()
                        .frame(height: 224)
                        .frame(maxWidth: .infinity)
                        .clipped()
                }
                .frame(height: 224)
                .frame(maxWidth: .infinity)
                .clipped()

                LinearGradient(
                    colors: [.black.opacity(0.05), .clear, .black.opacity(0.7)],
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
                    Text(r.country.uppercased())
                        .font(Theme.eyebrow(10))
                        .tracking(1.8)
                        .foregroundStyle(Color.white.opacity(0.82))
                        .lineLimit(1)
                    Text(r.name)
                        .font(Theme.headline(22, weight: .semibold))
                        .kerning(-0.5)
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                    Text(Self.dateLine(r))
                        .font(Theme.body(11))
                        .foregroundStyle(Theme.inkOnPhoto)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
                .onPhoto()
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
        .accessibilityLabel("\(r.name), \(r.country), \(Self.dateLine(r))")
        .accessibilityHint("Brings it into focus")
        .scrollTransition(.interactive(timingCurve: .easeOut), axis: .vertical) { view, phase in
            let entering = max(phase.value, 0)
            return view
                .opacity(1 - entering * 0.5)
                .scaleEffect(1 - entering * 0.06)
                .offset(y: entering * 18)
        }
    }

    // MARK: - Error / empty states

    /// No catalog, and why. There is deliberately no sample data behind this —
    /// see `RetreatsLoadFailure`.
    private func errorState(_ failure: RetreatsLoadFailure) -> some View {
        VStack(spacing: 20) {
            VStack(spacing: 8) {
                Image(systemName: failure == .offline ? "wifi.slash" : "exclamationmark.triangle")
                    .font(.system(size: 22, weight: .light))
                    .foregroundStyle(Theme.inkSoft)
                    .padding(.bottom, 4)
                Text(failure.title)
                    .font(Theme.headline(19, weight: .medium)).kerning(-0.2)
                    .foregroundStyle(Theme.ink)
                Text(failure.detail)
                    .font(Theme.body(13))
                    .foregroundStyle(Theme.inkSoft)
                    .multilineTextAlignment(.center)
                    .lineSpacing(2)
                    .padding(.horizontal, 32)
            }
            .onPhoto()
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

    /// The fetch worked and nothing is upcoming — every retreat has begun, or
    /// the next ones aren't in yet. Before this the screen was a bare backdrop
    /// with a "00" in the corner.
    private var emptyState: some View {
        VStack(spacing: 8) {
            Text("New gatherings are on their way")
                .font(Theme.headline(19, weight: .medium)).kerning(-0.2)
                .foregroundStyle(Theme.ink)
            Text("There are no upcoming retreats just now. New dates will appear here as they're announced.")
                .font(Theme.body(13))
                .foregroundStyle(Theme.inkSoft)
                .multilineTextAlignment(.center)
                .lineSpacing(2)
                .padding(.horizontal, 32)
        }
        .onPhoto()
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
                        CatalogImage(r.imageUrl) { image in
                            image
                                .resizable().scaledToFill()
                                .frame(width: proxy.size.width, height: proxy.size.height, alignment: .topLeading)
                                .clipped()
                        }
                        .frame(width: proxy.size.width, height: proxy.size.height)
                        .clipped()
                        .opacity(idx == vm.activeIndex ? 1 : 0)
                    }
                }
                .blur(radius: mode == .catalog ? 16 : 0)

                LinearGradient(
                    colors: [.black.opacity(0.30), .black.opacity(0.15), .black.opacity(0.45), .black.opacity(0.78)],
                    startPoint: .top, endPoint: .bottom
                )

                // Ground for the header — the app-wide type-over-photography
                // rule (see `PhotoBackdrop.topScrim`). The vignette above is at
                // its lightest exactly where Back and the intro sit.
                LinearGradient(
                    colors: [.black.opacity(0.45), .clear],
                    startPoint: .top, endPoint: .bottom
                )
                .frame(height: 340)
                .frame(maxHeight: .infinity, alignment: .top)

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
