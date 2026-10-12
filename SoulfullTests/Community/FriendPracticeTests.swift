//
//  FriendPracticeTests.swift
//  SoulfullTests
//
//  A friend's practice in numbers (0034): their streak worked out of their
//  latest run against today, by the rule the You tab uses for its own; the
//  line under their name; the rows `friend_practice_stats()` answers with;
//  and when the Community view model reads them, what it says of a friend the
//  answer leaves out, and what a block or the next person on the phone leaves
//  behind. What the server lets through (accepted friends who share, blocks)
//  is verified live per 0034's header; the screens are
//  SoulfullUITests/CommunityTests.
//

import Foundation
import Testing
@preconcurrency import Supabase
@testable import SoulfullGatherings

@MainActor
@Suite("Friend practice")
struct FriendPracticeTests {

    typealias Fake = CommunityLoadTests.FakeCommunity

    let madrid = Calendar.gregorian(in: "Europe/Madrid")
    /// A Monday.
    var monday: Date { madrid.at(2026, 10, 12, 12) }

    func day(_ year: Int, _ month: Int, _ day: Int) -> CalendarDay {
        CalendarDay(year: year, month: month, day: day)
    }

    func practice(_ run: ClosedRange<CalendarDay>?, longest: Int = 0, classes: Int = 0,
                  minutes: Int = 0, of memberID: UUID = UUID()) -> FriendPractice {
        FriendPractice(memberID: memberID, latestRun: run, longestRun: longest,
                       classesTaken: classes, minutesPracticed: minutes)
    }

    func member(_ name: String) -> CommunityMember {
        CommunityMember(id: UUID(), displayName: name, avatarUrl: nil)
    }

    // MARK: - The streak

    @Test func aRunThatReachesTodayIsAStreakKeptToday() {
        let alma = practice(day(2026, 10, 1)...day(2026, 10, 12), longest: 5)

        let streak = alma.streak(calendar: madrid, now: monday)

        #expect(streak.current == 12)
        #expect(streak.keptToday)
        #expect(streak.best == 12, "The best is never shorter than the run they're on")
    }

    @Test func aRunThatEndedYesterdayIsStillAliveButNotYetKept() {
        let theo = practice(day(2026, 10, 9)...day(2026, 10, 11), longest: 9)

        let streak = theo.streak(calendar: madrid, now: monday)

        #expect(streak.current == 3)
        #expect(!streak.keptToday)
        #expect(streak.best == 9)
    }

    @Test func aRunThatEndedBeforeYesterdayIsNoStreakButKeepsTheBest() {
        let nia = practice(day(2026, 10, 1)...day(2026, 10, 10), longest: 14)

        let streak = nia.streak(calendar: madrid, now: monday)

        #expect(streak.current == 0)
        #expect(!streak.keptToday)
        #expect(streak.best == 14)
    }

    @Test func theStreakMovesAtMidnightWithoutANewRead() {
        let alma = practice(day(2026, 10, 10)...day(2026, 10, 12), longest: 3)

        let justAfterMidnight = alma.streak(calendar: madrid, now: madrid.at(2026, 10, 13, 0, 5))
        let theDayAfter = alma.streak(calendar: madrid, now: madrid.at(2026, 10, 14, 9))

        #expect(justAfterMidnight.current == 3 && !justAfterMidnight.keptToday)
        #expect(theDayAfter.current == 0)
    }

    @Test func aFriendWhoHasNeverFinishedAPracticeHasNoStreak() {
        let mateo = practice(nil)

        let streak = mateo.streak(calendar: madrid, now: monday)

        #expect(streak == PracticeStreak(current: 0, best: 0, keptToday: false))
    }

    /// Madrid's 25 October 2026 is 25 hours long; São Paulo's 4 November 2018
    /// had no midnight.
    @Test(arguments: [
        ("Europe/Madrid", 2026, 10, 24),
        ("America/Sao_Paulo", 2018, 11, 3),
    ])
    func aRunAcrossAClockChangeCountsEveryDay(zone: String, year: Int, month: Int, first: Int) {
        let calendar = Calendar.gregorian(in: zone)
        let run = day(year, month, first)...day(year, month, first + 2)

        let streak = practice(run).streak(calendar: calendar, now: calendar.at(year, month, first + 2, 18))

        #expect(streak.current == 3)
        #expect(streak.keptToday)
    }

    // MARK: - Said in words

    @Test func theLastDayTheyPracticedIsSaidAsTheStreakCaptionSaysIt() throws {
        func label(_ last: CalendarDay) -> String? {
            practice(day(2026, 9, 1)...last).lastPracticedLabel(calendar: madrid, now: monday)
        }

        #expect(label(day(2026, 10, 12)) == "Practiced today")
        #expect(label(day(2026, 10, 11)) == "Last practiced yesterday")
        #expect(label(day(2026, 10, 9)) == "Last practiced Friday")
        // "12 Sep" or "Sep 12", as the phone's region writes it.
        let older = try #require(label(day(2026, 9, 12)))
        #expect(older.hasPrefix("Last practiced ") && older.contains("12") && older.contains("Sep"))
        #expect(practice(nil).lastPracticedLabel(calendar: madrid, now: monday) == nil)
    }

