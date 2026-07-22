import Foundation
import Combine

@MainActor
final class AppState: ObservableObject {
    @Published var recapDate: Date?
    @Published var selectedTab: AppTab = .today
    @Published var presentedSheet: TodaySheet?

    func openRecap(for date: Date) {
        recapDate = date
        selectedTab = .insights
    }

    func openWeightLogger() {
        selectedTab = .today
        presentedSheet = .weight
    }

    func openWorkout() {
        selectedTab = .today
        presentedSheet = .workout(suggested: nil)
    }

    func openStretches(_ phase: StretchPhase = .dynamic) {
        selectedTab = .today
        presentedSheet = .stretch(phase: phase)
    }
}

enum TodaySheet: Identifiable {
    case weight
    case workout(suggested: WorkoutKind?)
    case finishedWorkout(WorkoutSession)
    case stretch(phase: StretchPhase)

    var id: String {
        switch self {
        case .weight: "weight"
        case .workout: "workout"
        case .finishedWorkout: "summary"
        case .stretch: "stretch"
        }
    }
}
