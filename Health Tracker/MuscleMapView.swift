import SwiftUI

struct MuscleMapView: View {
    let scores: [MuscleGroup: Double]
    var compact = false

    private var activeMuscles: [MuscleGroup] {
        scores
            .filter { $0.value > 0 }
            .sorted { $0.value > $1.value }
            .map(\.key)
    }

    var body: some View {
        VStack(spacing: compact ? 10 : 14) {
            HStack(alignment: .bottom, spacing: compact ? 6 : 12) {
                AnatomyFigureColumn(side: .front, scores: scores)
                AnatomyFigureColumn(side: .back, scores: scores)
            }
            .frame(height: compact ? 330 : 390)

            muscleSummary
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilitySummary)
    }

    @ViewBuilder
    private var muscleSummary: some View {
        if activeMuscles.isEmpty {
            Text("Complete a set to light up the muscles you hit.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        } else {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 7) {
                    ForEach(activeMuscles) { muscle in
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
        }
    }

    private var accessibilitySummary: String {
        activeMuscles.isEmpty
            ? "No completed muscle work yet"
            : "Muscles trained: \(activeMuscles.map(\.title).joined(separator: ", "))"
    }
}

private enum AnatomySide: String {
    case front
    case back

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

private struct AnatomyFigureColumn: View {
    let side: AnatomySide
    let scores: [MuscleGroup: Double]

    var body: some View {
        VStack(spacing: 4) {
            AnatomyFigure(side: side, scores: scores)

            Text(side.title.uppercased())
                .font(.system(size: 9, weight: .bold, design: .rounded))
                .tracking(1.2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
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
