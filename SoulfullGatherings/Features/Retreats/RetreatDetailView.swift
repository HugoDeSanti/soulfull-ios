//
//  RetreatDetailView.swift
//  Soulfull Gatherings
//
//  Iceland-style editorial detail screen: full-bleed photo, centered title,
//  white pill reserve CTA, glass meta pills. Pushed onto NavigationStack
//  so the standard swipe-back works.
//

import SwiftUI

struct RetreatDetailView: View {
    @Environment(\.dismiss) private var dismiss
    let retreat: Retreat

    @State private var reserved = false

    var body: some View {
        ZStack {
            // Full-bleed photo
            Image(retreat.imageUrl)
                .resizable().scaledToFill()
                .ignoresSafeArea()

            // Vignette
            LinearGradient(
                colors: [.black.opacity(0.42), .black.opacity(0.10), .black.opacity(0.08), .black.opacity(0.62)],
                startPoint: .top, endPoint: .bottom
            )
            .ignoresSafeArea()

            // Top chrome (back / share)
            VStack {
                topBar
                    .padding(.horizontal, 24)
                    .padding(.top, 8)
                Spacer()
            }

            // Center editorial block
            VStack(spacing: 18) {
                Text("Gathering")
                    .font(Theme.body(15))
                    .foregroundStyle(Color.white.opacity(0.85))
                Text(retreat.name)
                    .font(.system(size: 64, weight: .semibold))
                    .kerning(-2.4)
                    .foregroundStyle(.white)

                Button {
                    Haptics.success()
                    withAnimation(.spring(response: 0.45, dampingFraction: 0.8)) {
                        reserved = true
                    }
                } label: {
                    HStack(spacing: 8) {
                        if reserved {
                            Image(systemName: "checkmark").font(.system(size: 14, weight: .semibold))
                        }
                        Text(reserved ? "Reserved" : "Reserve")
                            .font(Theme.body(15, weight: .medium))
                    }
                    .foregroundStyle(.black)
                    .padding(.horizontal, 36)
                    .padding(.vertical, 14)
                    .background(Capsule().fill(.white))
                    .shadow(color: .black.opacity(0.18), radius: 20, y: 6)
                }
                .buttonStyle(.plain)
                .padding(.top, 4)
            }
            .padding(.horizontal, 24)

            // Bottom meta + tagline
            VStack(spacing: 12) {
                Spacer()
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
                    .padding(.bottom, 32)
            }
            .padding(.horizontal, 24)
        }
        .preferredColorScheme(.dark)
        .navigationBarBackButtonHidden(true)
        .toolbar(.hidden, for: .navigationBar)
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
            CircleIconButton(systemName: "square.and.arrow.up", size: 38) { Haptics.tap() }
        }
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
            .background(.ultraThinMaterial, in: Capsule())
            .overlay(Capsule().strokeBorder(Theme.glassBorderHigh, lineWidth: 1))
    }
}

#Preview {
    let cal = Calendar.current
    let sample = Retreat(
        id: 0, name: "Mallorca", country: "Spain",
        startDate: cal.date(from: DateComponents(year: 2026, month: 4, day: 18))!,
        endDate:   cal.date(from: DateComponents(year: 2026, month: 4, day: 23))!,
        maxGuests: 14, priceUsd: 4400,
        tags: ["Hyrox", "Recovery", "Wellness"],
        blurb: "Cliffside training mornings, cove swims, recovery rituals on the sand. Push and return.",
        imageUrl: "retreat-mallorca",
        toneTop:  Color(red: 0.45, green: 0.62, blue: 0.65),
        toneMid:  Color(red: 0.20, green: 0.32, blue: 0.40),
        toneBase: Color(red: 0.06, green: 0.10, blue: 0.14)
    )
    return NavigationStack {
        RetreatDetailView(retreat: sample)
            .toolbar(.hidden, for: .navigationBar)
    }
    .preferredColorScheme(.dark)
}
