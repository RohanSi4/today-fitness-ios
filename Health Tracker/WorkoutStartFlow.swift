import SwiftUI

struct WorkoutStartFlow: View {
    @ObservedObject var store: TodayStore
    @ObservedObject var catalog: ExerciseCatalog
    let suggestedKind: WorkoutKind?

    var body: some View {
        if let active = store.activeWorkout {
            WorkoutLogView(store: store, catalog: catalog, kind: active.kind)
        } else {
            WorkoutTypePicker(
                store: store,
                catalog: catalog,
                suggestedKind: suggestedKind
            )
        }
    }
}

private struct WorkoutTypePicker: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var store: TodayStore
    @ObservedObject var catalog: ExerciseCatalog
    let suggestedKind: WorkoutKind?

    private var choices: [WorkoutKind] {
        guard let suggestedKind else { return WorkoutKind.allCases }
        return [suggestedKind] + WorkoutKind.allCases.filter { $0 != suggestedKind }
    }

    private let columns = [
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12),
    ]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    VStack(alignment: .leading, spacing: 5) {
                        Text("What are you training?")
                            .font(.title2.weight(.bold))
                        Text("Pick a starting point. You can add, remove, or swap anything once you start.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }

                    LazyVGrid(columns: columns, spacing: 12) {
                        ForEach(choices) { kind in
                            Button {
                                store.beginWorkout(kind: kind, catalog: catalog)
                            } label: {
                                workoutChoice(kind)
                            }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("start-\(kind.rawValue)-workout")
                        }
                    }
                }
                .padding(16)
                .padding(.bottom, 24)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Start workout")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
        }
    }

    private func workoutChoice(_ kind: WorkoutKind) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                Image(systemName: kind.symbol)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(TodayPalette.accent)
                    .frame(width: 38, height: 38)
                    .background(TodayPalette.accent.opacity(0.1), in: RoundedRectangle(cornerRadius: 11))

                Spacer(minLength: 4)

                if kind == suggestedKind {
                    Text("TODAY")
                        .font(.system(size: 8, weight: .bold, design: .rounded))
                        .tracking(0.8)
                        .foregroundStyle(TodayPalette.accent)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 4)
                        .background(TodayPalette.accent.opacity(0.1), in: Capsule())
                }
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(kind.title)
                    .font(.headline)
                    .foregroundStyle(.primary)
                Text(kind.subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 112, alignment: .topLeading)
        .padding(14)
        .todayCard()
        .overlay {
            if kind == suggestedKind {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .stroke(TodayPalette.accent.opacity(0.45), lineWidth: 1.5)
            }
        }
    }
}

#Preview {
    WorkoutStartFlow(
        store: TodayStore(storageURL: FileManager.default.temporaryDirectory.appendingPathComponent("workout-picker-preview.json")),
        catalog: ExerciseCatalog(),
        suggestedKind: .lower
    )
}
