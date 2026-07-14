import SwiftUI

struct DailyRecapView: View {
    let targetDate: Date?

    @AppStorage("useMockData") private var useSampleData = RecapLaunchEnvironment.prefersSampleData
    @StateObject private var viewModel: DailyRecapViewModel
    @State private var reminderResult: ReminderResult?

    private var loadRequest: LoadRequest {
        LoadRequest(targetDate: targetDate, useSampleData: useSampleData)
    }

    init(targetDate: Date? = nil) {
        self.targetDate = targetDate
        _viewModel = StateObject(wrappedValue: DailyRecapViewModel())
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color(.systemGroupedBackground)
                    .ignoresSafeArea()
                stateContent
            }
            .navigationTitle("Health Recap")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { recapToolbar }
        }
        .tint(RecapPalette.accent)
        .task(id: loadRequest) {
            await viewModel.load(
                targetDate: loadRequest.targetDate,
                useSampleData: loadRequest.useSampleData
            )
        }
        .alert(item: $reminderResult) { result in
            Alert(
                title: Text(result.title),
                message: Text(result.message),
                dismissButton: .default(Text("Done"))
            )
        }
    }

    @ViewBuilder
    private var stateContent: some View {
        switch viewModel.state {
        case .idle, .loading:
            RecapLoadingView()
        case .error(let message):
            RecapErrorView(
                message: message,
                retry: retry,
                showSampleData: showSampleData
            )
        case .loaded(let recap, let source):
            DailyRecapContentView(recap: recap, source: source)
                .refreshable { await retryAsync() }
        }
    }

    @ToolbarContentBuilder
    private var recapToolbar: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            Menu {
                Button(
                    useSampleData ? "Use Health data" : "Use sample data",
                    systemImage: useSampleData ? "heart.text.square" : "sparkles",
                    action: toggleDataSource
                )
                Button(
                    "Enable morning reminders",
                    systemImage: "bell.badge",
                    action: enableReminders
                )
                .disabled(!viewModel.isShowingHealthData)
            } label: {
                Image(systemName: "ellipsis.circle")
                    .accessibilityLabel("Recap options")
            }
        }
    }

    private func toggleDataSource() {
        useSampleData.toggle()
    }

    private func showSampleData() {
        useSampleData = true
    }

    private func retry() {
        Task { await retryAsync() }
    }

    private func retryAsync() async {
        await viewModel.load(targetDate: targetDate, useSampleData: useSampleData)
    }

    private func enableReminders() {
        Task {
            let granted = await viewModel.enableMorningReminders()
            reminderResult = granted ? .enabled : .denied
        }
    }
}

struct DailyRecapContentView: View {
    let recap: DailyRecap
    let source: RecapDataSource

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                RecapSourceBanner(source: source)
                RecapHeroCard(recap: recap)
                RecapInsightCard(insight: recap.insight)
                SleepDetailsCard(sleep: recap.sleep)
                MovementSection(movement: recap.movement)
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 32)
        }
        .scrollIndicators(.hidden)
        .accessibilityIdentifier("daily-recap-scroll")
    }
}

private struct RecapLoadingView: View {
    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                RecapHeroCard(recap: .mock())
                RecapInsightCard(insight: DailyRecap.mock().insight)
                SleepDetailsCard(sleep: DailyRecap.mock().sleep)
            }
            .padding(16)
            .redacted(reason: .placeholder)
            .allowsHitTesting(false)
        }
        .accessibilityLabel("Loading health recap")
    }
}

private struct RecapErrorView: View {
    let message: String
    let retry: () -> Void
    let showSampleData: () -> Void

    var body: some View {
        ContentUnavailableView {
            Label("Recap unavailable", systemImage: "heart.slash")
        } description: {
            Text(message)
        } actions: {
            Button("Try again", action: retry)
                .buttonStyle(.borderedProminent)
            Button("Preview sample data", action: showSampleData)
                .buttonStyle(.bordered)
        }
        .padding()
    }
}

private struct LoadRequest: Equatable {
    let targetDate: Date?
    let useSampleData: Bool
}

private enum RecapLaunchEnvironment {
    static var prefersSampleData: Bool {
#if targetEnvironment(simulator)
        true
#else
        ProcessInfo.processInfo.arguments.contains("--sample-data")
#endif
    }
}

private enum ReminderResult: Identifiable {
    case enabled
    case denied

    var id: Self { self }

    var title: String {
        switch self {
        case .enabled: "Reminders enabled"
        case .denied: "Notifications are off"
        }
    }

    var message: String {
        switch self {
        case .enabled:
            "When the app sees a newly finished sleep session, it can prepare a recap reminder."
        case .denied:
            "You can allow notifications later in Settings."
        }
    }
}

#Preview("Sample recap") {
    DailyRecapContentView(
        recap: .mock(),
        source: .sample(reason: "Previewing a deterministic demo day")
    )
}

#Preview("Accessibility text") {
    DailyRecapContentView(
        recap: .mock(),
        source: .sample(reason: "HealthKit is unavailable in Simulator")
    )
    .environment(\.dynamicTypeSize, .accessibility2)
}
