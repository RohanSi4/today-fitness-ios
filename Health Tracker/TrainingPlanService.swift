import Combine
import Foundation

@MainActor
final class TrainingPlanService: ObservableObject {
    static let shared = TrainingPlanService()

    @Published private(set) var plan: TrainingPlan?
    @Published private(set) var isLoading = false
    @Published private(set) var lastUpdated: Date?
    @Published private(set) var errorMessage: String?

    private let endpoint = URL(string: "https://rohansingh04.com/api/running/ingest")!
    private let cacheURL: URL
    private let session: URLSession
    private let maximumResponseBytes = 2_000_000

    init(session: URLSession = .shared, cacheURL: URL? = nil) {
        self.session = session
        let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
        self.cacheURL = cacheURL ?? base.appendingPathComponent("today-plan.json")
        loadCache()
    }

    var today: TrainingPlanDay? {
        guard let plan else { return nil }
        let key = Self.dayFormatter.string(from: Date())
        return plan.days.first { $0.date == key }
    }

    func refresh() async {
        if isLoading { return }
        isLoading = true
        defer { isLoading = false }

        do {
            var request = URLRequest(url: endpoint)
            request.cachePolicy = .reloadIgnoringLocalCacheData
            request.timeoutInterval = 15
            request.setValue("no-cache", forHTTPHeaderField: "Cache-Control")
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                throw URLError(.badServerResponse)
            }
            guard data.count <= maximumResponseBytes else {
                throw URLError(.dataLengthExceedsMaximum)
            }
            let envelope = try Self.decoder.decode(DashboardEnvelope.self, from: data)
            guard let incoming = envelope.trainingPlan, Self.isPlausible(incoming) else {
                throw URLError(.cannotParseResponse)
            }
            plan = incoming
            lastUpdated = envelope.generatedAt ?? Date()
            errorMessage = nil
            try? data.write(to: cacheURL, options: .atomic)
        } catch {
            errorMessage = "Could not refresh the plan. Showing the last saved version."
        }
    }

    private func loadCache() {
        guard let data = try? Data(contentsOf: cacheURL),
              data.count <= maximumResponseBytes,
              let envelope = try? Self.decoder.decode(DashboardEnvelope.self, from: data),
              let cachedPlan = envelope.trainingPlan,
              Self.isPlausible(cachedPlan) else {
            return
        }
        plan = cachedPlan
        lastUpdated = envelope.generatedAt
    }

    static func isPlausible(_ plan: TrainingPlan) -> Bool {
        let datePattern = /^\d{4}-\d{2}-\d{2}$/
        return plan.weekStart.wholeMatch(of: datePattern) != nil
            && plan.weekEnd.wholeMatch(of: datePattern) != nil
            && plan.weekStart <= plan.weekEnd
            && plan.prescribedMiles >= 0
            && plan.prescribedMiles <= 250
            && (1...14).contains(plan.days.count)
            && plan.days.allSatisfy { day in
                day.date.wholeMatch(of: datePattern) != nil
                    && day.date >= plan.weekStart
                    && day.date <= plan.weekEnd
                    && day.text.count <= 300
                    && day.details.count <= 12
                    && day.details.allSatisfy { $0.count <= 500 }
            }
    }

    private static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { value in
            let container = try value.singleValueContainer()
            let string = try container.decode(String.self)
            let fractional = ISO8601DateFormatter()
            fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let date = fractional.date(from: string) { return date }
            let standard = ISO8601DateFormatter()
            guard let date = standard.date(from: string) else {
                throw DecodingError.dataCorruptedError(
                    in: container,
                    debugDescription: "Invalid ISO-8601 date: \(string)"
                )
            }
            return date
        }
        return decoder
    }()
}
