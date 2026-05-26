//
//  HomeView.swift
//  Soulfull Gatherings
//
//  The main landing screen. Centered logo, greeting, mood chips, today's
//  ritual card, continue-journey card, digital retreats carousel, circles
//  meeting now, and the upcoming-gatherings carousel that opens the
//  retreats stack / detail.
//

import SwiftUI

struct HomeView: View {
    @Environment(AppState.self) private var app
    @Environment(AppSettings.self) private var settings
    @State private var vm = HomeViewModel()

    let onOpenRetreats: () -> Void
    let onOpenRetreat: (Retreat) -> Void

    var body: some View {
        ScrollView {
            VStack(spacing: 32) {
                header
                moodRow
                todaysRitual
                continueJourney
                digitalRetreats
                circlesList
                upcomingGatherings
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

    // MARK: - Sections

    private var header: some View {
        VStack(spacing: 14) {
            Image("soulfull-logo-white")
                .resizable().scaledToFit()
                .frame(width: 88, height: 88)
                .opacity(0.92)

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
                    .font(Theme.body(13))
                    .foregroundStyle(Theme.inkSoft)
                    .padding(.top, 8)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 24)
        }
    }

    private var moodRow: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionLabel(title: "How do you feel?")
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(vm.moods) { m in
                        Button {
                            vm.tapMood(m.id)
                        } label: {
                            Text(m.label)
                                .font(Theme.body(13))
                                .foregroundStyle(Theme.ink)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 10)
                                .background(
                                    Capsule()
                                        .fill(.ultraThinMaterial)
                                        .overlay(
                                            Capsule().strokeBorder(
                                                vm.selectedMood == m.id
                                                ? Color.white.opacity(0.55)
                                                : Theme.glassBorder,
                                                lineWidth: 1
                                            )
                                        )
                                )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 24)
            }
        }
    }

    private var todaysRitual: some View {
        VStack(alignment: .leading, spacing: 0) {
            GlassCard(radius: 22, padding: 18) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("TODAY'S RITUAL")
                        .font(Theme.eyebrow(10))
                        .tracking(2)
                        .foregroundStyle(.white)
                        .padding(.bottom, 4)
                    Text("Nervous System Reset")
                        .font(Theme.headline(22))
                        .foregroundStyle(Theme.ink)
                        .kerning(-0.2)
                    Text("4 minutes · guided breath")
                        .font(Theme.body(11.5, weight: .medium))
                        .foregroundStyle(.white)
                        .padding(.top, 2)

                    HStack(spacing: 8) {
                        Circle()
                            .fill(Color.white)
                            .frame(width: 6, height: 6)
                            .pulse()
                        Text("Begin now")
                            .font(Theme.body(11.5, weight: .semibold))
                            .tracking(0.4)
                            .foregroundStyle(.white)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .overlay(
                        Capsule().strokeBorder(Color.white.opacity(0.85), lineWidth: 1)
                    )
                    .padding(.top, 12)
                }
            }
            .padding(.horizontal, 20)
            .contentShape(Rectangle())
            .onTapGesture { Haptics.bump() }
        }
    }

    private var continueJourney: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionLabel(title: "Continue your journey", action: "VIEW") { }

            GlassCard(radius: 22, padding: 16) {
                HStack(spacing: 16) {
                    Text("3")
                        .font(Theme.body(38, weight: .ultraLight))
                        .foregroundStyle(Theme.ink)
                        .frame(width: 84, height: 84)
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
                        .overlay(
                            RoundedRectangle(cornerRadius: 16)
                                .strokeBorder(Theme.glassBorder, lineWidth: 1)
                        )

                    VStack(alignment: .leading, spacing: 6) {
                        Text("DAY 3 OF 7")
                            .font(Theme.eyebrow(10))
                            .tracking(2)
                            .foregroundStyle(.white)
                        Text("Nervous System Healing")
                            .font(Theme.headline(20))
                            .foregroundStyle(Theme.ink)
                            .kerning(-0.2)
                        Text("with Dr. Anya Iyer")
                            .font(Theme.body(12))
                            .foregroundStyle(Theme.muted)

                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                Capsule().fill(Theme.line)
                                Capsule().fill(Color.white).frame(width: geo.size.width * 0.43)
                            }
                        }
                        .frame(height: 3)
                        .padding(.top, 8)
                    }
                }
            }
            .padding(.horizontal, 20)
        }
    }

    private var digitalRetreats: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionLabel(title: "Digital Retreats", action: "ALL") { }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 14) {
                    ForEach(vm.programs) { p in
                        programCard(p)
                    }
                }
                .padding(.horizontal, 20)
            }
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
        .onTapGesture { Haptics.tap() }
    }

    private var circlesList: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionLabel(title: "Circles meeting now", action: "ALL") { }

            VStack(spacing: 10) {
                ForEach(vm.circles) { c in
                    circleRow(c)
                }
            }
            .padding(.horizontal, 24)
        }
    }

    private func circleRow(_ c: CommunityCircle) -> some View {
        HStack(spacing: 14) {
            Text(String(c.title.prefix(1)))
                .font(Theme.headline(18))
                .foregroundStyle(Theme.ink)
                .frame(width: 44, height: 44)
                .background(.ultraThinMaterial, in: Circle())
                .overlay(Circle().strokeBorder(Theme.glassBorder, lineWidth: 1))

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    if c.isLive {
                        Circle().fill(Color.white).frame(width: 6, height: 6).pulse()
                    }
                    Text(c.timeLabel.uppercased())
                        .font(Theme.eyebrow(10))
                        .tracking(2)
                        .foregroundStyle(.white)
                }
                Text(c.title)
                    .font(Theme.headline(17))
                    .foregroundStyle(Theme.ink)
                Text("\(c.host) · \(c.attendees) attending")
                    .font(Theme.body(11))
                    .foregroundStyle(Theme.muted)
            }
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16).strokeBorder(Theme.glassBorder, lineWidth: 1)
        )
        .onTapGesture { Haptics.tap() }
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
                            .onTapGesture {
                                Haptics.tap()
                                onOpenRetreat(r)
                            }
                    }
                }
                .padding(.horizontal, 20)
            }
        }
    }

    private func retreatCard(_ r: Retreat) -> some View {
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
}

#Preview {
    let a = AppState()
    a.settings.userName = "Mara"
    return HomeView(onOpenRetreats: {}, onOpenRetreat: { _ in })
        .environment(a)
        .environment(a.settings)
}
