import SwiftUI

/// A reference list of the run-day stretches. Tap a card to open its cue and
/// a placeholder figure; the segmented control switches between the dynamic
/// warm-up and the static cool-down.
struct StretchRoutineView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var phase: StretchPhase

    init(initialPhase: StretchPhase = .dynamic) {
        _phase = State(initialValue: initialPhase)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Text(phase.summary)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.top, 2)

                    ForEach(StretchLibrary.stretches(for: phase)) { stretch in
                        StretchCard(stretch: stretch)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 28)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Stretches")
            .navigationBarTitleDisplayMode(.inline)
            .safeAreaInset(edge: .top) {
                Picker("Phase", selection: $phase.animation(.easeInOut(duration: 0.2))) {
                    ForEach(StretchPhase.allCases) { phase in
                        Text(phase.shortTitle).tag(phase)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 16)
                .padding(.top, 6)
                .padding(.bottom, 10)
                .background(.bar)
            }
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

private struct StretchCard: View {
    let stretch: Stretch
    @State private var isOpen = false

    var body: some View {
        Button {
            withAnimation(.snappy(duration: 0.26)) { isOpen.toggle() }
        } label: {
            VStack(spacing: 0) {
                HStack(spacing: 14) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(TodayPalette.accent.opacity(0.12))
                        Image(systemName: stretch.symbol)
                            .font(.title2)
                            .foregroundStyle(TodayPalette.accent)
                    }
                    .frame(width: 50, height: 50)

                    VStack(alignment: .leading, spacing: 3) {
                        Text(stretch.name)
                            .font(.headline)
                            .multilineTextAlignment(.leading)
                        Label(stretch.style.label, systemImage: stretch.style.symbol)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer(minLength: 8)

                    Image(systemName: "chevron.down")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.tertiary)
                        .rotationEffect(.degrees(isOpen ? 180 : 0))
                }
                .padding(16)

                if isOpen {
                    VStack(alignment: .leading, spacing: 14) {
                        Image(systemName: stretch.symbol)
                            .font(.system(size: 62))
                            .foregroundStyle(TodayPalette.accent)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 4)
                            .accessibilityHidden(true)

                        Text(stretch.cue)
                            .font(.subheadline)
                            .frame(maxWidth: .infinity, alignment: .leading)

                        Label(stretch.targets, systemImage: "target")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.secondary)
                    }
                    .padding([.horizontal, .bottom], 16)
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .todayCard()
        .accessibilityElement(children: .combine)
        .accessibilityHint(isOpen ? "Collapse" : "Show how to do it")
    }
}

#Preview {
    StretchRoutineView()
}
