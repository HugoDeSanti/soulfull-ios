//
//  RetreatEnquiryViewModel.swift
//  Soulfull Gatherings
//
//  The half-filled application: every answer as the form holds it (strings,
//  optionals, nothing validated), plus the rules that decide when it is ready
//  to send. `makeEnquiry()` is the gate between the two — it returns a
//  `RetreatEnquiry` only when every required question has a usable answer, so
//  the server never has to think about empty values.
//
//  The one answer that is not editable is the email address: it is the address
//  of the account the applicant is signed in to, shown for confirmation and
//  never typed. It isn't even in the payload — `send-retreat-enquiry` reads it
//  from the JWT, so a modified client cannot put someone else's address on an
//  application. `RetreatDetailView` gates the form on `auth.hasAccount`, which
//  is what guarantees there is an address to show.
//

import Foundation

@Observable @MainActor
final class RetreatEnquiryViewModel {

    // MARK: - Answers

    var firstName = ""
    var lastName = ""
    var dateOfBirth: Date?
    var basedIn = ""
    var phone = ""
    var instagram = ""
    var selectedRetreat: String
    var about = ""
    var decision: RetreatEnquiry.Decision?
    var investment: RetreatEnquiry.Investment?
    var referral = ""

    /// The signed-in account's address. Displayed, never edited, never sent —
    /// see the note at the top of the file.
    let accountEmail: String

    // MARK: - Retreat options

    /// The answers offered for "What retreat are you interested in attending?".
    ///
    /// Seeded with the retreat the guest was looking at — that is already the
    /// right answer, and it means the question is never blank or waiting on a
    /// network round-trip. `loadOptions()` then widens it to the live catalog
    /// so someone can apply for a different gathering without backing out.
    ///
    /// Sourced from `retreats` rather than hardcoded: the website's list is
    /// typed by hand and goes stale, and this app's whole catalog is a
    /// database read for the same reason (see docs/ADDING-A-RETREAT.md).
    private(set) var retreatOptions: [String]

    /// True once the server has accepted the application.
    var didSend = false
    /// A send is in flight — the button says so and can't be tapped twice.
    var isSending = false
    /// Set when a send fails. The answers stay exactly as they were, because
    /// the only useful thing an applicant can do with a failed send is try it
    /// again, and retyping eleven answers first is not that.
    var sendFailure: String?

    private let retreat: Retreat
    /// What the name fields and the date of birth were seeded with, so
    /// `hasContent` can tell a prefilled answer from a given one.
    private let seededName: MemberName
    private let seededDateOfBirth: Date?

    init(retreat: Retreat, name: MemberName = MemberName(), birthDate: BirthDate? = nil,
         accountEmail: String = "") {
        self.retreat = retreat
        self.selectedRetreat = retreat.enquiryLabel
        self.retreatOptions = [retreat.enquiryLabel]
        self.accountEmail = accountEmail.trimmingCharacters(in: .whitespacesAndNewlines)
        // The account's name, or the first name onboarding asked for.
        let seededName = name.limited
        self.seededName = seededName
        self.firstName = seededName.first
        self.lastName = seededName.last
        // The account's date of birth, when it meets the form's own rule:
        // a member of 13 to 17 answers for themselves, and meets the wheel's
        // limit there.
        let seededDateOfBirth = birthDate.map { $0.date() }
            .flatMap { $0 <= Self.latestDateOfBirth ? $0 : nil }
        self.seededDateOfBirth = seededDateOfBirth
        self.dateOfBirth = seededDateOfBirth
    }

    /// Widen the retreat question to the whole upcoming catalog.
    ///
    /// Best-effort on purpose. `fetchRetreats()` is cached for five minutes and
    /// the guest reached this form *through* the catalog, so this is normally a
    /// cache hit; when it isn't — offline, a failed read — the question keeps
    /// the single correct option rather than showing an error for something the
    /// guest did not ask for.
    func loadOptions() async {
        guard retreatOptions.count == 1 else { return }
        do {
            let all = try await SupabaseService.shared.fetchRetreats()
            let labels = all.map(\.enquiryLabel)
            guard !labels.isEmpty else { return }
            // The retreat they came from leads, whether or not the catalog
            // still lists it.
            retreatOptions = labels.contains(selectedRetreat)
                ? [selectedRetreat] + labels.filter { $0 != selectedRetreat }
                : [selectedRetreat] + labels
        } catch {
            Log.data.error("Retreat options for the enquiry form failed to load: \(error.localizedDescription)")
        }
    }

    // MARK: - Validation

