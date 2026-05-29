//
//  RecipeView.swift
//  Soulfull Gatherings
//
//  Food Recipes section. The list shows each dish; the detail screen leads
//  with a full-bleed photo, then meta, ingredients, and method.
//  Mock-driven until a `recipes` table is seeded.
//

import SwiftUI

struct RecipeListView: View {
    let onOpen: (Recipe) -> Void
    private let recipes = Recipe.all

    var body: some View {
        PracticeListScaffold(
            title: PracticeMenuItem.recipes.title,
            blurb: PracticeMenuItem.recipes.blurb,
            systemImage: PracticeMenuItem.recipes.systemImage,
            backdrop: PracticeMenuItem.recipes.imageName
        ) {
            VStack(spacing: 14) {
                ForEach(recipes) { recipe in
                    recipeCard(recipe)
                        .onTapGesture {
                            Haptics.tap()
                            onOpen(recipe)
                        }
                }
            }
        }
    }

    private func recipeCard(_ recipe: Recipe) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            ZStack(alignment: .bottomLeading) {
                Image(recipe.imageUrl)
                    .resizable().scaledToFill()
                    .frame(height: 160)
                    .clipped()
                LinearGradient(colors: [.clear, .black.opacity(0.6)], startPoint: .top, endPoint: .bottom)
                Text("\(recipe.lead) · \(recipe.minutes) MIN".uppercased())
                    .font(Theme.eyebrow(10))
                    .tracking(2)
                    .foregroundStyle(.white)
                    .padding(14)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(recipe.title)
                    .font(Theme.headline(20))
                    .foregroundStyle(Theme.ink)
                    .kerning(-0.2)
                    .lineLimit(2)
                Text(recipe.blurb)
                    .font(Theme.body(12))
                    .foregroundStyle(Theme.muted)
                    .lineLimit(2)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(Theme.glassBorder, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

// MARK: - Detail

struct RecipeDetailView: View {
    @Environment(\.dismiss) private var dismiss
    let recipe: Recipe

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                ZStack(alignment: .top) {
                    Image(recipe.imageUrl)
                        .resizable().scaledToFill()
                        .frame(height: 320)
                        .clipped()
                    LinearGradient(colors: [.black.opacity(0.45), .clear, .black.opacity(0.35)],
                                   startPoint: .top, endPoint: .bottom)
                        .frame(height: 320)
                    HStack {
                        Button {
                            Haptics.tap()
                            dismiss()
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "chevron.left").font(.system(size: 12, weight: .semibold))
                                Text("Recipes").font(Theme.body(13)).underline()
                            }
                            .foregroundStyle(.white)
                        }
                        .buttonStyle(.plain)
                        Spacer()
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 8)
                }

                VStack(alignment: .leading, spacing: 18) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(recipe.lead.uppercased())
                            .font(Theme.eyebrow(11))
                            .tracking(3)
                            .foregroundStyle(Theme.muted)
                        Text(recipe.title)
                            .font(Theme.headline(32))
                            .foregroundStyle(Theme.ink)
                            .kerning(-0.3)
                            .fixedSize(horizontal: false, vertical: true)

                        HStack(spacing: 10) {
                            metaPill("clock", "\(recipe.minutes) min")
                            metaPill("person.2", "\(recipe.servings) servings")
                        }
                        .padding(.top, 2)

                        Text(recipe.blurb)
                            .font(Theme.body(14))
                            .foregroundStyle(Theme.inkSoft)
                            .lineSpacing(4)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.top, 2)
                    }

                    section("INGREDIENTS") {
                        VStack(alignment: .leading, spacing: 10) {
                            ForEach(recipe.ingredients, id: \.self) { item in
                                HStack(alignment: .top, spacing: 12) {
                                    Circle().fill(Theme.inkSoft).frame(width: 5, height: 5).padding(.top, 7)
                                    Text(item)
                                        .font(Theme.body(15))
                                        .foregroundStyle(Theme.ink)
                                        .fixedSize(horizontal: false, vertical: true)
                                    Spacer(minLength: 0)
                                }
                            }
                        }
                    }

                    section("METHOD") {
                        VStack(spacing: 14) {
                            ForEach(Array(recipe.steps.enumerated()), id: \.offset) { index, step in
                                NumberedStepRow(index: index + 1, title: step)
                            }
                        }
                    }

                    Color.clear.frame(height: 120)
                }
                .padding(.top, 18)
                .padding(.horizontal, 20)
            }
        }
        .scrollIndicators(.hidden)
        .ignoresSafeArea(edges: .top)
        .background(Theme.bg)
    }

    private func metaPill(_ icon: String, _ text: String) -> some View {
        Label(text, systemImage: icon)
            .font(Theme.body(11, weight: .medium))
            .foregroundStyle(Theme.ink)
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(.ultraThinMaterial, in: Capsule())
            .overlay(Capsule().strokeBorder(Theme.glassBorder, lineWidth: 1))
    }

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(Theme.eyebrow(11))
                .tracking(3)
                .foregroundStyle(Theme.muted)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(Theme.glassBorder, lineWidth: 1))
    }
}

#Preview {
    NavigationStack {
        RecipeDetailView(recipe: Recipe.all[0])
            .toolbar(.hidden, for: .navigationBar)
    }
    .preferredColorScheme(.dark)
}
