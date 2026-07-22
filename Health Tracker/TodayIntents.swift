import AppIntents
import Combine
import Foundation

enum TodayIntentRoute: Equatable {
    case today
    case weight
}

@MainActor
final class TodayIntentRouter: ObservableObject {
    static let shared = TodayIntentRouter()
    @Published var route: TodayIntentRoute?

    func consume() {
        route = nil
    }
}

struct LogMorningWeightIntent: AppIntent {
    static let title: LocalizedStringResource = "Log morning weight"
    static let description = IntentDescription("Open Today directly to the private weight logger.")
    static let openAppWhenRun = true

    func perform() async throws -> some IntentResult {
        await MainActor.run {
            TodayIntentRouter.shared.route = .weight
        }
        return .result()
    }
}

struct OpenTodayIntent: AppIntent {
    static let title: LocalizedStringResource = "Open today’s plan"
    static let description = IntentDescription("Open Today to the current run and lift plan.")
    static let openAppWhenRun = true

    func perform() async throws -> some IntentResult {
        await MainActor.run {
            TodayIntentRouter.shared.route = .today
        }
        return .result()
    }
}

struct TodayShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: LogMorningWeightIntent(),
            phrases: [
                "Log my weight in \(.applicationName)",
                "Record morning weight with \(.applicationName)"
            ],
            shortTitle: "Log weight",
            systemImageName: "scalemass.fill"
        )
        AppShortcut(
            intent: OpenTodayIntent(),
            phrases: ["Show my plan in \(.applicationName)"],
            shortTitle: "Today’s plan",
            systemImageName: "figure.run"
        )
    }
}