    /// The latest date of birth an applicant can have. The form says guests
    /// must be above legal age, so the picker simply cannot reach a younger
    /// date — a rule the guest runs into before they submit reads as a rule,
    /// where the same rule in an error message reads as a rejection.
    static let latestDateOfBirth: Date = {
        Calendar.current.date(byAdding: .year, value: -18, to: Date()) ?? Date()
    }()

    /// A sensible place for the wheel to open: old enough to be plausible, not
    /// so old that most people scroll the wrong way.
    static let defaultDateOfBirth: Date = {
        Calendar.current.date(byAdding: .year, value: -32, to: Date()) ?? latestDateOfBirth
    }()

    /// What the date-of-birth wheel shows and sets. It opens on
    /// `defaultDateOfBirth`, but only turning it answers the question: opening
    /// the wheel used to write that default straight into `dateOfBirth`, so a
    /// glance at it counted as an answer and sent the team a birthday nobody
    /// had chosen.
    var dateOfBirthWheel: Date {
        get { dateOfBirth ?? Self.defaultDateOfBirth }
        set { dateOfBirth = newValue }
    }

    /// Deliberately loose. Numbers arrive with country codes, spaces, dashes
    /// and parentheses from a dozen countries, and a strict pattern would
    /// reject more real numbers than fake ones. Enough digits to be dialable
    /// is the whole test.
    var isPhoneValid: Bool {
        phone.filter(\.isNumber).count >= 7
    }

    /// What is still missing, in the order the form asks for it. Drives both
    /// the submit button and the line underneath it — on a form this long,
    /// "why is the button dim" is a real question and worth answering.
    var missingAnswers: [String] {
        var missing: [String] = []
        if firstName.trimmed.isEmpty || lastName.trimmed.isEmpty { missing.append(RetreatEnquiry.Question.name) }
        if dateOfBirth == nil { missing.append(RetreatEnquiry.Question.dateOfBirth) }
        if basedIn.trimmed.isEmpty { missing.append("Where you're based") }
        if !isPhoneValid { missing.append(RetreatEnquiry.Question.phone) }
        if about.trimmed.isEmpty { missing.append("A little about you") }
        if decision == nil { missing.append("Where you are in your decision") }
        if investment == nil { missing.append("Your usual investment") }
        return missing
    }

    var canSubmit: Bool { missingAnswers.isEmpty }

    /// Whether anything has been typed or chosen **beyond what the form opened
    /// with**. Drives the discard guard — a swipe shouldn't take an application
    /// someone spent five minutes on, and a confirmation on a form nobody has
    /// touched is just friction, which is why the seeded name is compared
    /// rather than merely checked for emptiness.
    var hasContent: Bool {
        firstName.trimmed != seededName.first
            || lastName.trimmed != seededName.last || dateOfBirth != seededDateOfBirth
            || !basedIn.trimmed.isEmpty || !phone.trimmed.isEmpty || !instagram.trimmed.isEmpty
            || !about.trimmed.isEmpty || decision != nil || investment != nil
            || !referral.trimmed.isEmpty
    }

    /// The completed application, or `nil` if it isn't one yet.
    func makeEnquiry() -> RetreatEnquiry? {
        guard canSubmit, let dateOfBirth, let decision, let investment else { return nil }
        return RetreatEnquiry(
            firstName: firstName.trimmed,
            lastName: lastName.trimmed,
            dateOfBirth: dateOfBirth,
            basedIn: basedIn.trimmed,
            phone: phone.trimmed,
            instagram: instagram.trimmed,
            retreat: selectedRetreat,
            about: about.trimmed,
            decision: decision,
            investment: investment,
            referral: referral.trimmed
        )
    }

    // MARK: - Sending

    /// Posts the application to `send-retreat-enquiry`, which emails it to the
    /// team. Returns true once the server has accepted it.
    ///
    /// The app used to hand the answers to the iPhone's Mail composer instead.
    /// That made delivery depend on the device having Mail configured and on
    /// the applicant finding and tapping Send in a screen they could also just
    /// abandon — and it put the application in *their* outbox rather than in
    /// the team's inbox. An authenticated call to our own function sends it the
    /// same way from every device.
    func send() async -> Bool {
        guard !isSending, let enquiry = makeEnquiry() else { return false }
        isSending = true
        sendFailure = nil
        defer { isSending = false }

        do {
            try await SupabaseService.shared.sendRetreatEnquiry(enquiry)
            didSend = true
            return true
        } catch {
            Log.data.error("Retreat application failed to send: \(error.localizedDescription)")
            sendFailure = error.isOffline
                ? "You'll need to be online to send this. Your answers are still here."
                : "That didn't send. Your answers are still here — please try again."
            return false
        }
    }
}

private extension String {
    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
}
