//
//  RecipeView.swift
//  Soulfull Gatherings
//
//  Food Recipes section. The list shows each dish; the detail screen leads
//  with a full-bleed photo, then meta, ingredients, and method.
//  The recipes are the `recipes` table, through WrittenPracticeStore.
//

import SwiftUI

struct RecipeListView: View {
    let onOpen: (Recipe) -> Void
    private let store = WrittenPracticeStore.shared

    var body: some View {
        PracticeListScaffold(
            title: PracticeMenuItem.recipes.title,
            blurb: PracticeMenuItem.recipes.blurb,
            systemImage: PracticeMenuItem.recipes.systemImage,
            backdrop: PracticeMenuItem.recipes.imageName
        ) {
            if store.library.recipes.isEmpty {
                WrittenLibraryPlaceholder(item: .recipes, noun: "recipes")
            } else {
                VStack(spacing: 14) {
                    ForEach(store.library.recipes) { recipe in
                        PressableCard(action: { onOpen(recipe) }) {
                            recipeCard(recipe)
                        }
                        .accessibilityIdentifier("recipe-card")
                        .listReveal()
                    }
                }
            }
        }
        .task { await store.refresh() }
    }

    private func recipeCard(_ recipe: Recipe) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            ZStack(alignment: .bottomLeading) {
                Color.clear
                    .frame(height: 160)
                    .frame(maxWidth: .infinity)
                    .overlay {
                        CatalogImage(recipe.imageUrl) { $0.resizable().scaledToFill() }
                    }
                    .clipped()
                LinearGradient(colors: [.clear, .black.opacity(0.6)], startPoint: .top, endPoint: .bottom)
                Text("\(recipe.angle) · \(recipe.minutes) MIN".uppercased())
                    .font(Theme.eyebrow(10))
                    .tracking(2)
                    .foregroundStyle(.white)
                    .padding(14)
            }
            .frame(height: 160)
            .clipped()
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
                PresenceLine(kind: .recipe, contentID: recipe.id, faceSize: 18)
                    .padding(.top, 6)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .soulGlassCard(radius: 18)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        // Clip the hit-test region: `scaledToFill` + `.clipped()`/`.clipShape()`
        // only clip visually, so the hero image's tap area overflows up into
        // the back bar and the first card swallows the "Practices" tap.
        .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

// MARK: - Detail

struct RecipeDetailView: View {
    @Environment(\.dismiss) private var dismiss
    let recipe: Recipe
    /// Pantry checklist — ticked ingredients for this cooking session.
    @State private var gathered: Set<String> = []
    /// Normalized scroll offset for the stretchy hero.
    @State private var scrollY: CGFloat = 0

    var body: some View {
        ZStack(alignment: .topLeading) {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    ZStack(alignment: .top) {
                        CatalogImage(recipe.imageUrl) { $0.resizable().scaledToFill() }
                            .frame(height: 320)
                            .clipped()
                            // Stretch on pull-down, anchored to the top edge.
                            .scaleEffect(1 + max(0, -scrollY) / 500, anchor: .top)
                        LinearGradient(colors: [.black.opacity(0.45), .clear, .black.opacity(0.35)],
                                       startPoint: .top, endPoint: .bottom)
                            .frame(height: 320)
                    }

                    VStack(alignment: .leading, spacing: 18) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(recipe.angle.uppercased())
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

                        PresenceLine(kind: .recipe, contentID: recipe.id, faceSize: 22)
                            .padding(.top, 4)

                        Text(recipe.blurb)
                            .font(Theme.body(14))
                            .foregroundStyle(Theme.inkSoft)
                            .lineSpacing(4)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.top, 2)
                    }

                    GuideCard(instructorID: recipe.instructorID, from: recipe.title)

                    section("INGREDIENTS") {
                        VStack(alignment: .leading, spacing: 4) {
                            ForEach(recipe.ingredients, id: \.self) { item in
                                ingredientRow(item)
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
            .practiceActivity(.recipe(recipe))
            .ignoresSafeArea(edges: .top)
            .background(Theme.bg)
            .onScrollGeometryChange(for: CGFloat.self) { geo in
                geo.contentOffset.y + geo.contentInsets.top
            } action: { _, new in
                scrollY = new
            }

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
            .padding(.horizontal, 20)
            .padding(.top, 8)
        }
    }

    /// Tappable pantry row: ticking an ingredient springs the check in and
    /// softens the label — a tiny mise-en-place ritual.
    private func ingredientRow(_ item: String) -> some View {
        let checked = gathered.contains(item)
        return Button {
            Haptics.select()
            withAnimation(.spring(response: 0.35, dampingFraction: 0.6)) {
                if checked { gathered.remove(item) } else { gathered.insert(item) }
            }
        } label: {
            HStack(alignment: .top, spacing: 12) {
                ZStack {
                    Circle()
                        .strokeBorder(checked ? Theme.honey : Theme.inkSoft.opacity(0.5), lineWidth: 1.2)
                        .frame(width: 20, height: 20)
                    if checked {
                        Image(systemName: "checkmark")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(Theme.honey)
                            .transition(.scale(scale: 0.3).combined(with: .opacity))
                    }
                }
                .padding(.top, 1)

                Text(item)
                    .font(Theme.body(15))
                    .foregroundStyle(checked ? Theme.muted : Theme.ink)
                    .strikethrough(checked, color: Theme.muted.opacity(0.6))
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.vertical, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(checked ? .isSelected : [])
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
        RecipeDetailView(recipe: Recipe.mock[0])
            .toolbar(.hidden, for: .navigationBar)
    }
    .preferredColorScheme(.dark)
}
