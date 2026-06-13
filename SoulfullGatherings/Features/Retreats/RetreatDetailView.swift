//
//  RetreatDetailView.swift
//  Soulfull Gatherings
//
//  Editorial spread. At rest it's the full-bleed cover — centered title,
//  white reserve pill, glass meta. Scrolling reveals the story: pull-quote,
//  numbered focus list, details grid, closing CTA. The cover photo answers
//  the scroll — stretching on pull-down, blurring and darkening as the
//  story comes up — and a glass reserve bar slides in once the hero CTA
//  has scrolled away.
//

import SwiftUI

struct RetreatDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AuthManager.self) private var auth
    let retreat: Retreat

    @State private var vm: RetreatDetailViewModel
    @State private var showAccount = false
    /// Normalized scroll offset: 0 at rest, negative when pulled down.
    @State private var scrollY: CGFloat = 0

    init(retreat: Retreat) {
        self.retreat = retreat
        _vm = State(initialValue: RetreatDetailViewModel(retreat: retreat))
    }

    var body: some View {
        ZStack {
            hero

            ScrollView(showsIndicators: false) {
                VStack(spacing: 0) {
                    coverPage
                        .containerRelativeFrame(.vertical)
                    storySections
                }
            }
            .onScrollGeometryChange(for: CGFloat.self) { geo in
                geo.contentOffset.y + geo.contentInsets.top
            } action: { _, new in
                scrollY = new
            }

            // Top chrome (back / share)
            VStack {
                topBar
                    .padding(.horizontal, 24)
                    .padding(.top, 8)
                Spacer()
            }

            // Pinned reserve bar once the hero CTA is gone.
            VStack {
                Spacer()
                if scrollY > 260 {
                    reserveBar
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .animation(.spring(response: 0.45, dampingFraction: 0.8), value: scrollY > 260)
        }
        .preferredColorScheme(.dark)
        .navigationBarBackButtonHidden(true)
        .toolbar(.hidden, for: .navigationBar)
        .task(id: auth.userID) { await vm.loadExistingBooking(userID: auth.userID) }
        .sheet(isPresented: $showAccount) { AccountView() }
    }

    // MARK: - Hero photo (scroll-graded)

    private var hero: some View {
        GeometryReader { proxy in
            ZStack {
                Image(retreat.imageUrl)
                    .resizable().scaledToFill()
                    .frame(width: proxy.size.width, height: proxy.size.height)
                    .clipped()
                    .scaleEffect(1 + max(0, -scrollY) / 700)          // stretch on pull-down
                    .blur(radius: min(14, max(0, scrollY) / 26))       // soften under the story

                LinearGradient(
                    colors: [.black.opacity(0.42), .black.opacity(0.10), .black.opacity(0.08), .black.opacity(0.62)],
                    startPoint: .top, endPoint: .bottom
                )

                // Extra dim as the story scrolls up.
                Color.black.opacity(min(0.45, Double(max(0, scrollY)) / 700))
            }
        }
        .ignoresSafeArea()
    }

    // MARK: - Cover page (first viewport)

    private var coverPage: some View {
        VStack(spacing: 0) {
            Spacer()

            VStack(spacing: 18) {
                Text("Gathering")
                    .font(Theme.body(15))
                    .foregroundStyle(Color.white.opacity(0.85))
                Text(retreat.name)
                    .font(Theme.headline(64, weight: .semibold))
                    .kerning(-2.4)
                    .foregroundStyle(.white)
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)

                reserveButton

                if let error = vm.errorMessage {
                    Text(error)
                        .font(Theme.body(12))
                        .foregroundStyle(Color.white.opacity(0.85))
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 300)
                        .padding(.top, 2)
                }
            }
            .padding(.horizontal, 24)
            .animation(.spring(response: 0.45, dampingFraction: 0.8), value: vm.phase)

            Spacer()

            VStack(spacing: 12) {
                HStack(spacing: 12) {
                    MetaPill(text: retreat.when)
                    MetaPill(text: "\(retreat.maxGuests) guests")
                    MetaPill(text: retreat.priceFormatted)
                }
                Text(retreat.blurb)
                    .font(Theme.body(12))
                    .foregroundStyle(Color.white.opacity(0.78))
                    .multilineTextAlignment(.center)
                    .lineSpacing(2)
                    .frame(maxWidth: 320)

                Image(systemName: "chevron.compact.down")
                    .font(.system(size: 22, weight: .light))
                    .foregroundStyle(Color.white.opacity(0.7))
                    .breathing(scale: 1.0...1.0, opacity: 0.35...0.85, period: 2.2)
                    .padding(.top, 10)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 36)
            // Fade the cover furniture as the story arrives.
            .opacity(1 - min(1, Double(max(0, scrollY)) / 220))
        }
    }

    private var reserveButton: some View {
        Button {
            Haptics.bump()
            if auth.hasAccount {
                Task { await vm.reserve() }
            } else {
                showAccount = true
            }
        } label: {
            HStack(spacing: 8) {
                if vm.isReserved {
                    Image(systemName: "checkmark").font(.system(size: 14, weight: .semibold))
                } else if vm.isBusy {
                    ProgressView()
                        .controlSize(.small)
                        .tint(.black)
                }
                Text(reserveTitle)
                    .font(Theme.body(15, weight: .medium))
            }
            .foregroundStyle(.black)
            .padding(.horizontal, 36)
            .padding(.vertical, 14)
            .background(Capsule().fill(.white))
            .shadow(color: .black.opacity(0.18), radius: 20, y: 6)
            .opacity(vm.isBusy ? 0.7 : 1)
        }
        .buttonStyle(SoulPressableStyle(scale: 0.96, hapticOnPress: false, dim: false))
        .disabled(vm.isBusy || vm.isReserved)
        .padding(.top, 4)
    }

    private var reserveTitle: String {
        if vm.isReserved { return "Reserved" }
        if vm.isBusy { return "Processing…" }
        return auth.hasAccount ? "Reserve" : "Sign in to reserve"
    }

    // MARK: - Story sections

    private var storySections: some View {
        VStack(alignment: .leading, spacing: 44) {
            // Pull-quote
            VStack(alignment: .leading, spacing: 14) {
                sectionEyebrow("The experience")
                Text(retreat.blurb)
                    .font(Theme.headline(28, weight: .light))
                    .kerning(-0.4)
                    .foregroundStyle(Theme.ink)
                    .lineSpacing(5)
            }

            // Numbered focus list from tags
            VStack(alignment: .leading, spacing: 0) {
                sectionEyebrow("The days")
                    .padding(.bottom, 8)
                ForEach(Array(retreat.tags.enumerated()), id: \.offset) { idx, tag in
                    HStack(alignment: .firstTextBaseline, spacing: 18) {
                        Text(String(format: "%02d", idx + 1))
                            .font(Theme.body(12, weight: .medium))
                            .tracking(1.5)
                            .foregroundStyle(Theme.honey.opacity(0.85))
                        Text(tag)
                            .font(Theme.headline(24))
                            .kerning(-0.4)
                            .foregroundStyle(Theme.ink)
                        Spacer()
                    }
                    .padding(.vertical, 14)
                    .overlay(alignment: .bottom) {
                        if idx < retreat.tags.count - 1 {
                            Rectangle().fill(Color.white.opacity(0.12)).frame(height: 1)
                        }
                    }
                }
            }

            // Details grid
            VStack(alignment: .leading, spacing: 14) {
                sectionEyebrow("Details")
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible())], spacing: 12) {
                    detailCell(label: "Dates", value: detailWhen)
                    detailCell(label: "Place", value: retreat.country)
                    detailCell(label: "Guests", value: "\(retreat.maxGuests) at most")
                    detailCell(label: "Contribution", value: retreat.priceFormatted)
                }
            }

            // Closing CTA
            VStack(spacing: 16) {
                Text("\(retreat.maxGuests) places. One table.")
                    .font(Theme.headline(22))
                    .kerning(-0.3)
                    .foregroundStyle(Theme.ink)
                    .frame(maxWidth: .infinity)
                reserveButton
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 6)
            .padding(.bottom, 140)
        }
        .padding(.horizontal, 26)
        .padding(.top, 30)
    }

    private var detailWhen: String {
        let year = Calendar.current.component(.year, from: retreat.startDate)
        return "\(retreat.when), \(year)"
    }

    private func sectionEyebrow(_ text: String) -> some View {
        Text(text.uppercased())
            .font(Theme.eyebrow(10))
            .tracking(3)
            .foregroundStyle(Color.white.opacity(0.6))
    }

    private func detailCell(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(label.uppercased())
                .font(Theme.eyebrow(9))
                .tracking(2)
                .foregroundStyle(Theme.muted)
            Text(value)
                .font(Theme.body(15, weight: .medium))
                .foregroundStyle(Theme.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .soulGlassCard(radius: 16)
    }

    // MARK: - Pinned reserve bar

    private var reserveBar: some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 2) {
                Text(retreat.name)
                    .font(Theme.body(15, weight: .medium))
                    .foregroundStyle(Theme.ink)
                Text("\(detailWhen) · \(retreat.priceFormatted)")
                    .font(Theme.body(11))
                    .foregroundStyle(Theme.inkSoft)
            }
            Spacer()
            Button {
                Haptics.bump()
                if auth.hasAccount {
                    Task { await vm.reserve() }
                } else {
                    showAccount = true
                }
            } label: {
                Text(vm.isReserved ? "Reserved" : "Reserve")
                    .font(Theme.body(13, weight: .medium))
                    .foregroundStyle(.black)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 11)
                    .background(Capsule().fill(.white))
            }
            .buttonStyle(SoulPressableStyle(scale: 0.95, hapticOnPress: false, dim: false))
            .disabled(vm.isBusy || vm.isReserved)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
        .soulGlassCapsule(stroke: Theme.glassBorderHigh)
        .padding(.horizontal, 16)
        .padding(.bottom, 24)
    }

    private var topBar: some View {
        HStack {
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
            }
            .buttonStyle(.plain)
            Spacer()
            ShareLink(item: shareMessage) {
                Image(systemName: "square.and.arrow.up")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(Theme.ink)
                    .frame(width: 38, height: 38)
                    .soulGlass(in: Circle(), interactive: true, stroke: Theme.glassBorderHigh)
            }
            .buttonStyle(.soulPressableChip)
        }
    }

    private var shareMessage: String {
        "\(retreat.name), \(retreat.country) — \(detailWhen). \(retreat.blurb)"
    }
}

// MARK: - Glass meta pill

private struct MetaPill: View {
    let text: String
    var body: some View {
        Text(text)
            .font(Theme.body(11))
            .tracking(0.3)
            .foregroundStyle(.white)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .soulGlassCapsule(stroke: Theme.glassBorderHigh)
    }
}

#Preview {
    NavigationStack {
        RetreatDetailView(retreat: Retreat.mock[0])
            .toolbar(.hidden, for: .navigationBar)
    }
    .environment(AppState().auth)
    .preferredColorScheme(.dark)
}
