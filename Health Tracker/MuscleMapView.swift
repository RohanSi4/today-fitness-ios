import SwiftUI

struct MuscleMapView: View {
    let scores: [MuscleGroup: Double]
    var compact = false

    @State private var selectedSide: AnatomySide = .front

    private var activeMuscles: [MuscleGroup] {
        scores
            .filter { $0.value > 0 }
            .sorted { $0.value > $1.value }
            .map(\.key)
    }

    private var activeSignature: String {
        activeMuscles.map(\.rawValue).joined(separator: ",")
    }

    var body: some View {
        VStack(spacing: compact ? 10 : 14) {
            sidePicker

            AnatomyFigure(side: selectedSide, scores: scores)
                .frame(height: compact ? 420 : 500)
                .frame(maxWidth: .infinity)
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 24)
                        .onEnded { value in
                            guard abs(value.translation.width) > abs(value.translation.height) else { return }
                            withAnimation(.snappy) {
                                selectedSide = value.translation.width < 0 ? .back : .front
                            }
                        }
                )

            muscleSummary
        }
        .frame(maxWidth: .infinity)
        .onChange(of: activeSignature) { _, _ in
            let currentScore = selectedSide.totalScore(in: scores)
            let otherSide: AnatomySide = selectedSide == .front ? .back : .front
            guard currentScore == 0, otherSide.totalScore(in: scores) > 0 else { return }
            withAnimation(.snappy) {
                selectedSide = otherSide
            }
        }
        .accessibilityElement(children: .contain)
    }

    private var sidePicker: some View {
        HStack(spacing: 4) {
            ForEach(AnatomySide.allCases) { side in
                Button {
                    withAnimation(.snappy) {
                        selectedSide = side
                    }
                } label: {
                    HStack(spacing: 6) {
                        Text(side.title)
                        if side.activeCount(in: scores) > 0 {
                            Text("\(side.activeCount(in: scores))")
                                .font(.caption2.monospacedDigit().weight(.bold))
                                .foregroundStyle(selectedSide == side ? .white : TodayPalette.muscle)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(
                                    selectedSide == side
                                        ? Color.white.opacity(0.22)
                                        : TodayPalette.muscle.opacity(0.12),
                                    in: Capsule()
                                )
                        }
                    }
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(selectedSide == side ? .white : .secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background(
                        selectedSide == side ? TodayPalette.accent : Color.clear,
                        in: RoundedRectangle(cornerRadius: 11)
                    )
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Show \(side.title.lowercased()) muscle map")
                .accessibilityAddTraits(selectedSide == side ? .isSelected : [])
            }
        }
        .padding(4)
        .background(Color(.tertiarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14))
    }

    @ViewBuilder
    private var muscleSummary: some View {
        let visible = selectedSide.activeMuscles(in: scores)
        if visible.isEmpty {
            Text(activeMuscles.isEmpty
                 ? "Complete a set to light up the muscles you hit."
                 : "Switch sides to see the muscles you hit.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        } else {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 7) {
                    ForEach(visible) { muscle in
                        HStack(spacing: 5) {
                            Circle()
                                .fill(TodayPalette.muscle)
                                .frame(width: 6, height: 6)
                            Text(muscle.title)
                        }
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(TodayPalette.muscle)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 6)
                        .background(TodayPalette.muscle.opacity(0.09), in: Capsule())
                    }
                }
                .padding(.horizontal, 1)
            }
            .accessibilityLabel("Muscles trained on the \(selectedSide.title.lowercased()): \(visible.map(\.title).joined(separator: ", "))")
        }
    }
}

private enum AnatomySide: String, CaseIterable, Identifiable {
    case front
    case back

    var id: Self { self }
    var title: String { rawValue.capitalized }
    var baseAsset: String { self == .front ? "MuscleFrontBase" : "MuscleBackBase" }

