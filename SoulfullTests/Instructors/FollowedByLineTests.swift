//
//  FollowedByLineTests.swift
//  SoulfullTests
//
//  "Followed by Alma G., Theo R. and 1,203 others" — the sentence under a
//  guide's numbers. At most two names, "you" first when the viewer follows
//  (the server never puts the viewer among the faces, so without it they'd
//  vanish into "others"), and a remainder that is counted, never negative.
//

import Foundation
import Testing
@testable import SoulfullGatherings

@Suite("Followed by line")
struct FollowedByLineTests {

    private static let alma = CommunityMember(id: UUID(), displayName: "Alma G.", avatarUrl: nil)
    private static let theo = CommunityMember(id: UUID(), displayName: "Theo R.", avatarUrl: nil)
    private static let nia  = CommunityMember(id: UUID(), displayName: "Nia K.", avatarUrl: nil)

    private func line(followers: Int, faces: [CommunityMember], me: Bool = false) -> String? {
        InstructorSocial(followers: followers, following: 0, followedByMe: me, isMe: false, faces: faces)
            .followedByLine(locale: Locale(identifier: "en_US"))
    }

    @Test func nobodyWhoCanBeNamedMeansNoLine() {
        // Five followers, none of them sharing their practice.
        #expect(line(followers: 5, faces: []) == nil)
    }

    @Test func aSingleFollowerIsNamedAlone() {
        #expect(line(followers: 1, faces: [Self.alma]) == "Followed by Alma G.")
    }

    @Test func twoFollowersAreNamedTogether() {
        #expect(line(followers: 2, faces: [Self.alma, Self.theo]) == "Followed by Alma G. and Theo R.")
    }

    @Test(arguments: [
        (3,     "Followed by Alma G., Theo R. and 1 other"),
        (4,     "Followed by Alma G., Theo R. and 2 others"),
        (1_205, "Followed by Alma G., Theo R. and 1,203 others"),
    ])
    func onlyTwoAreNamedAndTheRestAreCounted(followers: Int, expected: String) {
        #expect(line(followers: followers, faces: [Self.alma, Self.theo, Self.nia]) == expected)
    }

    @Test func youComeFirstWhenYouFollowToo() {
        let text = line(followers: 213, faces: [Self.theo, Self.nia], me: true)

        #expect(text == "Followed by you, Theo R. and 211 others")
    }

    @Test func followingAloneReadsAsYou() {
        #expect(line(followers: 1, faces: [], me: true) == "Followed by you")
    }

    @Test func youAndOneOtherAreNamedTogether() {
        #expect(line(followers: 2, faces: [Self.alma], me: true) == "Followed by you and Alma G.")
    }

    /// The count and the faces arrive in one read, but an optimistic unfollow
    /// moves only the count — the remainder must clamp, not read "-1 others".
    @Test func aCountBehindTheFacesNeverGoesNegative() {
        #expect(line(followers: 0, faces: [Self.alma, Self.theo]) == "Followed by Alma G. and Theo R.")
    }
}
