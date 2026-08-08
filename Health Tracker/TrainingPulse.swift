import SwiftUI

enum TrainingRegion: String, CaseIterable, Identifiable {
    case chest = "Chest"
    case back = "Back"
    case shoulders = "Shoulders"
    case biceps = "Biceps"
    case triceps = "Triceps"
    case quads = "Quads"
    case hamstrings = "Hamstrings"
    case glutes = "Glutes"
    case calves = "Calves"
    case core = "Core"

    var id: Self { self }

    var symbol: String {
        switch self {
        case .chest: "figure.strengthtraining.traditional"
        case .back: "figure.climbing"
        case .shoulders: "figure.arms.open"
        case .biceps, .triceps: "dumbbell.fill"
        case .quads, .hamstrings, .glutes: "figure.run"
        case .calves: "shoeprints.fill"
        case .core: "figure.core.training"
        }
    }

    static func region(for muscle: MuscleGroup) -> TrainingRegion {
        switch muscle {
        case .upperChest, .middleChest, .lowerChest: .chest
        case .lats, .rhomboids, .upperTraps, .middleTraps, .lowerTraps, .lowerBack: .back
        case .frontDelts, .sideDelts, .rearDelts: .shoulders
        case .bicepsLongHead, .bicepsShortHead, .brachialis, .forearms: .biceps
        case .tricepsLongHead, .tricepsLateralHead, .tricepsMedialHead: .triceps
        case .rectusFemoris, .vastusLateralis, .vastusMedialis: .quads
        case .hamstrings: .hamstrings
        case .gluteMax, .gluteMed, .adductors, .abductors: .glutes
        case .gastrocnemius, .soleus, .tibialisAnterior: .calves
        case .rectusAbdominis, .obliques: .core
        }
    }
}

struct TrainingRegionDose: Identifiable, Equatable {
    let region: TrainingRegion
    let estimatedSets: Double
    let exposureDays: Int

    var id: TrainingRegion { region }
}

struct TrainingPulseSnapshot: Equatable {
    let sessions: Int
    let hardSets: Int
    let failureSets: Int
    let regions: [TrainingRegionDose]

    var trainedRegions: Int { regions.filter { $0.estimatedSets > 0 }.count }
    var failureShare: Double { hardSets > 0 ? Double(failureSets) / Double(hardSets) : 0 }

    @MainActor
    static func build(
        workouts: [WorkoutSession],
        catalog: ExerciseCatalog,
        now: Date = .now,
        calendar: Calendar = .current
    ) -> TrainingPulseSnapshot {
        let today = calendar.startOfDay(for: now)
        let cutoff = calendar.date(byAdding: .day, value: -6, to: today) ?? today
        let recent = workouts.filter { $0.startedAt >= cutoff && $0.startedAt < now.addingTimeInterval(86_400) }

        var hardSets = 0
        var failureSets = 0
        var doses: [TrainingRegion: Double] = [:]
        var days: [TrainingRegion: Set<Date>] = [:]

        for workout in recent {
            let day = calendar.startOfDay(for: workout.startedAt)
            for logged in workout.exercises {
                guard let exercise = catalog.exercise(id: logged.exerciseID) else { continue }
                let performed = logged.sets.filter(\.isWorkingSet)
                guard !performed.isEmpty else { continue }

                hardSets += performed.count
                failureSets += performed.filter { $0.rir == 0 }.count

                // Several mapped muscle heads can belong to one region. Taking
                // the maximum contribution per region avoids counting one chest
                // press as multiple chest sets while retaining fractional credit
                // for secondary regions.
                var contributionByRegion: [TrainingRegion: Double] = [:]
                for contribution in exercise.muscles {
                    let region = TrainingRegion.region(for: contribution.muscle)
                    contributionByRegion[region] = max(
                        contributionByRegion[region] ?? 0,
                        min(1, max(0, contribution.intensity))
                    )
                }

                for (region, contribution) in contributionByRegion where contribution > 0 {
                    doses[region, default: 0] += Double(performed.count) * contribution
                    if contribution >= 0.4 {
                        days[region, default: []].insert(day)
                    }
                }
            }
        }

        let regions = TrainingRegion.allCases
            .map { region in
                TrainingRegionDose(
                    region: region,
                    estimatedSets: doses[region] ?? 0,
                    exposureDays: days[region]?.count ?? 0
                )
            }
            .filter { $0.estimatedSets > 0 }
            .sorted {
                if $0.estimatedSets == $1.estimatedSets {
                    return $0.region.rawValue < $1.region.rawValue
                }
                return $0.estimatedSets > $1.estimatedSets
            }

        return TrainingPulseSnapshot(
            sessions: recent.count,
            hardSets: hardSets,
            failureSets: failureSets,
            regions: regions
        )
    }
}

