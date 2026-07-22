import SwiftUI

struct StretchRoutineView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var phase: StretchPhase

    init(initialPhase: StretchPhase = .dynamic) {
        _phase = State(initialValue: initialPhase)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    StretchRoutineHeader(phase: phase)

                    Text("Quick reference")
                        .font(.headline)
                        .padding(.horizontal, 2)

                    VStack(spacing: 12) {
                        ForEach(StretchLibrary.stretches(for: phase)) { stretch in
                            StretchCard(stretch: stretch)
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 14)
                .padding(.bottom, 24)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Run stretches")
            .navigationBarTitleDisplayMode(.inline)
            .safeAreaInset(edge: .top) {
                Picker("Routine", selection: $phase) {
                    ForEach(StretchPhase.allCases) { phase in
                        Text(phase.shortTitle).tag(phase)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(.bar)
                .accessibilityIdentifier("stretch-phase-picker")
            }
            .navigationDestination(for: StretchPhase.self) { phase in
                GuidedStretchRoutineView(phase: phase) {
                    dismiss()
                }
            }
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

private struct StretchRoutineHeader: View {
    let phase: StretchPhase

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label(phase.title, systemImage: phase.symbol)
                .font(.title3.weight(.bold))
                .foregroundStyle(TodayPalette.accent)

            Text(phase.summary)
                .font(.subheadline)

            HStack(spacing: 16) {
                Label("\(StretchLibrary.stretches(for: phase).count) moves", systemImage: "list.bullet")
                Label("About \(phase.estimatedMinutes) min", systemImage: "clock")
            }
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)

            Label(phase.safetyNote, systemImage: "checkmark.shield")
                .font(.caption)
                .foregroundStyle(.secondary)

            NavigationLink(value: phase) {
                Label(
                    phase == .cooldown ? "Start the hold timer" : "Walk me through it",
                    systemImage: phase == .cooldown ? "timer" : "list.number"
                )
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .accessibilityIdentifier("start-stretch-routine")
        }
        .padding(18)
        .todayCard()
    }
}

private struct StretchCard: View {
    let stretch: Stretch
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isOpen = false

    var body: some View {
        Button(action: toggleOpen) {
            VStack(spacing: 0) {
                HStack(spacing: 14) {
                    Image(stretch.assetName)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 50, height: 50)
                        .background(TodayPalette.accent.opacity(0.08), in: RoundedRectangle(cornerRadius: 14))
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                        .accessibilityHidden(true)

                    VStack(alignment: .leading, spacing: 4) {
                        Text(stretch.name)
                            .font(.headline)
                            .multilineTextAlignment(.leading)
                        Label(stretch.dose.label, systemImage: stretch.dose.symbol)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer(minLength: 8)

                    Image(systemName: "chevron.down")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.tertiary)
                        .rotationEffect(.degrees(isOpen ? 180 : 0))
                        .accessibilityHidden(true)
                }
                .padding(16)

                if isOpen {
                    VStack(alignment: .leading, spacing: 14) {
                        StretchArtwork(stretch: stretch, height: 190)

                        Text(stretch.cue)
                            .font(.subheadline)
                            .frame(maxWidth: .infinity, alignment: .leading)

                        Label(stretch.targets, systemImage: "target")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.secondary)

                        if let support = stretch.support {
                            Label(support, systemImage: "info.circle")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding([.horizontal, .bottom], 16)
                    .transition(reduceMotion ? .opacity : .opacity.combined(with: .move(edge: .top)))
                }
            }
            .contentShape(Rectangle())
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(stretch.name)
            .accessibilityValue(accessibilityValue)
            .accessibilityHint(isOpen ? "Double tap to collapse" : "Double tap for instructions")
            .accessibilityIdentifier("stretch-card-\(stretch.id)")
        }
        .buttonStyle(.plain)
        .todayCard()
    }

    private var accessibilityValue: String {
        guard isOpen else { return "\(stretch.dose.label). Collapsed" }
        return "\(stretch.dose.label). \(stretch.cue). Targets \(stretch.targets). Expanded"
    }

    private func toggleOpen() {
        if reduceMotion {
            isOpen.toggle()
        } else {
            withAnimation(.snappy(duration: 0.26)) { isOpen.toggle() }
        }
    }
}

struct StretchArtwork: View {
    let stretch: Stretch
    let height: CGFloat

    var body: some View {
        Image(stretch.assetName)
            .resizable()
            .scaledToFit()
            .frame(maxWidth: .infinity)
            .frame(height: height)
            .background(
                LinearGradient(
                    colors: [TodayPalette.accent.opacity(0.07), TodayPalette.warm.opacity(0.07)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .accessibilityHidden(true)
    }
}

#Preview {
    StretchRoutineView()
}
