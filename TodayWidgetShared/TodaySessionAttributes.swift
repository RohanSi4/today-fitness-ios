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
    }

}
