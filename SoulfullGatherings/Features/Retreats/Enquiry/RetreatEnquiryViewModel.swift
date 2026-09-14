//
//  RetreatEnquiryViewModel.swift
//  Soulfull Gatherings
//
//  The half-filled application: every answer as the form holds it (strings,
//  optionals, nothing validated), plus the rules that decide when it is ready
//  to send. `makeEnquiry()` is the gate between the two — it returns a
//  `RetreatEnquiry` only when every required question has a usable answer, so
//  the email builder never has to think about empty values.
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
    var email = ""
    var investment: RetreatEnquiry.Investment?
    var referral = ""

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

    /// True once the application has actually left the device.
    var didSend = false

    private let retreat: Retreat
    /// What the form was seeded with, so `hasContent` can tell a prefilled
    /// field from an answered one.
    private let seededName: String
    private let seededEmail: String

    init(retreat: Retreat, name: String = "", email: String = "") {
        self.retreat = retreat
        self.selectedRetreat = retreat.enquiryLabel
        self.retreatOptions = [retreat.enquiryLabel]
        // Onboarding asked for a name and it is one word; the account, if there
        // is one, knows the address. Neither is worth asking for twice.
        let seededName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let seededEmail = email.trimmingCharacters(in: .whitespacesAndNewlines)
        self.seededName = seededName
        self.seededEmail = seededEmail
        self.firstName = seededName
        self.email = seededEmail
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

    var isEmailValid: Bool {
        let trimmed = email.trimmingCharacters(in: .whitespaces)
        guard let at = trimmed.firstIndex(of: "@"), at != trimmed.startIndex else { return false }
        let domain = trimmed[trimmed.index(after: at)...]
        return domain.contains(".") && !domain.hasSuffix(".") && !domain.contains(" ")
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
        if !isEmailValid { missing.append(RetreatEnquiry.Question.email) }
        if investment == nil { missing.append("Your usual investment") }
        return missing
    }

    var canSubmit: Bool { missingAnswers.isEmpty }

    /// Whether anything has been typed or chosen **beyond what the form opened
    /// with**. Drives the discard guard — a swipe shouldn't take an application
    /// someone spent five minutes on, and a confirmation on a form nobody has
    /// touched is just friction, which is why the seeded name and address are
    /// compared rather than merely checked for emptiness.
    var hasContent: Bool {
        firstName.trimmed != seededName || email.trimmed != seededEmail
            || !lastName.trimmed.isEmpty || dateOfBirth != nil
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
            email: email.trimmed,
            investment: investment,
            referral: referral.trimmed
        )
    }
}

private extension String {
    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
}
