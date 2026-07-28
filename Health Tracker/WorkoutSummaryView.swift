import SwiftUI

struct WorkoutSummaryView: View {
    @Environment(\.dismiss) private var dismiss
    let session: WorkoutSession
    @ObservedObject var store: TodayStore
    @ObservedObject var catalog: ExerciseCatalog

    private var scores: [MuscleGroup: Double] {
        store.muscleScores(for: session, catalog: catalog)
    }

    private var trainedMuscles: [(muscle: MuscleGroup, value: Double)] {
        scores
            .filter { $0.value > 0 }
            .sorted { $0.value > $1.value }
            .map { (muscle: $0.key, value: $0.value) }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    completionHeader

                    HStack(spacing: 10) {
                        StatTile(session.completedExerciseCount, "exercises")
                        StatTile(session.completedSetCount, "sets")
                        StatTile(session.durationLabel ?? "In progress", "time")
                    }

                    MuscleMapView(scores: scores)
                        .padding(18)
                        .frame(maxWidth: .infinity)
                        .todayCard()

                    musclesHit

                    Text("Exercise details and weights stay private. The public site only needs to know that the lift happened.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding(16)
                .padding(.bottom, 24)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Workout recap")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private var completionHeader: some View {
        VStack(spacing: 6) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 48))
                .foregroundStyle(.green)
                .accessibilityHidden(true)
            Text(session.kind.completionTitle)
                .font(.title2.weight(.bold))
                .multilineTextAlignment(.center)
            Text(
                session.completedSetCount == 1
                    ? "1 working set"
                    : "\(session.completedSetCount) working sets"
            )
            .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var musclesHit: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Muscles hit")
                .font(.headline)
            if trainedMuscles.isEmpty {
                Text("No completed sets were mapped to a muscle group.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                FlowLayout(spacing: 8) {
                    ForEach(trainedMuscles, id: \.muscle) { entry in
                        Text(entry.muscle.title)
                            .font(.caption.weight(.semibold))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 7)
                            .background(
                                TodayPalette.muscle.opacity(min(0.22, 0.08 + entry.value / 30)),
                                in: Capsule()
                            )
                    }
                }
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .todayCard()
    }

}

/// Wraps its subviews onto as many lines as they need. Used for the muscle chips.
struct FlowLayout: Layout {
    let spacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? 0
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x + size.width > width, x > 0 {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
        return CGSize(width: width, height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        var y = bounds.minY
        var rowHeight: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x + size.width > bounds.maxX, x > bounds.minX {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }
            view.place(at: CGPoint(x: x, y: y), anchor: .topLeading, proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}