struct TrainingPulseCard: View {
    let snapshot: TrainingPulseSnapshot
    let muscleScores: [MuscleGroup: Double]

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header

            HStack(spacing: 9) {
                pulseStat(snapshot.sessions, "sessions")
                pulseStat(snapshot.hardSets, "hard sets")
                pulseStat(snapshot.trainedRegions, "regions")
            }

            if snapshot.hardSets == 0 {
                Text("Complete a workout and Today will summarize your seven-day training dose here.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                doseRows
                if snapshot.failureShare >= 0.8 {
                    fatigueCallout
                }
            }

            HStack(spacing: 10) {
                NavigationLink {
                    MuscleExposureDetailView(scores: muscleScores)
                } label: {
                    Label("Muscle breakdown", systemImage: "list.bullet.rectangle")
                        .frame(maxWidth: .infinity)
                }
                NavigationLink {
                    ResearchLibraryView()
                } label: {
                    Label("Evidence", systemImage: "books.vertical")
                        .frame(maxWidth: .infinity)
                }
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .todayCard()
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Training pulse")
                    .font(.headline)
                Text("Rolling 7-day view")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text("ESTIMATED")
                .font(.caption2.weight(.bold))
                .tracking(0.7)
                .foregroundStyle(TodayPalette.muscle)
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(TodayPalette.muscle.opacity(0.09), in: Capsule())
        }
    }

    private func pulseStat(_ value: Int, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("\(value)")
                .font(.title3.monospacedDigit().weight(.bold))
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.tertiarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14))
        .accessibilityElement(children: .combine)
    }

    private var doseRows: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Estimated set exposure")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Text("top regions")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            ForEach(snapshot.regions.prefix(5)) { dose in
                VStack(spacing: 5) {
                    HStack {
                        Text(dose.region.rawValue)
                        Spacer()
                        Text(doseLabel(dose))
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                    .font(.caption)
                    GeometryReader { proxy in
                        ZStack(alignment: .leading) {
                            Capsule().fill(Color.primary.opacity(0.07))
                            Capsule()
                                .fill(TodayPalette.muscle.gradient)
                                .frame(width: proxy.size.width * min(1, dose.estimatedSets / 12))
                        }
                    }
                    .frame(height: 6)
                }
                .accessibilityElement(children: .combine)
            }
            Text("A transparent estimate from completed sets and exercise mappings—not activation, recovery, or measured muscle growth.")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func doseLabel(_ dose: TrainingRegionDose) -> String {
        let sets = dose.estimatedSets.formatted(.number.precision(.fractionLength(0...1)))
        return "\(sets) · \(dose.exposureDays)×"
    }

    private var fatigueCallout: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "bolt.heart.fill")
                .foregroundStyle(TodayPalette.warm)
            VStack(alignment: .leading, spacing: 3) {
                Text("Your main fatigue lever")
                    .font(.caption.weight(.bold))
                Text("Nearly every tracked set reaches failure. Current reviews do not show a reliable growth advantage over hard non-failure work; keep a buffer on squats and hinges before adding volume.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(12)
        .background(TodayPalette.warm.opacity(0.09), in: RoundedRectangle(cornerRadius: 14))
    }
}

private struct MuscleExposureDetailView: View {
    let scores: [MuscleGroup: Double]

    private var activeMuscles: [(muscle: MuscleGroup, score: Double)] {
        scores
            .filter { $0.value > 0 }
            .map { (muscle: $0.key, score: $0.value) }
            .sorted { $0.score == $1.score ? $0.muscle.title < $1.muscle.title : $0.score > $1.score }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text("Completed sets are broken down using each exercise’s muscle mapping. This is an exposure estimate, not a measurement of activation, fatigue, or growth.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                VStack(spacing: 12) {
                    ForEach(activeMuscles, id: \.muscle) { entry in
                        VStack(spacing: 6) {
                            HStack {
                                Text(entry.muscle.title)
                                    .font(.subheadline.weight(.semibold))
                                Spacer()
                                Text(entry.score.formatted(.number.precision(.fractionLength(0...1))))
                                    .font(.caption.monospacedDigit().weight(.semibold))
                                    .foregroundStyle(.secondary)
                            }
                            GeometryReader { proxy in
                                ZStack(alignment: .leading) {
                                    Capsule().fill(Color.primary.opacity(0.07))
                                    Capsule()
                                        .fill(TodayPalette.muscle.gradient)
                                        .frame(width: proxy.size.width * min(1, entry.score / 12))
                                }
                            }
                            .frame(height: 7)
                        }
                        .accessibilityElement(children: .combine)
                    }
                }
                .padding(16)
                .todayCard()
            }
            .padding(16)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Muscle exposure")
        .navigationBarTitleDisplayMode(.inline)
    }
}
