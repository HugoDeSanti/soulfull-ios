//
//  HomeView.swift
//  Soulfull Gatherings
//
//  The main landing screen. Sections rise out of a blur as they scroll in,
//  card imagery drifts in parallax, mood chips bloom on selection, and the
//  ritual card has a living aurora interior. Retreat cards are zoom-hero
//  sources into the detail screen.
//

import SwiftUI

struct HomeView: View {
    @Environment(AppState.self) private var app
    @Environment(AppSettings.self) private var settings
    @State private var vm = HomeViewModel()

    let onOpenRetreats: () -> Void
    let onOpenRetreat: (Retreat) -> Void
    /// Jump to a section of the Practice library (from the ritual card).
    var onOpenPractice: (PracticeMenuItem) -> Void = { _ in }
    /// Zoom-hero namespace owned by HomeRoot; retreat cards register as sources.
    var zoomNamespace: Namespace.ID? = nil

    var body: some View {
        ScrollView {
            VStack(spacing: 32) {
                header
                section { moodRow }
                section { todaysRitual }
                section { upcomingGatherings }
                // Hidden until the `programs` table is seeded — see HomeViewModel.
                if !vm.programs.isEmpty {
                    section { digitalRetreats }
                }
                Color.clear.frame(height: 120)
            }
            .padding(.top, 24)
        }
        .scrollIndicators(.hidden)
        .background {
            PhotoBackdrop(imageName: "home-bg", blur: 3, darken: 0.74)
        }
        .task { await vm.load() }
    }

    /// Shared scroll-in reveal: sections rise out of a blur as they enter
    /// from the bottom; nothing happens scrolling back past the top.
    private func section(@ViewBuilder _ content: () -> some View) -> some View {
        content()
            .scrollTransition(.interactive(timingCurve: .easeOut), axis: .vertical) { view, phase in
                let entering = max(phase.value, 0) // only the bottom edge
                return view
                    .opacity(1 - entering * 0.6)
                    .blur(radius: entering * 3)
                    .offset(y: entering * 26)
            }
    }

    // MARK: - Sections

    private var header: some View {
        VStack(spacing: 14) {
            Image("soulfull-logo-white")
                .resizable().scaledToFit()
                .frame(width: 88, height: 88)

            VStack(alignment: .leading, spacing: 6) {
                Text(vm.greeting.uppercased())
                    .font(Theme.eyebrow(12))
                    .tracking(2)
                    .foregroundStyle(.white)
                Text("\(settings.userName.isEmpty ? "Friend" : settings.userName).")
                    .font(Theme.headline(38))
                    .foregroundStyle(Theme.ink)
                    .kerning(-0.3)
                Text("Take your time. We're here with you.")
                    .font(Theme.body(14))
                    .foregroundStyle(Theme.inkOnPhoto)
                    .padding(.top, 8)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 24)
            // Sits on the brightest part of home-bg (blur 3) — see onPhoto().
            .onPhoto()
        }
    }

