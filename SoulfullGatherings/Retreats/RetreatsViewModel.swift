//
//  RetreatsViewModel.swift
//  Soulfull Gatherings
//
//  State for the Foodle-style retreat stack: which retreat is "active"
//  (centered + bright), plus the snap-scroll behavior.
//

import SwiftUI

@Observable @MainActor
final class RetreatsViewModel {

    let retreats: [Retreat] = Retreat.mock
    var activeIndex: Int = 0

    var active: Retreat { retreats[activeIndex] }

    func setActive(_ idx: Int) {
        guard idx != activeIndex, retreats.indices.contains(idx) else { return }
        Haptics.select()
        activeIndex = idx
    }
}
