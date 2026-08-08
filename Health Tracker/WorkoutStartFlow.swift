import SwiftUI

struct WorkoutStartFlow: View {
    @ObservedObject var store: TodayStore
    @ObservedObject var catalog: ExerciseCatalog
    let suggestedKind: WorkoutKind?

    var body: some View {
        if let active = store.activeWorkout {
            // `.shared` is read here rather than defaulted inside the init,
            // because a SwiftUI body is already main-actor and the init is not.
            WorkoutLogView(
                store: store,
                catalog: catalog,
                kind: active.kind,
                brandPreferences: .shared
            )
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
    @State private var selectedRoutineForEditing: HypertrophyTemplate?

    private var splitChoices: [HypertrophyTemplate] { store.routines }

    private var otherChoices: [WorkoutKind] {
        let choices: [WorkoutKind] = [.push, .pull, .legs, .chest, .back, .other]
        guard let suggestedKind, choices.contains(suggestedKind) else { return choices }
        return [suggestedKind] + choices.filter { $0 != suggestedKind }
    }

    private var suggestedTemplateID: String? {
        guard let suggestedKind, suggestedKind == .upper || suggestedKind == .lower else { return nil }
        return store.nextRoutine(for: suggestedKind)?.id
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

                    VStack(alignment: .leading, spacing: 10) {
                        sectionLabel("Your Upper / Lower split")
                        ForEach(splitChoices) { template in
                            HStack(spacing: 8) {
                                Button {
                                    store.beginWorkout(template: template, catalog: catalog)
                                } label: {
                                    splitChoice(template)
                                }
                                .buttonStyle(.plain)
                                .accessibilityIdentifier("start-\(template.id)-workout")

                                Button {
                                    selectedRoutineForEditing = template
                                } label: {
                                    Image(systemName: "slider.horizontal.3")
                                        .font(.body.weight(.semibold))
                                        .frame(width: 44, height: 44)
                                }
                                .buttonStyle(.bordered)
                                .accessibilityLabel("Edit \(template.title)")
                            }
                        }
                    }

                    VStack(alignment: .leading, spacing: 10) {
                        sectionLabel("Other starting points")
                        LazyVGrid(columns: columns, spacing: 12) {
                            ForEach(otherChoices) { kind in
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
            .sheet(item: $selectedRoutineForEditing) { routine in
                RoutineEditorView(store: store, catalog: catalog, routine: routine)
            }
        }
    }

    private func sectionLabel(_ title: String) -> some View {
        Text(title.uppercased())
            .font(.caption2.weight(.bold))
            .tracking(0.8)
            .foregroundStyle(.secondary)
            .padding(.leading, 2)
    }

    private func splitChoice(_ template: HypertrophyTemplate) -> some View {
        HStack(alignment: .top, spacing: 13) {
            Image(systemName: template.kind.symbol)
                .font(.title3.weight(.semibold))
                .foregroundStyle(TodayPalette.accent)
                .frame(width: 42, height: 42)
                .background(TodayPalette.accent.opacity(0.1), in: RoundedRectangle(cornerRadius: 12))

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(template.title)
                        .font(.headline)
                    if template.id == suggestedTemplateID {
                        todayBadge
                    }
                }
                Text(template.focus)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                Text(WorkoutMuscleCoverage.summary(template.targetMuscles))
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(TodayPalette.muscle)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .todayCard()
        .overlay {
            if template.id == suggestedTemplateID {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .stroke(TodayPalette.accent.opacity(0.45), lineWidth: 1.5)
            }
        }
    }

    private var todayBadge: some View {
        Text("TODAY")
            .font(.system(size: 8, weight: .bold, design: .rounded))
            .tracking(0.8)
            .foregroundStyle(TodayPalette.accent)
            .padding(.horizontal, 6)
            .padding(.vertical, 4)
            .background(TodayPalette.accent.opacity(0.1), in: Capsule())
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

                if kind == suggestedKind { todayBadge }
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

private struct RoutineEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var store: TodayStore
    @ObservedObject var catalog: ExerciseCatalog
    @State private var draft: HypertrophyTemplate
    @State private var pickerMode: PickerMode?
    @State private var showResetConfirmation = false

    private enum PickerMode: Identifiable {
        case add
        case replace(String)

        var id: String {
            switch self {
            case .add: "add"
            case .replace(let id): "replace-\(id)"
            }
        }
    }

    init(store: TodayStore, catalog: ExerciseCatalog, routine: HypertrophyTemplate) {
        self.store = store
        self.catalog = catalog
        _draft = State(initialValue: routine)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Routine") {
                    TextField("Name", text: $draft.title)
                    TextField("Focus", text: $draft.focus, axis: .vertical)
                        .lineLimit(2...4)
                }

                Section {
                    ForEach($draft.exercises) { $item in
                        HStack(spacing: 12) {
                            Button {
                                pickerMode = .replace(item.id)
                            } label: {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(catalog.exercise(id: item.exerciseID)?.name ?? item.exerciseID)
                                        .font(.subheadline.weight(.semibold))
                                        .foregroundStyle(.primary)
                                    Text("Tap to swap")
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)

                            Stepper("\(item.sets)", value: $item.sets, in: 1...6)
                                .labelsHidden()
                            Text("\(item.sets)")
                                .font(.subheadline.monospacedDigit().weight(.semibold))
                                .frame(width: 18)
                        }
                        .swipeActions {
                            Button("Remove", systemImage: "trash", role: .destructive) {
                                draft.exercises.removeAll { $0.id == item.id }
                            }
                        }
                    }
                    .onMove { source, destination in
                        draft.exercises.move(fromOffsets: source, toOffset: destination)
                    }

                    Button("Add exercise", systemImage: "plus") {
                        pickerMode = .add
                    }
                } header: {
                    Text("Exercises")
                } footer: {
                    Text("Drag to reorder. Tap a movement to swap it. The set count controls working sets.")
                }

                Section("Coverage targets") {
                    ForEach(WorkoutMuscleArea.allCases) { area in
                        Toggle(area.rawValue, isOn: targetBinding(for: area))
                    }
                }

                Section {
                    Button("Reset to Today default", role: .destructive) {
                        showResetConfirmation = true
                    }
                }
            }
            .navigationTitle("Edit \(draft.title)")
            .navigationBarTitleDisplayMode(.inline)
            .environment(\.editMode, .constant(.active))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        store.updateRoutine(draft)
                        dismiss()
                    }
                    .fontWeight(.semibold)
                    .disabled(draft.exercises.isEmpty || draft.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .sheet(item: $pickerMode) { mode in
                ExercisePickerView(
                    catalog: catalog,
                    brandPreferences: .shared,
                    selectedIDs: Set(draft.exercises.map(\.exerciseID)),
                    recentIDs: store.workouts.flatMap(\.exercises).map(\.baseExerciseID)
                ) { exercise in
                    select(exercise, for: mode)
                }
            }
            .confirmationDialog(
                "Reset \(draft.title)?",
                isPresented: $showResetConfirmation,
                titleVisibility: .visible
            ) {
                Button("Reset routine", role: .destructive) {
                    if let original = HypertrophyProgramming.template(id: draft.id) {
                        draft = original
                    }
                }
                Button("Keep changes", role: .cancel) {}
            } message: {
                Text("This restores the original exercises, order, set counts, and coverage targets. Your workout history does not change.")
            }
        }
    }

    private func targetBinding(for area: WorkoutMuscleArea) -> Binding<Bool> {
        Binding(
            get: { draft.targetMuscles.contains(area) },
            set: { enabled in
                if enabled {
                    if !draft.targetMuscles.contains(area) { draft.targetMuscles.append(area) }
                } else {
                    draft.targetMuscles.removeAll { $0 == area }
                }
            }
        )
    }

    private func select(_ exercise: ExerciseDefinition, for mode: PickerMode) {
        switch mode {
        case .add:
            guard !draft.exercises.contains(where: { $0.exerciseID == exercise.baseID }) else { return }
            draft.exercises.append(.init(exerciseID: exercise.baseID, sets: 2))
        case .replace(let oldID):
            guard let index = draft.exercises.firstIndex(where: { $0.id == oldID }) else { return }
            draft.exercises[index].exerciseID = exercise.baseID
        }
        pickerMode = nil
    }
}

#Preview {
    WorkoutStartFlow(
        store: TodayStore(storageURL: FileManager.default.temporaryDirectory.appendingPathComponent("workout-picker-preview.json")),
        catalog: ExerciseCatalog(),
        suggestedKind: .lower
    )
}
