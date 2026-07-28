import SwiftUI

struct ExercisePickerView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var catalog: ExerciseCatalog
    let selectedIDs: Set<String>
    let recentIDs: [String]
    let onSelect: (ExerciseDefinition) -> Void

    @State private var query = ""
    @State private var addedIDs: Set<String>

    init(
        catalog: ExerciseCatalog,
        selectedIDs: Set<String>,
        recentIDs: [String],
        onSelect: @escaping (ExerciseDefinition) -> Void
    ) {
        self.catalog = catalog
        self.selectedIDs = selectedIDs
        self.recentIDs = recentIDs
        self.onSelect = onSelect
        _addedIDs = State(initialValue: selectedIDs)
    }

    var body: some View {
        NavigationStack {
            Group {
                if searchResults.isEmpty, recentExercises.isEmpty {
                    // Searching 700+ exercises and getting a blank list read as a
                    // broken screen: there was no empty state and no sign the
                    // catalog was still downloading.
                    emptyState
                } else {
                    list
                }
            }
            .searchable(text: $query, prompt: "Search 700+ exercises")
            .navigationTitle("Add exercises")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .fontWeight(.semibold)
                }
            }
            .task { await catalog.refreshIfNeeded() }
        }
    }

    private var list: some View {
        List {
            if query.isEmpty, !recentExercises.isEmpty {
                Section("Recent") {
                    ForEach(recentExercises) { exercise in
                        exerciseRow(exercise)
                    }
                }
            }

            Section(query.isEmpty ? "Browse" : "Results") {
                ForEach(searchResults) { exercise in
                    exerciseRow(exercise)
                }
            }
        }
    }

    @ViewBuilder
    private var emptyState: some View {
        if catalog.isLoading {
            ProgressView("Loading exercises")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(.systemGroupedBackground))
        } else if query.isEmpty {
            ContentUnavailableView(
                "No exercises yet",
                systemImage: "dumbbell",
                description: Text("The exercise list could not load. Pull down on Today to retry.")
            )
        } else {
            ContentUnavailableView.search(text: query)
        }
    }

    private var recentExercises: [ExerciseDefinition] {
        recentIDs.compactMap(catalog.exercise(id:)).filter { !selectedIDs.contains($0.id) }
    }

    private var searchResults: [ExerciseDefinition] {
        let recent = Set(recentExercises.map(\.id))
        return catalog.search(query).filter { !query.isEmpty || !recent.contains($0.id) }
    }

    private func exerciseRow(_ exercise: ExerciseDefinition) -> some View {
        let isAdded = addedIDs.contains(exercise.id)
        return Button {
            guard !isAdded else { return }
            onSelect(exercise)
            addedIDs.insert(exercise.id)
        } label: {
            HStack(spacing: 12) {
                Image(systemName: isAdded ? "checkmark.circle.fill" : "plus.circle.fill")
                    .foregroundStyle(isAdded ? .green : TodayPalette.accent)
                VStack(alignment: .leading, spacing: 3) {
                    Text(exercise.name).foregroundStyle(.primary)
                    Text(
                        exercise.muscles
                            .sorted { $0.intensity > $1.intensity }
                            .prefix(3)
                            .map(\.muscle.title)
                            .joined(separator: " · ")
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                }
                Spacer()
            }
            .contentShape(Rectangle())
        }
        .disabled(isAdded)
        .accessibilityLabel(isAdded ? "\(exercise.name), already added" : "Add \(exercise.name)")
    }
}