    private var moodRow: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionLabel(title: "How do you feel?")
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(vm.moods) { m in
                        moodChip(m)
                    }
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 6) // headroom for the selection pop
            }
        }
    }

    private func moodChip(_ m: MoodChip) -> some View {
        let selected = vm.selectedMood == m.id
        return Button {
            vm.tapMood(m.id)
        } label: {
            Text(m.label)
                .font(Theme.body(13, weight: selected ? .medium : .regular))
                .foregroundStyle(selected ? Color.black : Theme.ink)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background {
                    if selected {
                        Capsule().fill(Theme.ink)
                            .shadow(color: Theme.honey.opacity(0.35), radius: 12, y: 2)
                    } else {
                        Capsule()
                            .fill(.ultraThinMaterial)
                            .overlay(Capsule().strokeBorder(Theme.glassBorder, lineWidth: 1))
                    }
                }
                .scaleEffect(selected ? 1.06 : 1)
                .animation(.spring(response: 0.38, dampingFraction: 0.6), value: selected)
        }
        .buttonStyle(SoulPressableStyle(scale: 0.9, hapticOnPress: false, dim: false))
        .accessibilityLabel(m.label)
        .accessibilityHint("Suggests a practice for feeling \(m.label.lowercased())")
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private var todaysRitual: some View {
        PressableCard(action: { onOpenPractice(vm.ritualDestination) }) {
            VStack(alignment: .leading, spacing: 4) {
                Text(vm.mood == nil ? "TODAY'S RITUAL" : "BECAUSE YOU FEEL \(vm.mood!.label.uppercased())")
                    .font(Theme.eyebrow(10))
                    .tracking(2)
                    .foregroundStyle(.white)
                    .padding(.bottom, 4)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Text(vm.ritualTitle)
                    .font(Theme.headline(22))
                    .foregroundStyle(Theme.ink)
                    .kerning(-0.2)
                    .fixedSize(horizontal: false, vertical: true)
                Text(vm.ritualLead)
                    .font(Theme.body(11.5, weight: .medium))
                    .foregroundStyle(.white)
                    .padding(.top, 2)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 8) {
                    Circle()
                        .fill(Color.white)
                        .frame(width: 6, height: 6)
                    Text("Begin now")
                        .font(Theme.body(11.5, weight: .semibold))
                        .tracking(0.4)
                        .foregroundStyle(.white)
                }
                .animation(.easeInOut(duration: 0.25), value: vm.selectedMood)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .overlay(
                    Capsule().strokeBorder(Color.white.opacity(0.85), lineWidth: 1)
                )
                .padding(.top, 12)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(18)
            .background {
                // Living interior: slow aurora under the glass.
                AuroraBackground(speed: 0.7)
                    .opacity(0.55)
                    .overlay(.ultraThinMaterial)
            }
            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .strokeBorder(Theme.glassBorder, lineWidth: 1)
            )
        }
        .padding(.horizontal, 20)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(vm.ritualTitle). \(vm.ritualLead)")
        .accessibilityHint("Opens \(vm.ritualDestination.title)")
        .accessibilityAddTraits(.isButton)
    }

    private var upcomingGatherings: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionLabel(title: "Upcoming gatherings", action: "ALL") {
                onOpenRetreats()
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 14) {
                    ForEach(vm.retreats.prefix(5)) { r in
                        retreatCard(r)
                    }
                }
                .padding(.horizontal, 20)
                .scrollTargetLayout()
            }
            .scrollTargetBehavior(.viewAligned(limitBehavior: .never))
        }
    }

    private func retreatCard(_ r: Retreat) -> some View {
        PressableCard(action: { onOpenRetreat(r) }) {
            VStack(alignment: .leading, spacing: 0) {
                ZStack(alignment: .bottomLeading) {
                    Image(r.imageUrl)
                        .resizable().scaledToFill()
                        .frame(width: 260, height: 150)
                        .clipped()
                    LinearGradient(colors: [.clear, .black.opacity(0.55)],
                                   startPoint: .top, endPoint: .bottom)
                    Text("\(r.country) · \(r.when)".uppercased())
                        .font(Theme.eyebrow(10))
                        .tracking(2)
                        .foregroundStyle(.white)
                        .padding(14)
                }
                .frame(width: 260, height: 150)
                .clipped()

                VStack(alignment: .leading, spacing: 4) {
                    Text(r.name)
                        .font(Theme.headline(22))
                        .foregroundStyle(Theme.ink)
                        .kerning(-0.2)
                    Text("\(r.durationDays) days · \(r.maxGuests) guests")
                        .font(Theme.body(12))
                        .foregroundStyle(Theme.muted)
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(width: 260)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 22).strokeBorder(Theme.glassBorder, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        }
        .modifier(ZoomSourceIfAvailable(id: "home-retreat-\(r.id)", namespace: zoomNamespace))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(r.name), \(r.country). \(r.when). \(r.durationDays) days, \(r.maxGuests) guests")
        .accessibilityHint("Opens retreat details")
    }

    private var digitalRetreats: some View {
        VStack(alignment: .leading, spacing: 14) {
            // Informational shelf: there is no program detail screen yet, so
            // it deliberately offers no "ALL" action and the cards don't press.
            // Give both back when program detail exists.
            SectionLabel(title: "Digital Retreats")

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 14) {
                    ForEach(vm.programs) { p in
                        programCard(p)
                    }
                }
                .padding(.horizontal, 20)
                .scrollTargetLayout()
            }
            .scrollTargetBehavior(.viewAligned(limitBehavior: .never))
        }
    }

    private func programCard(_ p: Program) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            ZStack(alignment: .bottomLeading) {
                Image(p.imageUrl)
                    .resizable().scaledToFill()
                    .frame(width: 260, height: 200)
                    .clipped()

                LinearGradient(
                    colors: [.clear, .black.opacity(0.62)],
                    startPoint: .top, endPoint: .bottom
                )

                Text("\(p.days) DAYS · DIGITAL · \(p.when)".uppercased())
                    .font(Theme.eyebrow(10))
                    .tracking(2)
                    .foregroundStyle(.white)
                    .padding(14)
            }
            .frame(width: 260, height: 200)
            .clipped()

            VStack(alignment: .leading, spacing: 4) {
                Text(p.title)
                    .font(Theme.headline(22))
                    .foregroundStyle(Theme.ink)
                    .kerning(-0.2)
                    .lineLimit(2)
                Text("with \(p.lead)")
                    .font(Theme.body(12))
                    .foregroundStyle(Theme.muted)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(width: 260)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 22)
                .strokeBorder(Theme.glassBorder, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(p.title), with \(p.lead), \(p.days) day digital program, \(p.when)")
    }

}

/// Registers a zoom-hero source only when the owning stack provided a
/// namespace (previews pass none).
private struct ZoomSourceIfAvailable: ViewModifier {
    let id: String
    let namespace: Namespace.ID?

    func body(content: Content) -> some View {
        if let namespace {
            content.matchedTransitionSource(id: id, in: namespace)
        } else {
            content
        }
    }
}

#Preview {
    let a = AppState()
    a.settings.userName = "Mara"
    return HomeView(onOpenRetreats: {}, onOpenRetreat: { _ in })
        .environment(a)
        .environment(a.settings)
}
