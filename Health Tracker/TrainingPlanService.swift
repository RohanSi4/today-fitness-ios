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
            request.setValue("no-cache", forHTTPHeaderField: "Cache-Control")
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                throw URLError(.badServerResponse)
            }
            let envelope = try Self.decoder.decode(DashboardEnvelope.self, from: data)
            guard let incoming = envelope.trainingPlan else {
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
              let envelope = try? Self.decoder.decode(DashboardEnvelope.self, from: data) else {
            return
        }
        plan = envelope.trainingPlan
        lastUpdated = envelope.generatedAt
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
