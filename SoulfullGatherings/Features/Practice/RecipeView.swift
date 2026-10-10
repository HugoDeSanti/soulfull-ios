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
                VStack(spacing: 28) {
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
                    .foregroundStyle(Theme.ink)
                    .padding(16)
            }
            .frame(height: 160)
            .clipped()
            VStack(alignment: .leading, spacing: 6) {
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
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .soulGlassCard()
        .clipped()
        // Clip the hit-test region: `scaledToFill` + `.clipped()` only clip
        // visually, so the hero image's tap area overflows up into the back
        // bar and the first card swallows the "Practices" tap.
        .contentShape(Rectangle())
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

                    VStack(alignment: .leading, spacing: 36) {
                    VStack(alignment: .leading, spacing: 10) {
                        Text(recipe.angle.uppercased())
                            .font(Theme.eyebrow(11))
                            .tracking(3)
                            .foregroundStyle(Theme.muted)
                        Text(recipe.title)
                            .font(Theme.headline(32, weight: .light))
                            .foregroundStyle(Theme.ink)
                            .kerning(-0.7)
                            .fixedSize(horizontal: false, vertical: true)

                        // Time and servings as a line of type, not two pills.
                        HStack(spacing: 10) {
                            metaItem("clock", "\(recipe.minutes) min")
                            Text("·")
                            metaItem("person.2", "\(recipe.servings) servings")
                        }
                        .font(Theme.body(12))
                        .foregroundStyle(Theme.inkSoft)
                        .padding(.top, 4)

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
                        VStack(spacing: 0) {
                            ForEach(Array(recipe.steps.enumerated()), id: \.offset) { index, step in
                                NumberedStepRow(index: index + 1, title: step)
                                    .padding(.vertical, 14)
                                    .overlay(alignment: .top) {
                                        if index > 0 { PracticeRule() }
                                    }
                            }
                        }
                    }

                    Color.clear.frame(height: 120)
                }
                .padding(.top, 28)
                .padding(.horizontal, Theme.gutter)
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
                HStack(spacing: 10) {
                    Image(systemName: "arrow.left").font(.system(size: 15, weight: .light))
                    Text("Recipes").font(Theme.body(13))
                }
                .foregroundStyle(Theme.ink)
                .onPhoto()
                // The drawn label is ~20pt tall; give the thumb a full row.
                .frame(minWidth: 44, minHeight: 44, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.horizontal, Theme.gutter)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                // The link is pinned while the page scrolls under it. Over the
                // photo it reads on its own; once the hero has gone, it sat on
                // the title and the ingredients. The page's own ground rises
                // behind it as the photo leaves, under the status bar too.
                LinearGradient(stops: [.init(color: Theme.bg, location: 0),
                                       .init(color: Theme.bg.opacity(0.92), location: 0.7),
                                       .init(color: Theme.bg.opacity(0), location: 1)],
                               startPoint: .top, endPoint: .bottom)
                    .padding(.bottom, -14)
                    .ignoresSafeArea(edges: .top)
                    .opacity(backScrim)
                    .allowsHitTesting(false)
            }
        }
    }

    /// 0 while the link is over the hero, 1 by the time the title reaches it.
    /// The hero runs 320pt from the top of the screen and the link's row ends
    /// ~105pt down, so the title arrives under it at ~230pt of scroll.
    private var backScrim: Double {
        Double(min(1, max(0, (scrollY - 170) / 60)))
    }

    /// Tappable pantry row: ticking an ingredient fades a check into its
    /// square and softens the label — a tiny mise-en-place ritual.
    private func ingredientRow(_ item: String) -> some View {
        let checked = gathered.contains(item)
        return Button {
            Haptics.select()
            withAnimation(Theme.Motion.settle) {
                if checked { gathered.remove(item) } else { gathered.insert(item) }
            }
        } label: {
            HStack(alignment: .top, spacing: 14) {
                ZStack {
                    Rectangle()
                        .strokeBorder(checked ? Theme.ember : Theme.inkSoft.opacity(0.5), lineWidth: Theme.hairline)
                        .frame(width: 18, height: 18)
                    if checked {
                        Image(systemName: "checkmark")
                            .font(.system(size: 10, weight: .regular))
                            .foregroundStyle(Theme.ember)
                            .transition(.opacity)
                    }
                }
                .padding(.top, 2)

                Text(item)
                    .font(Theme.body(15))
                    .foregroundStyle(checked ? Theme.muted : Theme.ink)
                    .strikethrough(checked, color: Theme.muted.opacity(0.6))
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.vertical, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(checked ? .isSelected : [])
    }

    private func metaItem(_ icon: String, _ text: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .light))
            Text(text)
        }
    }

    /// A section of the page: a hairline across the measure, a caps label,
    /// and the content set open beneath — no box.
    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            PracticeRule()
            Text(title)
                .font(Theme.eyebrow(11))
                .tracking(3)
                .foregroundStyle(Theme.inkSoft)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

#Preview {
    NavigationStack {
        RecipeDetailView(recipe: Recipe.mock[0])
            .toolbar(.hidden, for: .navigationBar)
    }
    .preferredColorScheme(.dark)
}
