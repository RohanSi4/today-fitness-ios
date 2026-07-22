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
}

enum TodaySheet: Identifiable {
    case weight
    case startWorkout(WorkoutKind)
    case finishedWorkout(WorkoutSession)

    var id: String {
        switch self {
        case .weight: "weight"
        case .startWorkout: "workout"
        case .finishedWorkout: "summary"
        }
    }
}
