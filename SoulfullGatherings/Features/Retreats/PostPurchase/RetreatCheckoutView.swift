//
//  RetreatCheckoutView.swift
//  Soulfull Gatherings
//
//  Reserve / checkout review — a dark, all-Geist translation of the Claude
//  Design `retreat-checkout` brochure card. Shows the order summary and what's
//  due, then hands the actual charge to Stripe's PaymentSheet via
//  `RetreatDetailViewModel.reserve()`. There are deliberately NO raw card
//  fields (the prototype's form is dropped) — PCI stays with Stripe. On a
//  successful charge it calls `onReserved`, which routes on to the experience
//  hub. The deposit / installment copy is presentational; the live charge is
//  the single-payment flow (see docs/PLAN-deposit-installments.md).
//

import SwiftUI

struct RetreatCheckoutView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AuthManager.self) private var auth

    let retreat: Retreat
    var onReserved: () -> Void = {}

    @State private var vm: RetreatDetailViewModel
    @State private var showAccount = false

    init(retreat: Retreat, onReserved: @escaping () -> Void = {}) {
        self.retreat = retreat
        self.onReserved = onReserved
        _vm = State(initialValue: RetreatDetailViewModel(retreat: retreat))
    }

    private var exp: RetreatExperience? { retreat.experience ?? RetreatExperience.curated(for: retreat) }
    private var checkout: RetreatExperience.PostBooking.Checkout? { exp?.postBooking?.checkout }
    private var dueAmount: String { checkout?.dueToday ?? retreat.priceFormatted }

    var body: some View {
        ZStack(alignment: .top) {
            RetreatPalette.espresso.ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {
                    header
                    content
                }
            }
            .ignoresSafeArea(.container, edges: .top)

            topBar
                .padding(.horizontal, 20)
                .padding(.top, 8)

            VStack { Spacer(); payBar }
        }
        .preferredColorScheme(.dark)
        .navigationBarBackButtonHidden(true)
        .toolbar(.hidden, for: .navigationBar)
        .sheet(isPresented: $showAccount) { AccountView() }
    }

    // MARK: - Photo header

    private var header: some View {
        ZStack(alignment: .bottom) {
            Color.clear
                .frame(height: 300)
                .overlay { Image("mb-checkout").resizable().scaledToFill() }
                .clipped()

            LinearGradient(
                colors: [.black.opacity(0.45), .black.opacity(0.1), .black.opacity(0.25), RetreatPalette.espresso],
                startPoint: .top, endPoint: .bottom
            )
            .frame(height: 300)

            VStack(spacing: 6) {
                Text("\(retreat.name) · \(retreat.country)".uppercased())
                    .font(Theme.eyebrow(10)).tracking(3)
                    .foregroundStyle(RetreatPalette.terracotta)
                Text("Reserve your place")
                    .font(Theme.headline(34, weight: .semibold)).kerning(-0.6)
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                Text((exp?.dateRange ?? retreat.when).uppercased())
                    .font(Theme.eyebrow(10)).tracking(2)
                    .foregroundStyle(.white.opacity(0.8))
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 26)
        }
        .frame(height: 300)
    }

    // MARK: - Body

    private var content: some View {
        VStack(alignment: .leading, spacing: 18) {
            eyebrow("Your Reservation")
            summaryCard
            dueCard
            secureNote
            if let error = vm.errorMessage {
                Text(error)
                    .font(Theme.body(12)).foregroundStyle(RetreatPalette.terracotta)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
            }
        }
        .padding(.horizontal, 24)
        .padding(.top, 22)
        .padding(.bottom, 180)   // clears the sticky pay bar
    }

    private var summaryCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let items = checkout?.lineItems {
                ForEach(Array(items.enumerated()), id: \.element.id) { idx, item in
                    if idx > 0 { rule }
                    summaryRow(item.title, item.detail, item.value)
                }
            } else {
                summaryRow(retreat.name, "\(retreat.durationDays) days · all-inclusive", retreat.priceFormatted)
            }
            Rectangle().fill(RetreatPalette.cream.opacity(0.4)).frame(height: 1).padding(.top, 2)
            HStack {
                Text((checkout != nil ? "Total experience" : "Total").uppercased())
                    .font(Theme.eyebrow(10)).tracking(2)
                    .foregroundStyle(RetreatPalette.creamSoft)
                Spacer()
                Text(checkout?.total ?? retreat.priceFormatted)
                    .font(Theme.headline(22)).foregroundStyle(RetreatPalette.cream)
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity)
        .soulGlassCard(radius: 18, tint: RetreatPalette.glassTint, stroke: RetreatPalette.glassLine)
    }

    private var dueCard: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 4) {
                Text((checkout != nil ? "Due today — deposit" : "Due today").uppercased())
                    .font(Theme.eyebrow(10)).tracking(1.5)
                    .foregroundStyle(RetreatPalette.creamSoft)
                if let note = checkout?.dueTodayNote {
                    Text(note)
                        .font(Theme.body(11)).foregroundStyle(RetreatPalette.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 12)
            Text(dueAmount)
                .font(Theme.headline(30)).foregroundStyle(RetreatPalette.gold)
        }
        .padding(18)
        .frame(maxWidth: .infinity)
        .soulGlassCard(radius: 18, tint: RetreatPalette.gold.opacity(0.08), stroke: RetreatPalette.glassLine)
    }

    private var secureNote: some View {
        HStack(spacing: 8) {
            Image(systemName: "lock.fill")
                .font(.system(size: 11))
                .foregroundStyle(RetreatPalette.olive)
            Text("Encrypted & secure. Your place is held the moment your deposit clears.")
                .font(Theme.body(11)).foregroundStyle(RetreatPalette.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.top, 2)
    }

    // MARK: - Sticky pay bar

    private var payBar: some View {
        VStack(spacing: 10) {
            Button {
                pay()
            } label: {
                HStack(spacing: 8) {
                    if vm.isBusy {
                        ProgressView().controlSize(.small).tint(RetreatPalette.espresso)
                    }
                    Text(payTitle).font(Theme.body(16, weight: .medium)).tracking(0.4)
                    if !vm.isBusy {
                        Text("· Pay \(dueAmount)").font(Theme.body(13)).opacity(0.7)
                    }
                }
                .foregroundStyle(RetreatPalette.espresso)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 17)
                .background(Capsule().fill(RetreatPalette.terracotta))
                .opacity(vm.isBusy ? 0.8 : 1)
            }
            .buttonStyle(SoulPressableStyle(scale: 0.985, hapticOnPress: false, dim: false))
            .disabled(vm.isBusy)

            Text(checkout?.fineprint ?? "By reserving you agree to the enrollment terms and cancellation policy.")
                .font(Theme.body(10)).foregroundStyle(RetreatPalette.muted)
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal, 22)
        .padding(.top, 18)
        .padding(.bottom, 28)
        .background(
            LinearGradient(colors: [RetreatPalette.espresso.opacity(0), RetreatPalette.espresso], startPoint: .top, endPoint: .bottom)
        )
    }

    private var payTitle: String { vm.isBusy ? "Processing…" : "Reserve my place" }

    private func pay() {
        Haptics.bump()
        guard auth.hasAccount else { showAccount = true; return }
        Task {
            await vm.reserve()
            if vm.isReserved { onReserved() }
        }
    }

    // MARK: - Chrome / helpers

    private var topBar: some View {
        HStack {
            Button {
                Haptics.tap()
                dismiss()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "chevron.left").font(.system(size: 12, weight: .semibold))
                    Text("Back").font(Theme.body(13)).underline()
                }
                .foregroundStyle(.white)
            }
            .buttonStyle(.plain)
            Spacer()
            Text("RESERVE").font(Theme.eyebrow(11)).tracking(2.5)
                .foregroundStyle(.white.opacity(0.85))
        }
    }

    private var rule: some View { Rectangle().fill(RetreatPalette.glassLine).frame(height: 1) }

    private func summaryRow(_ title: String, _ detail: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(Theme.body(14)).foregroundStyle(RetreatPalette.cream)
                Text(detail).font(Theme.body(11)).foregroundStyle(RetreatPalette.muted)
            }
            Spacer(minLength: 12)
            Text(value).font(Theme.headline(17, weight: .light)).foregroundStyle(RetreatPalette.cream)
        }
    }

    private func eyebrow(_ text: String) -> some View {
        Text(text.uppercased())
            .font(Theme.eyebrow(10)).tracking(3)
            .foregroundStyle(RetreatPalette.terracotta)
    }
}

#Preview {
    NavigationStack {
        RetreatCheckoutView(retreat: Retreat.mock[0])
            .toolbar(.hidden, for: .navigationBar)
    }
    .environment(AppState().auth)
    .preferredColorScheme(.dark)
}