    var overlays: [AnatomyOverlay] {
        switch self {
        case .front:
            [
                AnatomyOverlay(asset: "MuscleFrontUpperChest", muscles: [.upperChest]),
                AnatomyOverlay(asset: "MuscleFrontMiddleChest", muscles: [.middleChest]),
                AnatomyOverlay(asset: "MuscleFrontLowerChest", muscles: [.lowerChest]),
                AnatomyOverlay(asset: "MuscleFrontDeltoids", muscles: [.frontDelts, .sideDelts]),
                AnatomyOverlay(asset: "MuscleFrontBicepsLongHead", muscles: [.bicepsLongHead]),
                AnatomyOverlay(asset: "MuscleFrontBicepsShortHead", muscles: [.bicepsShortHead]),
                AnatomyOverlay(asset: "MuscleFrontBiceps", muscles: [.brachialis]),
                AnatomyOverlay(asset: "MuscleFrontForearm", muscles: [.forearms]),
                AnatomyOverlay(asset: "MuscleFrontAbs", muscles: [.rectusAbdominis]),
                AnatomyOverlay(asset: "MuscleFrontObliques", muscles: [.obliques]),
                AnatomyOverlay(asset: "MuscleFrontAdductors", muscles: [.adductors]),
                AnatomyOverlay(asset: "MuscleFrontRectusFemoris", muscles: [.rectusFemoris]),
                AnatomyOverlay(asset: "MuscleFrontVastusLateralis", muscles: [.vastusLateralis]),
                AnatomyOverlay(asset: "MuscleFrontVastusMedialis", muscles: [.vastusMedialis]),
                AnatomyOverlay(asset: "MuscleFrontTibialis", muscles: [.tibialisAnterior]),
            ]
        case .back:
            [
                AnatomyOverlay(asset: "MuscleBackDeltoids", muscles: [.rearDelts]),
                AnatomyOverlay(asset: "MuscleBackUpperBack", muscles: [.lats, .rhomboids]),
                AnatomyOverlay(asset: "MuscleBackTrapezius", muscles: [.upperTraps, .middleTraps, .lowerTraps]),
                AnatomyOverlay(asset: "MuscleBackTricepsLongHead", muscles: [.tricepsLongHead]),
                AnatomyOverlay(asset: "MuscleBackTricepsLateralHead", muscles: [.tricepsLateralHead]),
                AnatomyOverlay(asset: "MuscleBackTricepsMedialHead", muscles: [.tricepsMedialHead]),
                AnatomyOverlay(asset: "MuscleBackForearm", muscles: [.forearms]),
                AnatomyOverlay(asset: "MuscleBackLowerBack", muscles: [.lowerBack]),
                AnatomyOverlay(asset: "MuscleBackGluteMax", muscles: [.gluteMax]),
                AnatomyOverlay(asset: "MuscleBackGluteMed", muscles: [.gluteMed, .abductors]),
                AnatomyOverlay(asset: "MuscleBackHamstring", muscles: [.hamstrings]),
                AnatomyOverlay(asset: "MuscleBackGastrocnemius", muscles: [.gastrocnemius]),
                AnatomyOverlay(asset: "MuscleBackSoleus", muscles: [.soleus]),
            ]
        }
    }

    func activeMuscles(in scores: [MuscleGroup: Double]) -> [MuscleGroup] {
        let visible = Set(overlays.flatMap(\.muscles))
        return scores
            .filter { $0.value > 0 && visible.contains($0.key) }
            .sorted { $0.value > $1.value }
            .map(\.key)
    }

    func activeCount(in scores: [MuscleGroup: Double]) -> Int {
        activeMuscles(in: scores).count
    }

    func totalScore(in scores: [MuscleGroup: Double]) -> Double {
        activeMuscles(in: scores).reduce(0) { $0 + (scores[$1] ?? 0) }
    }
}

private struct AnatomyOverlay: Identifiable {
    let asset: String
    let muscles: [MuscleGroup]

    var id: String { asset }

    func score(in scores: [MuscleGroup: Double]) -> Double {
        muscles.map { scores[$0] ?? 0 }.max() ?? 0
    }
}

private struct AnatomyFigure: View {
    let side: AnatomySide
    let scores: [MuscleGroup: Double]

    var body: some View {
        ZStack {
            Image(side.baseAsset)
                .resizable()
                .scaledToFit()

            ForEach(side.overlays) { overlay in
                let score = overlay.score(in: scores)
                if score > 0 {
                    Image(overlay.asset)
                        .resizable()
                        .scaledToFit()
                        .opacity(min(1, 0.66 + score / 8))
                        .shadow(color: TodayPalette.muscle.opacity(0.25), radius: 3)
                }
            }
        }
        .aspectRatio(0.5, contentMode: .fit)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityHidden(true)
    }
}

#Preview {
    MuscleMapView(scores: [
        .upperChest: 2,
        .middleChest: 3,
        .frontDelts: 1,
        .bicepsLongHead: 2,
        .bicepsShortHead: 1,
        .rectusAbdominis: 2,
        .rectusFemoris: 3,
        .vastusLateralis: 2,
        .vastusMedialis: 1,
    ])
    .padding()
}
