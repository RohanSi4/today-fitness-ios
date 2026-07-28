import SwiftUI

struct WorkoutLogView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var store: TodayStore
    @ObservedObject var catalog: ExerciseCatalog
    @ObservedObject var brandPreferences: BrandPreferences

    let kind: WorkoutKind
    @State private var draft: WorkoutSession
    @State private var showingExercisePicker = false
    @State private var showingMuscleMap = false
    @State private var completedSession: WorkoutSession?
    @State private var showDiscardConfirmation = false

    private static let finishButtonID = "finish-workout"

    /// `brandPreferences` is required for the same reason as
    /// `ExercisePickerView.init`: defaulting it to the `@MainActor`
    /// `BrandPreferences.shared` is an error under the Swift 6 language mode,
    /// and `@MainActor` on the init does not silence it because the default
    /// expression is type-checked outside that isolation. Callers are SwiftUI
    /// bodies, which are already main-actor, so passing it is free there.
    ///
    /// This init also reads `store.activeWorkout`, so it was only ever correct
    /// on the main actor to begin with.
    @MainActor
    init(
        store: TodayStore,
        catalog: ExerciseCatalog,
        kind: WorkoutKind,
        brandPreferences: BrandPreferences
    ) {
        self.store = store
        self.catalog = catalog
        self.brandPreferences = brandPreferences
        self.kind = kind
        _draft = State(initialValue: store.activeWorkout ?? WorkoutSession(
            kind: kind,
            startedAt: Date(),
            endedAt: nil,
            exercises: []
        ))
    }

    var body: some View {
        Group {
            if let completedSession {
                WorkoutSummaryView(session: completedSession, store: store, catalog: catalog)
            } else {
                workoutEditor
            }
        }
        .onDisappear {
            persistActiveWorkoutIfNeeded()
        }
    }

    private var workoutEditor: some View {
        NavigationStack {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(spacing: 16) {
                        watchReminder
                        liveMuscleMap
                        exerciseCards(proxy)

                        if draft.exercises.isEmpty {
                            emptyState
                        }

                        Button {
                            showingExercisePicker = true
                        } label: {
                            Label("Add exercise", systemImage: "plus.circle.fill")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.large)

                        Button {
                            finishWorkout()
                        } label: {
                            Text("Finish workout").frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                        .disabled(draft.completedSetCount == 0)
                        .padding(.top, 6)
                        .id(Self.finishButtonID)
                    }
                    .padding(16)
                    .padding(.bottom, 24)
                }
                .background(Color(.systemGroupedBackground))
                .scrollDismissesKeyboard(.interactively)
            }
            .navigationTitle(kind.workoutTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { toolbarContent }
            .sheet(isPresented: $showingExercisePicker) {
                ExercisePickerView(
                    catalog: catalog,
                    brandPreferences: brandPreferences,
                    // Base ids, because "Lat pulldown" is already in this
                    // workout whichever maker's version of it was added.
                    selectedIDs: Set(draft.exercises.map(\.baseExerciseID)),
                    recentIDs: recentExerciseIDs
                ) { exercise in
                    withAnimation(.snappy) { add(exercise) }
                }
            }
            .confirmationDialog(
                "Discard this workout?",
                isPresented: $showDiscardConfirmation,
                titleVisibility: .visible
            ) {
                Button("Discard workout", role: .destructive) {
                    store.discardActiveWorkout()
                    dismiss()
                }
                Button("Keep workout", role: .cancel) {}
            } message: {
                Text("Every set logged in this session is deleted. This cannot be undone.")
            }
            .onChange(of: draft) { _, updated in
                store.updateActiveWorkout(updated)
            }
        }
    }

    @ViewBuilder
    private func exerciseCards(_ proxy: ScrollViewProxy) -> some View {
        ForEach($draft.exercises) { $loggedExercise in
            if let exercise = catalog.exercise(id: loggedExercise.exerciseID) {
                ExerciseLogCard(
                    exercise: exercise,
                    baseName: baseName(for: loggedExercise, resolved: exercise),
                    loggedExercise: $loggedExercise,
                    history: store.lastPerformance(for: exercise.id),
                    brandOptions: catalog.brands(for: loggedExercise.exerciseID),
                    isUsingCarriedOverHistory: BrandedStarterRules.isUsingCarriedOverHistory(
                        exerciseID: loggedExercise.exerciseID,
                        history: store
                    ),
                    canMoveUp: draft.exercises.first?.id != loggedExercise.id,
                    canMoveDown: draft.exercises.last?.id != loggedExercise.id,
                    onMoveUp: { moveExercise(loggedExercise.id, by: -1) },
                    onMoveDown: { moveExercise(loggedExercise.id, by: 1) },
                    onRemove: {
                        withAnimation(.snappy) {
                            draft.exercises.removeAll { $0.id == loggedExercise.id }
                        }
                    },
                    onFinished: {
                        // Falls through to the Finish button once nothing is
                        // left, instead of silently not scrolling at all.
                        let target: AnyHashable = nextExerciseID(after: loggedExercise.id)
                            .map(AnyHashable.init) ?? AnyHashable(Self.finishButtonID)
                        withAnimation(.snappy) { proxy.scrollTo(target, anchor: .top) }
                    },
                    onSelectBrand: { brand in
                        setBrand(brand, on: loggedExercise.id)
                    }
                )
                .id(loggedExercise.id)
                .transition(.opacity.combined(with: .scale(scale: 0.97)))
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "dumbbell")
                .font(.largeTitle)
                .foregroundStyle(.tertiary)
            Text("Nothing added yet")
                .font(.headline)
            Text("Add the first exercise and Today will pre-fill the weights you used last time.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 28)
        .padding(.horizontal, 16)
        .todayCard()
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .cancellationAction) {
            Button("Close") {
                persistActiveWorkoutIfNeeded()
                dismiss()
            }
            .accessibilityIdentifier("close-workout-button")
        }
        ToolbarItemGroup(placement: .confirmationAction) {
            Text("\(draft.completedSetCount) sets")
                .font(.subheadline.monospacedDigit())
                .foregroundStyle(.secondary)
                .accessibilityLabel("\(draft.completedSetCount) sets logged")
            Menu {
                Button(role: .destructive) {
                    showDiscardConfirmation = true
                } label: {
                    Label("Discard workout", systemImage: "trash")
                }
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .accessibilityLabel("Workout options")
            .accessibilityIdentifier("workout-options-menu")
        }
        ToolbarItemGroup(placement: .keyboard) {
            Spacer()
            Button("Done") { dismissKeyboard() }
            .fontWeight(.semibold)
        }
    }

    private var liveMuscleMap: some View {
        VStack(spacing: 0) {
            Button {
                withAnimation(.snappy) { showingMuscleMap.toggle() }
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "figure.strengthtraining.traditional")
                        .font(.title3)
                        .foregroundStyle(TodayPalette.muscle)
                        .frame(width: 38, height: 38)
                        .background(TodayPalette.muscle.opacity(0.09), in: RoundedRectangle(cornerRadius: 11))

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Muscle map")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.primary)
                        Text(muscleMapStatus)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Image(systemName: "chevron.down")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.tertiary)
                        .rotationEffect(.degrees(showingMuscleMap ? 180 : 0))
                }
                .padding(14)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Muscle map, \(muscleMapStatus)")
            .accessibilityHint(showingMuscleMap ? "Collapses the muscle map" : "Expands the muscle map")

            if showingMuscleMap {
                Divider().padding(.horizontal, 14)
                MuscleMapView(scores: store.muscleScores(for: draft, catalog: catalog), compact: true)
                    .padding(14)
                    .frame(maxWidth: .infinity)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .todayCard()
    }

    private var watchReminder: some View {
        HStack(spacing: 12) {
            Image(systemName: "applewatch")
                .font(.title2)
                .foregroundStyle(TodayPalette.accent)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text("Start Strength Training on your Watch")
                    .font(.subheadline.weight(.semibold))
                Text("Today tracks your sets. Your Watch and HealthFit still own the workout.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(TodayPalette.accent.opacity(0.09), in: RoundedRectangle(cornerRadius: 18))
        .accessibilityElement(children: .combine)
    }

    private var muscleMapStatus: String {
        let count = store.muscleScores(for: draft, catalog: catalog).filter { $0.value > 0 }.count
        if count == 0 { return "Fills in as you finish sets" }
        return count == 1 ? "1 area hit so far" : "\(count) areas hit so far"
    }

    /// Base ids on purpose. Recent should offer the movement, and the remembered
    /// maker is applied when it is tapped, so the same lift does not appear
    /// three times because it was logged on three machines.
    private var recentExerciseIDs: [String] {
        var seen = Set<String>()
        return store.workouts
            .sorted { $0.startedAt > $1.startedAt }
            .flatMap(\.exercises)
            .map(\.baseExerciseID)
            .filter { seen.insert($0).inserted }
            .prefix(10)
            .map { $0 }
    }

    /// The movement's name with no maker on it, since the brand has its own chip.
    private func baseName(for logged: LoggedExercise, resolved: ExerciseDefinition) -> String {
        guard logged.brand != nil else { return resolved.name }
        return catalog.exercise(id: logged.baseExerciseID)?.name ?? resolved.name
    }

    private func add(_ exercise: ExerciseDefinition) {
        let brand = brandPreferences.lastBrand(for: exercise.baseID)
        let exerciseID = catalog.qualifiedID(for: exercise.id, brand: brand)
        let starter = BrandedStarterRules.starter(
            for: exerciseID,
            history: store,
            catalog: catalog
        )
        draft.exercises.append(
            LoggedExercise(exerciseID: exerciseID, sets: starter.sets)
        )
    }

    /// Changing maker part-way through keeps every set already logged.
    ///
    /// `LoggedExercise.exerciseID` is a `let`, so the row is rebuilt rather than
    /// mutated. Reusing the same `id` keeps SwiftUI's identity, which keeps the
    /// card's expanded state and the sets exactly as they are. Refusing the
    /// change would mean deleting the exercise and re-adding it, which loses the
    /// work; and realising halfway through that you are on the Cybex rather than
    /// the Life Fitness is a correction, not a falsification, because the sets
    /// really were done on the machine you are standing at.
    private func setBrand(_ brand: EquipmentBrand?, on loggedID: UUID) {
        guard let index = draft.exercises.firstIndex(where: { $0.id == loggedID }) else { return }
        let existing = draft.exercises[index]
        let exerciseID = catalog.qualifiedID(for: existing.baseExerciseID, brand: brand)
        guard exerciseID != existing.exerciseID else { return }

        brandPreferences.remember(brand, for: existing.baseExerciseID)
        withAnimation(.snappy) {
            draft.exercises[index] = LoggedExercise(
                id: existing.id,
                exerciseID: exerciseID,
                sets: existing.sets
            )
        }
    }

    private func finishWorkout() {
        // A weight still being typed only commits to its binding when the field
        // resigns, so a set edited right up to the tap could be saved with the
        // previous value. Drop the keyboard, then let SwiftUI apply the write
        // before the draft is handed to the store.
        dismissKeyboard()
        Task { @MainActor in
            await Task.yield()
            store.updateActiveWorkout(draft)
            completedSession = store.finishActiveWorkout()
        }
    }

    private func moveExercise(_ id: UUID, by offset: Int) {
        guard let source = draft.exercises.firstIndex(where: { $0.id == id }) else { return }
        let destination = source + offset
        guard draft.exercises.indices.contains(destination) else { return }
        withAnimation(.snappy) {
            draft.exercises.swapAt(source, destination)
        }
    }

    private func nextExerciseID(after id: UUID) -> UUID? {
        guard let index = draft.exercises.firstIndex(where: { $0.id == id }) else { return nil }
        return draft.exercises.dropFirst(index + 1).first(where: { logged in
            logged.sets.contains { !$0.isPerformed }
        })?.id
    }

    private func persistActiveWorkoutIfNeeded() {
        guard completedSession == nil, store.activeWorkout != nil else { return }
        store.updateActiveWorkout(draft)
        store.flushPersistence()
    }
}
