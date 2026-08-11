import ActivityKit
import Foundation

struct TodayActivityTask: Codable, Hashable {
    let title: String
    let symbolName: String
    let isComplete: Bool
}

struct TodaySessionAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        let updatedAt: Date
        let phase: TodayWidgetPhase
        let headline: String
        let detail: String
        let symbolName: String
        let tasks: [TodayActivityTask]
        let completedMiles: Double
        let plannedMiles: Double
        /// Set only mid-lift. The card renders a `.timer` text from this so the
        /// rest clock keeps moving on a locked phone, where nothing can push it
        /// a new value. Optional so a card started by an older build still
        /// decodes into this shape.
        var restAnchor: Date? = nil
        var nextExercise: String? = nil
        var completedSets: Int = 0
        var plannedSets: Int = 0
    }

}
