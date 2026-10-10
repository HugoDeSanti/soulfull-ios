//
//  RetreatDetailView.swift
//  Soulfull Gatherings
//
//  Editorial spread. At rest it's the full-bleed cover — centered title, a
//  square ink reserve button, the particulars in one line. Scrolling reveals
//  the story, laid like a printed page: sections opened by a hairline and a
//  small caps label, with air between them and no boxes. A retreat carrying
//  a `RetreatExperience` (e.g. Mallorca) gets the full spread — invitation,
//  who it's for, the four elements, a member's word, guides, stay &
//  inclusions; one without falls back to the concise pull-quote / numbered
//  focus / details layout. The cover photo answers the scroll — stretching
//  on pull-down, going out of focus and nearly to black as the story comes
//  up — and a reserve bar fades in once the hero CTA has scrolled away.
//

import SwiftUI

struct RetreatDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(AuthManager.self) private var auth
    @Environment(AppSettings.self) private var settings
    let retreat: Retreat
    /// Push the checkout review screen (Reserve, when signed in and not yet
    /// reserved). Payment itself runs on the checkout screen.
    /// Open the post-purchase experience hub (once the retreat is reserved).
    var onOpenExperience: (Retreat) -> Void = { _ in }

    @State private var vm: RetreatDetailViewModel
    @State private var showAccount = false
    /// The retreat application — the website's "Join a retreat" form, asked
    /// in the app. Raised by the CTA while reservations are off.
    @State private var showEnquiry = false
    /// Normalized scroll offset: 0 at rest, negative when pulled down.
    @State private var scrollY: CGFloat = 0

    init(retreat: Retreat,
         onOpenExperience: @escaping (Retreat) -> Void = { _ in }) {
        self.retreat = retreat
        self.onOpenExperience = onOpenExperience
        _vm = State(initialValue: RetreatDetailViewModel(retreat: retreat))
    }

    /// The long-form brochure, decoded from this retreat's `experience` jsonb
    /// column. `nil` — no document, or an unreadable one — falls through to
    /// `basicStory`, which builds a real page out of `blurb` and `tags`.
    ///
    /// It used to fall back to `RetreatExperience.curated(for:)`, a switch on
    /// the retreat's name with exactly one case. That meant brochure content
    /// shipped in the binary: any retreat that wasn't Mallorca got the short
    /// layout and no amount of editing the database could change it.
    private var exp: RetreatExperience? {
        retreat.experience
    }

    /// The brochure's own date line if it overrides one, else the range
    /// derived from the row's real dates. `flatMap` because `dateRange` is
    /// itself optional — `exp?.dateRange` is a double optional.
    private var whenLabel: String { exp.flatMap(\.dateRange) ?? retreat.when }

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
                    .padding(.horizontal, Theme.gutter)
                    .padding(.top, 8)
                    .background(alignment: .top) { topBarScrim }
                Spacer()
            }

            // Pinned reserve bar once the hero CTA is gone.
            VStack {
                Spacer()
                if scrollY > 260 {
                    reserveBar
                        .transition(.opacity)
                }
            }
            .animation(Theme.Motion.settle, value: scrollY > 260)
        }
        .preferredColorScheme(.dark)
        .navigationBarBackButtonHidden(true)
        .toolbar(.hidden, for: .navigationBar)
        // Only meaningful when reservations exist; skipped in v1 so the screen
        // makes no `bookings` round-trip it can't act on.
        .task(id: auth.userID) {
            guard AppFeatures.paymentsEnabled else { return }
            await vm.loadExistingBooking(userID: auth.userID)
        }
        // Dismissing this having signed in replays the tap that raised it —
        // the same bargain `AccountGate` strikes everywhere else in the app.
        .sheet(isPresented: $showAccount, onDismiss: {
            if auth.hasAccount { showEnquiry = true }
        }) {
            // Onboarding already asked their name — same as the shared gate.
            AccountView(initialName: settings.userName)
        }
        .sheet(isPresented: $showEnquiry) {
            // Seeded with what we already know so the form asks for as little
            // as it can. The address is the account's and is shown locked —
            // the server takes the real one from the JWT either way.
            RetreatEnquiryView(
                retreat: retreat,
                initialName: settings.userName,
                accountEmail: auth.email ?? ""
            )
        }
    }

    // MARK: - Hero photo (scroll-graded)

    private var hero: some View {
        GeometryReader { proxy in
            ZStack {
                CatalogImage(retreat.imageUrl) { image in
                    image
                        .resizable().scaledToFill()
                        .frame(width: proxy.size.width, height: proxy.size.height)
                        .clipped()
                }
                .frame(width: proxy.size.width, height: proxy.size.height)
                .clipped()
                // Stretch on pull-down, soften under the story. Under Reduce
                // Motion the photo holds still and a deeper dim does the
                // softening's job of grounding the story's type.
                .scaleEffect(reduceMotion ? 1 : 1 + max(0, -scrollY) / 700)
                .blur(radius: reduceMotion ? 0 : min(14, max(0, scrollY) / 26))

                // The middle stops used to fall to 0.08 — right where the
                // cover's kind line and blurb sit, on an unblurred photo. They
                // now hold enough to be that type's ground, the same job the
                // top scrim does on every PhotoBackdrop screen.
                LinearGradient(
                    colors: [.black.opacity(0.45), .black.opacity(0.24), .black.opacity(0.22), .black.opacity(0.64)],
                    startPoint: .top, endPoint: .bottom
                )

                // The story reads on near-black: the photo is the cover, not
                // the page, so it sinks almost out of sight as the story
                // comes up.
                Color.black.opacity(min(reduceMotion ? 0.8 : 0.72, Double(max(0, scrollY)) / 560))
            }
        }
        .ignoresSafeArea()
    }

    // MARK: - Cover page (first viewport)

    private var coverPage: some View {
        VStack(spacing: 0) {
            Spacer()

            VStack(spacing: 18) {
                Text(exp?.kind ?? "Gathering")
                    .font(Theme.body(15))
                    .foregroundStyle(Theme.inkOnPhoto)
                    .multilineTextAlignment(.center)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    // The hero is unblurred and its gradient thins to 0.08
                    // right here, so the cover type carries its own ground.
                    .onPhoto()
                Text(retreat.name)
                    .font(Theme.headline(64, weight: .light))
                    .kerning(-2.2)
                    .foregroundStyle(Theme.ink)
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)
                    .onPhoto()

                reserveButton

                if let error = vm.errorMessage {
                    Text(error)
                        .font(Theme.body(12))
                        .foregroundStyle(Theme.inkOnPhoto)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 300)
                        .padding(.top, 2)
                }
            }
            .padding(.horizontal, Theme.gutter)
            .animation(Theme.Motion.settle, value: vm.phase)

            Spacer()

            VStack(spacing: 14) {
                // The particulars in one line, the way a printed programme
                // runs them — they were three glass pills.
                Text([whenLabel, "\(retreat.maxGuests) guests", retreat.priceFormatted]
                        .joined(separator: "  ·  "))
                    .font(Theme.body(12))
                    .tracking(0.6)
                    .foregroundStyle(Theme.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .onPhoto()
                Text(exp?.coverLine ?? retreat.blurb)
                    .font(Theme.body(12))
                    .foregroundStyle(Theme.inkOnPhoto)
                    .multilineTextAlignment(.center)
                    .lineSpacing(2)
                    .frame(maxWidth: 320)
                    .onPhoto()

                Image(systemName: "chevron.compact.down")
                    .font(.system(size: 22, weight: .light))
                    .foregroundStyle(Theme.ink.opacity(0.7))
                    .breathing(scale: 1.0...1.0, opacity: 0.35...0.85)
                    .padding(.top, 10)
            }
            .padding(.horizontal, Theme.gutter)
            .padding(.bottom, 36)
            // Fade the cover furniture as the story arrives.
            .opacity(1 - min(1, Double(max(0, scrollY)) / 220))
        }
    }

    private var reserveButton: some View {
        Button {
            routeReserve()
        } label: {
            HStack(spacing: 8) {
                if vm.isReserved {
                    Image(systemName: "arrow.right").font(.system(size: 14, weight: .regular))
                }
                Text(reserveTitle)
                    .font(Theme.body(15, weight: .medium))
            }
            .foregroundStyle(.black)
            .padding(.horizontal, 40)
            .padding(.vertical, 16)
            .background(Rectangle().fill(Theme.ink))
        }
        .buttonStyle(SoulPressableStyle(hapticOnPress: false))
        .padding(.top, 4)
        .accessibilityLabel(reserveTitle)
        .accessibilityHint(AppFeatures.paymentsEnabled
                           ? "Reserve a place on \(retreat.name)"
                           : "Opens the application form for \(retreat.name)")
    }

    /// Reserve-CTA routing.
    ///
    /// While `AppFeatures.paymentsEnabled` is off (v1), the CTA is an
    /// application rather than a checkout — `RetreatEnquiryView`, which asks
    /// the same questions as the "Join a retreat" form on the website and
    /// mails the answers to the team. That keeps the screen genuinely
    /// actionable instead of showing a dead "reservations open soon" line.
    ///
    /// It used to open a blank `mailto:` with only a subject line, which left
    /// the guest to guess what the team needed to know and gave the team an
    /// inbox of applications that each answered something different.
    ///
    /// Applying needs an account, so a guest gets `AccountView` first. That is
    /// a gate on an *action*, not on browsing — the catalog and this whole
    /// brochure stay open to a guest — and it is here because the application's
    /// Email answer *is* the account's address.
    ///
    /// A retreat that is already reserved opens its experience hub — that
    /// still works with no payment rail, because `bookings` is read from the
    /// server, not written here.
    ///
    /// Everything else is an enquiry. v1 has **no client-side checkout at all**
    /// now that the StripePaymentSheet dependency is dropped, so there is
    /// nothing to push even if `paymentsEnabled` were flipped — restoring the
    /// charge means restoring the dependency and the two deleted files first.
    private func routeReserve() {
        Haptics.bump()

        if AppFeatures.paymentsEnabled, vm.isReserved {
            onOpenExperience(retreat)
            return
        }

        guard auth.hasAccount else {
            showAccount = true
            return
        }
        showEnquiry = true
    }

    private var reserveTitle: String {
        if AppFeatures.paymentsEnabled, vm.isReserved { return "View your experience" }
        return "Request a place"
    }

    // MARK: - Story sections

    @ViewBuilder
    private var storySections: some View {
        if let exp {
            richStory(exp)
        } else {
            basicStory
        }
    }

    // MARK: Rich story (retreats carrying a RetreatExperience)

    private func richStory(_ exp: RetreatExperience) -> some View {
        VStack(alignment: .leading, spacing: Theme.sectionGap) {
            invitationSection(exp)
            whoForSection(exp)
            elementsSection(exp)
            if let testimonial = exp.testimonial {
                testimonialSection(testimonial)
            }
            guidesSection(exp)
            staySection(exp)
            closingCTA
        }
        .padding(.horizontal, Theme.gutter)
        .padding(.top, 48)
    }

    private func invitationSection(_ exp: RetreatExperience) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            sectionEyebrow("The Experience")
            ForEach(Array(exp.invitation.enumerated()), id: \.offset) { idx, stanza in
                if idx == 0 {
                    Text(stanza)
                        .font(Theme.headline(27, weight: .light))
                        .kerning(-0.4)
                        .foregroundStyle(Theme.ink)
                        .lineSpacing(6)
                } else {
                    Text(stanza)
                        .font(Theme.body(15))
                        .foregroundStyle(Theme.inkSoft)
                        .lineSpacing(5)
                }
            }
        }
    }

    private func whoForSection(_ exp: RetreatExperience) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            sectionEyebrow("Who This Is For")
            VStack(alignment: .leading, spacing: 12) {
                ForEach(exp.whoFor, id: \.self) { line in
                    Text(line)
                        .font(Theme.body(15))
                        .foregroundStyle(Theme.inkSoft)
                        .lineSpacing(5)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            // Welcome line as a pull-quote, ruled by one ember hairline.
            HStack(alignment: .top, spacing: 16) {
                Rectangle()
                    .fill(Theme.ember.opacity(0.8))
                    .frame(width: 1)
                Text(exp.welcome)
                    .font(Theme.headline(21, weight: .light))
                    .kerning(-0.3)
                    .foregroundStyle(Theme.ink)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.top, 4)
        }
    }

    private func elementsSection(_ exp: RetreatExperience) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                sectionEyebrow("The Rhythm of Each Day")
                Text("Every day is built from four elements.")
                    .font(Theme.body(14))
                    .foregroundStyle(Theme.inkSoft)
            }
            VStack(spacing: 0) {
                ForEach(Array(exp.elements.enumerated()), id: \.element.id) { idx, el in
                    elementCard(el, folio: idx + 1)
                }
            }
        }
    }

    /// One of the day's four elements: open on the page, under a hairline,
    /// rather than in a box.
    private func elementCard(_ el: RetreatExperience.Element, folio: Int) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                Image(systemName: el.systemImage)
                    .font(.system(size: 15, weight: .light))
                    .foregroundStyle(Theme.ember)
                    .frame(width: 22)
                Text(el.title)
                    .font(Theme.headline(25, weight: .light))
                    .kerning(-0.4)
                    .foregroundStyle(Theme.ink)
                Spacer()
                Text(String(format: "%02d", folio))
                    .font(Theme.body(12, weight: .medium))
                    .tracking(1)
                    .foregroundStyle(Theme.muted)
            }
            Text(el.summary)
                .font(Theme.body(15))
                .foregroundStyle(Theme.inkSoft)
                .lineSpacing(4)
                .fixedSize(horizontal: false, vertical: true)
            VStack(alignment: .leading, spacing: 9) {
                ForEach(el.highlights, id: \.self) { highlight in
                    HStack(alignment: .top, spacing: 11) {
                        Circle()
                            .fill(Theme.inkSoft.opacity(0.6))
                            .frame(width: 3, height: 3)
                            .padding(.top, 7)
                        Text(highlight)
                            .font(Theme.body(14))
                            .foregroundStyle(Theme.ink)
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 0)
                    }
                }
            }
        }
        .padding(.vertical, 26)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .top) {
            Rectangle().fill(Theme.line).frame(height: 0.5)
        }
    }

    private func testimonialSection(_ t: RetreatExperience.Testimonial) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            sectionEyebrow("A Member's Word")
            VStack(alignment: .leading, spacing: 16) {
                Text("\u{201C}")
                    .font(Theme.headline(56, weight: .thin))
                    .foregroundStyle(Theme.ember.opacity(0.7))
                    .frame(height: 26, alignment: .top)
                Text(t.quote)
                    .font(Theme.headline(20, weight: .light))
                    .kerning(-0.2)
                    .foregroundStyle(Theme.ink)
                    .lineSpacing(6)
                    .fixedSize(horizontal: false, vertical: true)
                VStack(alignment: .leading, spacing: 3) {
                    Text(t.author)
                        .font(Theme.body(14, weight: .medium))
                        .foregroundStyle(Theme.ink)
                    Text(t.attribution)
                        .font(Theme.eyebrow(10))
                        .tracking(1.5)
                        .textCase(.uppercase)
                        .foregroundStyle(Theme.muted)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func guidesSection(_ exp: RetreatExperience) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                sectionEyebrow("Your Guides")
                Text("A small team leads the week — you're in attentive hands from the first morning to the last.")
                    .font(Theme.body(14))
                    .foregroundStyle(Theme.inkSoft)
                    .lineSpacing(4)
                    .fixedSize(horizontal: false, vertical: true)
            }
            VStack(spacing: 0) {
                ForEach(Array(exp.guides.enumerated()), id: \.element.id) { idx, guide in
                    HStack(spacing: 14) {
                        Text(guide.initials)
                            .font(Theme.body(13, weight: .medium))
                            .foregroundStyle(Theme.ink)
                            .frame(width: 42, height: 42)
                            .soulGlass(in: Circle())
                        VStack(alignment: .leading, spacing: 2) {
                            Text(guide.name)
                                .font(Theme.body(15, weight: .medium))
                                .foregroundStyle(Theme.ink)
                            Text(guide.role)
                                .font(Theme.eyebrow(10))
                                .tracking(1.5)
                                .textCase(.uppercase)
                                .foregroundStyle(Theme.muted)
                        }
                        Spacer()
                    }
                    .padding(.vertical, 14)
                    .overlay(alignment: .bottom) {
                        if idx < exp.guides.count - 1 {
                            Rectangle().fill(Theme.line).frame(height: 0.5)
                        }
                    }
                }
            }
        }
    }

    private func staySection(_ exp: RetreatExperience) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 12) {
                sectionEyebrow("Your Stay")
                Text(exp.stay)
                    .font(Theme.body(15))
                    .foregroundStyle(Theme.inkSoft)
                    .lineSpacing(5)
                    .fixedSize(horizontal: false, vertical: true)
            }
            VStack(alignment: .leading, spacing: 14) {
                Text("WHAT'S INCLUDED")
                    .font(Theme.eyebrow(10))
                    .tracking(2)
                    .foregroundStyle(Theme.inkSoft)
                VStack(alignment: .leading, spacing: 11) {
                    ForEach(exp.inclusions, id: \.self) { item in
                        HStack(alignment: .top, spacing: 12) {
                            Image(systemName: "checkmark")
                                .font(.system(size: 11, weight: .light))
                                .foregroundStyle(Theme.inkSoft)
                                .padding(.top, 2)
                            Text(item)
                                .font(Theme.body(14))
                                .foregroundStyle(Theme.ink)
                                .fixedSize(horizontal: false, vertical: true)
                            Spacer(minLength: 0)
                        }
                    }
                }
            }
            .padding(.top, 22)
            .frame(maxWidth: .infinity, alignment: .leading)
            .overlay(alignment: .top) {
                Rectangle().fill(Theme.line).frame(height: 0.5)
            }

            if let note = exp.inclusionsNote {
                Text(note)
                    .font(Theme.body(11))
                    .foregroundStyle(Theme.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: Basic story (retreats without rich content)

    private var basicStory: some View {
        VStack(alignment: .leading, spacing: Theme.sectionGap) {
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
                            .foregroundStyle(Theme.muted)
                        Text(tag)
                            .font(Theme.headline(24, weight: .light))
                            .kerning(-0.4)
                            .foregroundStyle(Theme.ink)
                        Spacer()
                    }
                    .padding(.vertical, 16)
                    .overlay(alignment: .bottom) {
                        if idx < retreat.tags.count - 1 {
                            Rectangle().fill(Theme.line).frame(height: 0.5)
                        }
                    }
                }
            }

            // Details grid
            VStack(alignment: .leading, spacing: 14) {
                sectionEyebrow("Details")
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 20), GridItem(.flexible())], spacing: 4) {
                    detailCell(label: "Dates", value: detailWhen)
                    detailCell(label: "Place", value: retreat.country)
                    detailCell(label: "Guests", value: "\(retreat.maxGuests) at most")
                    detailCell(label: "Contribution", value: retreat.priceFormatted)
                }
            }

            closingCTA
        }
        .padding(.horizontal, Theme.gutter)
        .padding(.top, 48)
    }

    // MARK: Shared closing CTA

    private var closingCTA: some View {
        VStack(spacing: 16) {
            Text("\(retreat.maxGuests) places. One table.")
                .font(Theme.headline(22, weight: .light))
                .kerning(-0.3)
                .foregroundStyle(Theme.ink)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
            reserveButton
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 6)
        .padding(.bottom, 140)
    }

    private var detailWhen: String {
        let year = Calendar.current.component(.year, from: retreat.startDate)
        return "\(whenLabel), \(year)"
    }

    /// Opens a section as `SectionLabel` does everywhere else: a hairline
    /// across the measure, then a small tracked caps label.
    private func sectionEyebrow(_ text: String) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Rectangle()
                .fill(Theme.line)
                .frame(height: 0.5)
            Text(text.uppercased())
                .font(Theme.eyebrow(10))
                .tracking(3)
                .foregroundStyle(Theme.ink)
        }
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
        .padding(.vertical, 14)
        .overlay(alignment: .top) {
            Rectangle().fill(Theme.line).frame(height: 0.5)
        }
    }

    // MARK: - Pinned reserve bar

    /// Shorter than `reserveTitle` — the bar is tight on width.
    private var barActionTitle: String {
        guard AppFeatures.paymentsEnabled else { return "Enquire" }
        return vm.isReserved ? "Your experience" : "Reserve"
    }

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
                routeReserve()
            } label: {
                Text(barActionTitle)
                    .font(Theme.body(13, weight: .medium))
                    .foregroundStyle(.black)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 12)
                    .background(Rectangle().fill(Theme.ink))
            }
            .buttonStyle(SoulPressableStyle(hapticOnPress: false))
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
        .soulGlassCard(stroke: Theme.glassBorderHigh)
        .padding(.horizontal, Theme.gutter)
        .padding(.bottom, 24)
    }

    private var topBar: some View {
        HStack {
            Button {
                Haptics.tap()
                dismiss()
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "arrow.left").font(.system(size: 15, weight: .light))
                    Text("Back")
                        .font(Theme.body(13))
                }
                .foregroundStyle(Theme.ink)
                .onPhoto()
                // The drawn label is ~20pt tall and only its glyphs answered
                // (rendering gotcha #5); give the thumb a full 44pt target.
                .frame(minWidth: 44, minHeight: 44, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            Spacer()
            // A bare glyph, drawn as `GlyphButton` draws one (a ShareLink
            // can't be a GlyphButton): a 44pt square answers, not the glyph.
            ShareLink(item: shareMessage) {
                Image(systemName: "square.and.arrow.up")
                    .font(.system(size: 17, weight: .light))
                    .foregroundStyle(Theme.ink)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
                    .shadow(color: .black.opacity(0.45), radius: 6)
            }
            .buttonStyle(.soulPressable)
        }
    }

    /// Ground for the top bar once the story scrolls under it. The bar floats
    /// over the scroller, so brochure type used to slide straight through the
    /// plain "‹ Back" and read as one jumble with it. Invisible at rest, where
    /// the cover photo should stay open, and fading in as the cover title rises
    /// toward the bar — by the time anything reaches it, it sinks into the
    /// canvas colour first. Runs from the top edge of the screen through the
    /// bar, then fades out below it.
    private var topBarScrim: some View {
        LinearGradient(
            stops: [
                .init(color: Theme.bg.opacity(0.94), location: 0),
                .init(color: Theme.bg.opacity(0.82), location: 0.7),
                .init(color: Theme.bg.opacity(0), location: 1),
            ],
            startPoint: .top, endPoint: .bottom
        )
        .padding(.bottom, -44)
        .ignoresSafeArea(edges: .top)
        .opacity(min(1, max(0, Double(scrollY) - 80) / 180))
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private var shareMessage: String {
        "\(retreat.name), \(retreat.country) — \(detailWhen). \(retreat.blurb)"
    }
}

#Preview {
    let app = AppState()
    return NavigationStack {
        RetreatDetailView(retreat: Retreat.mock[0])
            .toolbar(.hidden, for: .navigationBar)
    }
    .environment(app.auth)
    .environment(app.settings)
    .preferredColorScheme(.dark)
}