    /// Runs in October 2026, read on Monday the 12th.
    @Test(arguments: [
        (1, 12, 48, "12-day streak · 48 classes"),
        (10, 11, 1, "2-day streak · 1 class"),
        (12, 12, 0, "1-day streak"),
        (1, 5, 3, "3 classes"),
        (1, 5, 0, "No streak right now"),
    ])
    func theLineUnderAFriendsNameSaysTheirStreakAndClasses(first: Int, last: Int,
                                                           classes: Int, expected: String) {
        let run = day(2026, 10, first)...day(2026, 10, last)

        let summary = practice(run, classes: classes).summary(calendar: madrid, now: monday)

        #expect(summary == expected)
    }

    @Test func aFriendWithNothingFinishedIsSaidSo() {
        #expect(practice(nil).summary(calendar: madrid, now: monday) == "No practices finished yet")
    }

    // MARK: - The server's rows

    @Test(arguments: [
        ("2026-10-12", CalendarDay(year: 2026, month: 10, day: 12)),
        ("2026-13-01", nil),
        ("2026-10", nil),
        ("yesterday", nil),
        ("", nil),
    ] as [(String, CalendarDay?)])
    func aDayIsReadOnlyAsTheDateSQLWrites(text: String, expected: CalendarDay?) {
        #expect(CalendarDay(text) == expected)
    }

