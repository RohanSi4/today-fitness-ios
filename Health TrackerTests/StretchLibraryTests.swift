import Foundation
import Testing
import UIKit
@testable import Health_Tracker

struct StretchLibraryTests {
    @Test func routineHasTheExpectedShape() {
        #expect(StretchLibrary.dynamic.count == 8)
        #expect(StretchLibrary.cooldown.count == 10)
        #expect(StretchLibrary.all.count == 18)
    }

    @Test func everyStretchIsWellFormed() {
        for stretch in StretchLibrary.all {
            #expect(!stretch.name.isEmpty)
            #expect(!stretch.cue.isEmpty)
            #expect(!stretch.targets.isEmpty)
        }
    }

    @Test func stretchIDsAreUnique() {
        let ids = StretchLibrary.all.map(\.id)
        #expect(Set(ids).count == ids.count)
    }

    @Test func eachStretchSitsInItsOwnBucket() {
        #expect(StretchLibrary.dynamic.allSatisfy { $0.phase == .dynamic })
        #expect(StretchLibrary.cooldown.allSatisfy { $0.phase == .cooldown })
        #expect(StretchLibrary.stretches(for: .dynamic) == StretchLibrary.dynamic)
        #expect(StretchLibrary.stretches(for: .cooldown) == StretchLibrary.cooldown)
    }

    @Test func staticStretchesAreAllHolds() {
        #expect(StretchLibrary.cooldown.allSatisfy { $0.style == .hold })
    }

    @MainActor
    @Test func everySymbolResolvesToASystemImage() {
        for stretch in StretchLibrary.all {
            #expect(UIImage(systemName: stretch.symbol) != nil, "Missing SF Symbol: \(stretch.symbol)")
        }
        for phase in StretchPhase.allCases {
            #expect(UIImage(systemName: phase.symbol) != nil, "Missing phase symbol: \(phase.symbol)")
        }
        for style in StretchStyle.allCases {
            #expect(UIImage(systemName: style.symbol) != nil, "Missing style symbol: \(style.symbol)")
        }
    }
}
