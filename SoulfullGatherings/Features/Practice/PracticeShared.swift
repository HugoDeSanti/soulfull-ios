//
//  PracticeShared.swift
//  Soulfull Gatherings
//
//  Shared chrome for the Practice feature: the back bar used on every pushed
//  screen, and the list scaffold (blurred backdrop + back bar + header) that
//  every category / section list is built on.
//

import SwiftUI

// MARK: - Back bar (pops the current pushed screen)

struct PracticeBackBar: View {
    var label: String = "Practices"
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        HStack {
            Button {
                Haptics.tap()
                dismiss()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "chevron.left").font(.system(size: 12, weight: .semibold))
                    Text(label)
                        .font(Theme.body(13))
                        .underline()
                }
                .foregroundStyle(Theme.ink)
            }
            .buttonStyle(.plain)
            Spacer()
        }
    }
}

// MARK: - List scaffold (backdrop + back bar + icon/title/blurb header)

struct PracticeListScaffold<Content: View>: View {
    let title: String
    let blurb: String
    let systemImage: String
    let backdrop: String
    var backLabel: String = "Practices"
    @ViewBuilder var content: Content

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                PracticeBackBar(label: backLabel)
                header
                content
                Color.clear.frame(height: 120)
            }
            .padding(.top, 8)
            .padding(.horizontal, 20)
        }
        .scrollIndicators(.hidden)
        .background {
            PhotoBackdrop(imageName: backdrop, blur: 22, darken: 0.78)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Image(systemName: systemImage)
                    .font(.system(size: 13, weight: .semibold))
                Text(title.uppercased())
                    .font(Theme.eyebrow(11))
                    .tracking(3)
            }
            .foregroundStyle(Theme.muted)

            Text(title)
                .font(Theme.headline(34))
                .foregroundStyle(Theme.ink)
                .kerning(-0.3)
            Text(blurb)
                .font(Theme.body(13))
                .foregroundStyle(Theme.inkSoft)
                .lineSpacing(3)
                .padding(.top, 2)
        }
        .padding(.bottom, 4)
    }
}

// MARK: - Numbered step row (shared by exercises, recipes, massages)

struct NumberedStepRow: View {
    let index: Int
    let title: String
    var detail: String? = nil

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Text("\(index)")
                .font(Theme.body(14, weight: .semibold))
                .foregroundStyle(Theme.ink)
                .frame(width: 30, height: 30)
                .background(.ultraThinMaterial, in: Circle())
                .overlay(Circle().strokeBorder(Theme.glassBorder, lineWidth: 1))

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(Theme.body(15))
                    .foregroundStyle(Theme.ink)
                    .fixedSize(horizontal: false, vertical: true)
                if let detail {
                    Text(detail)
                        .font(Theme.eyebrow(11))
                        .tracking(1)
                        .textCase(.uppercase)
                        .foregroundStyle(Theme.inkSoft)
                }
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