    @Test func theFunctionsRowsBecomeEachFriendsNumbers() throws {
        let alma = UUID(), theo = UUID(), nia = UUID()
        let json = """
        [
          {"friend_id": "\(alma)", "run_first_day": "2026-10-01", "run_last_day": "2026-10-12",
           "best_streak": 21, "classes_taken": 48, "minutes_practiced": 612},
          {"friend_id": "\(theo)", "run_first_day": null, "run_last_day": null,
           "best_streak": 0, "classes_taken": 0, "minutes_practiced": 0},
          {"friend_id": "\(nia)", "run_first_day": "2026-10-12", "run_last_day": "2026-10-01",
           "best_streak": -1, "classes_taken": 2, "minutes_practiced": 30}
        ]
        """

        let rows = try SupabaseService.decodeFriendPractice(Data(json.utf8))

        #expect(rows.count == 3)
        #expect(rows[0] == FriendPractice(memberID: alma, latestRun: day(2026, 10, 1)...day(2026, 10, 12),
                                          longestRun: 21, classesTaken: 48, minutesPracticed: 612))
        #expect(rows[1].memberID == theo && rows[1].latestRun == nil)
        #expect(rows[2].latestRun == nil, "A run that ends before it starts is no run")
        #expect(rows[2].longestRun == 0)
    }

    // MARK: - Reading them

    @Test func theNumbersWaitForTheFriendsTheyAreReadFor() async {
        let fake = Fake()
        let alma = member("Alma G.")
        fake.befriend(alma)
        fake.friendPractice = [practice(nil, classes: 4, of: alma.id)]
        let vm = fake.viewModel()

        await vm.loadFriendPractice()

        #expect(fake.friendPracticeReads == 0)
        #expect(vm.practice(of: alma.id) == .loading)

        await vm.load(isMember: true)
        await vm.loadFriendPractice()

        #expect(fake.friendPracticeReads == 1)
        #expect(vm.practice(of: alma.id) == .shared(practice(nil, classes: 4, of: alma.id)))
    }

    @Test func aFriendTheAnswerLeftOutKeepsTheirPracticePrivate() async {
        let fake = Fake()
        let alma = member("Alma G."), theo = member("Theo R.")
        fake.befriend(alma)
        fake.befriend(theo)
        fake.friendPractice = [practice(nil, of: alma.id)]
        let vm = fake.viewModel()
        await vm.load(isMember: true)

        await vm.loadFriendPractice()

        #expect(vm.practice(of: theo.id) == .keptPrivate)
    }

    @Test func aFriendMadeSinceTheReadIsAskedAboutBeforeAnythingIsSaid() async {
        let fake = Fake()
        let alma = member("Alma G."), nia = member("Nia")
        fake.befriend(alma)
        let vm = fake.viewModel()
        await vm.load(isMember: true)
        await vm.loadFriendPractice()
        fake.befriend(nia)
        fake.friendPractice = [practice(nil, classes: 2, of: nia.id)]
        await vm.loadFriendships(force: true)

        #expect(vm.practice(of: nia.id) == .loading, "Not asked about yet, so not private")

        await vm.loadFriendPractice()

        #expect(fake.friendPracticeReads == 2, "A new friend makes the numbers out of date inside the minute")
        #expect(vm.practice(of: nia.id) == .shared(practice(nil, classes: 2, of: nia.id)))
    }

    /// The Friends screen asks on appear and again as its friends arrive.
    @Test func theSameQuestionAskedWhileItIsOutIsOneRead() async {
        let fake = Fake()
        fake.befriend(member("Alma G."))
        let vm = fake.viewModel()
        await vm.load(isMember: true)
        fake.duringFriendPracticeRead = {
            fake.duringFriendPracticeRead = nil
            await vm.loadFriendPractice()
        }

        await vm.loadFriendPractice()

        #expect(fake.friendPracticeReads == 1)
    }

    @Test func theNumbersStayCurrentForAMinute() async {
        let fake = Fake()
        fake.befriend(member("Alma G."))
        let vm = fake.viewModel()
        await vm.load(isMember: true)
        await vm.loadFriendPractice()
        fake.wait(30)

        await vm.loadFriendPractice()

        #expect(fake.friendPracticeReads == 1)

        fake.wait(31)
        await vm.loadFriendPractice()

        #expect(fake.friendPracticeReads == 2)
    }

    @Test func aFailedReadSaysWhyAndIsRetriedAtOnce() async {
        let fake = Fake()
        let alma = member("Alma G.")
        fake.befriend(alma)
        fake.friendPractice = [practice(nil, classes: 4, of: alma.id)]
        fake.friendPracticeError = URLError(.notConnectedToInternet)
        let vm = fake.viewModel()
        await vm.load(isMember: true)
        await vm.loadFriendPractice()

        #expect(vm.practice(of: alma.id) == .unavailable(.offline))

        fake.friendPracticeError = nil
        await vm.loadFriendPractice()

        #expect(fake.friendPracticeReads == 2)
        #expect(vm.practice(of: alma.id) == .shared(practice(nil, classes: 4, of: alma.id)))
    }

    @Test func aFailedReReadKeepsTheNumbersOnScreen() async {
        let fake = Fake()
        let alma = member("Alma G."), theo = member("Theo R.")
        fake.befriend(alma)
        fake.befriend(theo)
        fake.friendPractice = [practice(nil, classes: 4, of: alma.id)]
        let vm = fake.viewModel()
        await vm.load(isMember: true)
        await vm.loadFriendPractice()
        fake.friendPracticeError = URLError(.timedOut)
        fake.wait(61)

        await vm.loadFriendPractice()

        #expect(vm.practice(of: alma.id) == .shared(practice(nil, classes: 4, of: alma.id)))
        #expect(vm.practice(of: theo.id) == .keptPrivate)
    }

    // MARK: - Block, and the next person

    @Test func blockingAFriendTakesTheirNumbersAwayAndARefusalPutsThemBack() async {
        let fake = Fake()
        let alma = member("Alma G.")
        fake.befriend(alma)
        fake.friendPractice = [practice(nil, classes: 4, of: alma.id)]
        let vm = fake.viewModel()
        await vm.load(isMember: true)
        await vm.loadFriendPractice()
        fake.writeError = URLError(.notConnectedToInternet)

        let refused = await vm.block(alma)

        #expect(!refused)
        #expect(vm.friendPractice[alma.id] != nil)

        fake.writeError = nil
        let held = await vm.block(alma)

        #expect(held)
        #expect(vm.friendPractice[alma.id] == nil)
    }

    @Test func aReadThatAnswersAfterABlockDoesNotBringThemBack() async {
        let fake = Fake()
        let alma = member("Alma G.")
        fake.befriend(alma)
        fake.friendPractice = [practice(nil, classes: 4, of: alma.id)]
        let vm = fake.viewModel()
        await vm.load(isMember: true)
        fake.duringFriendPracticeRead = {
            fake.duringFriendPracticeRead = nil
            await vm.block(alma)
        }

        await vm.loadFriendPractice()

        #expect(vm.friendPractice[alma.id] == nil)
    }

    @Test func aReadForThePreviousPersonNeverLandsOnTheNext() async {
        let fake = Fake()
        let alma = member("Alma G.")
        fake.befriend(alma)
        fake.friendPractice = [practice(nil, classes: 4, of: alma.id)]
        let vm = fake.viewModel()
        await vm.load(isMember: true)
        fake.duringFriendPracticeRead = {
            fake.duringFriendPracticeRead = nil
            // They sign out while it's out; a guest takes their place.
            fake.me = UUID()
            fake.friendships = []
            await vm.load(isMember: false)
        }

        await vm.loadFriendPractice()

        #expect(vm.friendPractice.isEmpty)
        #expect(vm.practice(of: alma.id) == .loading)
    }
}
