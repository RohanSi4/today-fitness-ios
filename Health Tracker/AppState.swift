import Foundation
import Combine

@MainActor
final class AppState: ObservableObject {
    @Published var recapDate: Date?

    func openRecap(for date: Date) {
        recapDate = date
    }
}
