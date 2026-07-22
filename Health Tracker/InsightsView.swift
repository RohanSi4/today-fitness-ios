import SwiftUI

struct InsightsView: View {
    @ObservedObject var store: TodayStore
    @ObservedObject var catalog: ExerciseCatalog
    let recapDate: Date?

    @State private var showingRecap = false

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                weightProgress
                recentMuscleWork
                strengthProgress

                Button {
                    showingRecap = true
                } label: {
                    HStack(spacing: 14) {
                        Image(systemName: "bed.double.fill")
                            .font(.title2)
                            .foregroundStyle(.indigo)
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Sleep and movement recap").font(.headline)
                            Text("The original Health Recap is still here.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Image(systemName: "chevron.right").foregroundStyle(.tertiary)
                    }
                    .padding(16)
                }
                .buttonStyle(.plain)
                .todayCard()
                .accessibilityIdentifier("sleep-movement-recap-button")
            }
            .padding(16)
            .padding(.bottom, 28)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Insights")
        .sheet(isPresented: $showingRecap) {
            DailyRecapView(targetDate: recapDate)
        }
    }

    private var weightProgress: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("Weight goal", systemImage: "scalemass.fill")
                .font(.headline)
            if let latest = store.latestWeight {
                HStack(alignment: .firstTextBaseline) {
                    Text("\(latest.pounds.formatted(.number.precision(.fractionLength(1))))")
                        .font(.system(size: 38, weight: .bold, design: .rounded))
                        .monospacedDigit()
                    Text("lb").foregroundStyle(.secondary)
                    Spacer()
                    VStack(alignment: .trailing, spacing: 2) {
                        Text("\(max(0, latest.pounds - store.goalWeight).formatted(.number.precision(.fractionLength(1)))) lb")
                            .font(.headline.monospacedDigit())
                        Text("to 175").font(.caption).foregroundStyle(.secondary)
                    }
                }

                if let average = store.sevenDayAverage {
                    insightRow("7-day average", "\(average.formatted(.number.precision(.fractionLength(1)))) lb")
                }
                if let change = store.thirtyDayChange {
                    insightRow("30-day change", "\(change.formatted(.number.sign(strategy: .always()).precision(.fractionLength(1)))) lb")
                }
            } else {
                Text("Log a few mornings and your trend will show here.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Text("Private on this device and in Apple Health.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .todayCard()
    }

    private var recentMuscleWork: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Last 7 days").font(.headline)
                Spacer()
                Text("Muscles trained").font(.caption).foregroundStyle(.secondary)
            }
            MuscleMapView(scores: recentScores, compact: true)
        }
        .padding(18)
        .frame(maxWidth: .infinity)
        .todayCard()
    }

    @ViewBuilder
    private var strengthProgress: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Strength progress").font(.headline)
            let records = exerciseRecords
            if records.isEmpty {
                Text("Your best sets and estimated strength will appear after the first workout.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(records.prefix(6), id: \.exercise.id) { record in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(record.exercise.name).font(.subheadline.weight(.semibold))
                            Text("Best recorded set").font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text(record.label)
                            .font(.subheadline.monospacedDigit().weight(.semibold))
                    }
                    if record.exercise.id != records.prefix(6).last?.exercise.id {
                        Divider()
                    }
                }
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .todayCard()
    }

    private var recentScores: [MuscleGroup: Double] {
        let cutoff = Calendar.current.date(byAdding: .day, value: -7, to: Date()) ?? Date()
        return store.workouts.filter { $0.startedAt >= cutoff }.reduce(into: [:]) { result, workout in
            for (muscle, value) in store.muscleScores(for: workout, catalog: catalog) {
                result[muscle, default: 0] += value
            }
        }
    }

    private var exerciseRecords: [(exercise: ExerciseDefinition, label: String, estimate: Double)] {
        var records: [String: (exercise: ExerciseDefinition, label: String, estimate: Double)] = [:]
        for workout in store.workouts {
            for logged in workout.exercises {
                guard let exercise = catalog.exercise(id: logged.exerciseID) else { continue }
                for set in logged.sets where set.isComplete {
                    let weight = set.weight ?? 0
                    let estimate = weight > 0 ? weight * (1 + Double(set.reps) / 30) : Double(set.reps)
                    guard estimate > (records[exercise.id]?.estimate ?? -1) else { continue }
                    let label = weight > 0
                        ? "\(weight.formatted(.number.precision(.fractionLength(0...1)))) × \(set.reps)"
                        : "\(set.reps) reps"
                    records[exercise.id] = (exercise, label, estimate)
                }
            }
        }
        return records.values.sorted { $0.estimate > $1.estimate }
    }

    private func insightRow(_ title: String, _ value: String) -> some View {
        HStack {
            Text(title).foregroundStyle(.secondary)
            Spacer()
            Text(value).font(.subheadline.monospacedDigit().weight(.semibold))
        }
        .font(.subheadline)
    }
}
