import SwiftUI

enum EvidenceConfidence: String, CaseIterable {
    case strong = "Strong"
    case moderate = "Moderate"
    case emerging = "Emerging"
    case heuristic = "App heuristic"

    var tint: Color {
        switch self {
        case .strong: TodayPalette.accent
        case .moderate: .blue
        case .emerging: TodayPalette.warm
        case .heuristic: .secondary
        }
    }
}

struct FitnessResearchSource: Identifiable {
    let id: String
    let title: String
    let citation: String
    let url: URL
}

struct FitnessEvidenceClaim: Identifiable {
    let id: String
    let topic: String
    let title: String
    let summary: String
    let application: String
    let limits: String
    let confidence: EvidenceConfidence
    let symbol: String
    let sourceIDs: [String]
}

enum FitnessEvidence {
    static let reviewedAt = "July 2026"

    static let sources: [FitnessResearchSource] = [
        .init(
            id: "acsm-2026",
            title: "Resistance Training Prescription for Muscle Function, Hypertrophy, and Physical Performance",
            citation: "ACSM position stand · Medicine & Science in Sports & Exercise · 2026",
            url: URL(string: "https://doi.org/10.1249/MSS.0000000000003897")!
        ),
        .init(
            id: "dose-2026",
            title: "The Resistance Training Dose Response",
            citation: "Pelland et al. · Sports Medicine · 2026",
            url: URL(string: "https://doi.org/10.1007/s40279-025-02344-w")!
        ),
        .init(
            id: "frequency-2026",
            title: "Impact of Resistance Training Frequency on Physiological and Performance Adaptations",
            citation: "Tao et al. · International Journal of Sports Science & Coaching · 2026",
            url: URL(string: "https://doi.org/10.1177/17479541261428779")!
        ),
        .init(
            id: "split-2024",
            title: "Efficacy of Split Versus Full-Body Resistance Training",
            citation: "Ramos-Campo et al. · Journal of Strength and Conditioning Research · 2024",
            url: URL(string: "https://pubmed.ncbi.nlm.nih.gov/38595233/")!
        ),
        .init(
            id: "failure-2026",
            title: "Failure Versus Non-Failure Resistance Training",
            citation: "Systematic review and meta-analysis · 2026",
            url: URL(string: "https://pubmed.ncbi.nlm.nih.gov/42410632/")!
        ),
        .init(
            id: "proximity-2024",
            title: "Proximity to Failure, Strength Gain, and Muscle Hypertrophy",
            citation: "Robinson et al. · Sports Medicine · 2024",
            url: URL(string: "https://doi.org/10.1007/s40279-024-02069-2")!
        ),
        .init(
            id: "rest-2024",
            title: "Inter-Set Rest Interval Duration and Muscle Hypertrophy",
            citation: "Singer et al. · Frontiers in Sports and Active Living · 2024",
            url: URL(string: "https://doi.org/10.3389/fspor.2024.1429789")!
        ),
        .init(
            id: "load-2023",
            title: "Resistance Training Prescription for Strength and Hypertrophy",
            citation: "Currier et al. · British Journal of Sports Medicine · 2023",
            url: URL(string: "https://doi.org/10.1136/bjsports-2023-106807")!
        ),
        .init(
            id: "concurrent-2022",
            title: "Concurrent Aerobic and Strength Training and Muscle Fiber Hypertrophy",
            citation: "Systematic review and meta-analysis · Sports Medicine · 2022",
            url: URL(string: "https://pmc.ncbi.nlm.nih.gov/articles/PMC9474354/")!
        ),
        .init(
            id: "protein-2018",
            title: "Protein Supplementation and Resistance-Training Adaptations",
            citation: "Morton et al. · British Journal of Sports Medicine · 2018",
            url: URL(string: "https://pubmed.ncbi.nlm.nih.gov/28698222/")!
        ),
        .init(
            id: "creatine-2024",
            title: "Creatine, Resistance Training, and Strength Gains in Adults Under 50",
            citation: "Wang et al. · Nutrients · 2024",
            url: URL(string: "https://pubmed.ncbi.nlm.nih.gov/39519498/")!
        ),
        .init(
            id: "sleep-2025",
            title: "Sleep Loss or Sleep Deprivation and Muscle Strength",
            citation: "Systematic review · Sleep and Breathing · 2025",
            url: URL(string: "https://pubmed.ncbi.nlm.nih.gov/40663194/")!
        ),
    ]

    static let claims: [FitnessEvidenceClaim] = [
        .init(
            id: "weekly-volume",
            topic: "Training dose",
            title: "Weekly hard sets matter, with diminishing returns",
            summary: "More weekly resistance-training volume generally predicts more hypertrophy, but each additional set is expected to add less than the one before it.",
            application: "Today starts your routine at a recoverable dose and treats extra sets as an experiment earned by multi-week performance—not an automatic upgrade.",
            limits: "There is no universal minimum effective or maximum recoverable volume. Today’s muscle-exposure estimates use exercise mappings and are not a biological measurement.",
            confidence: .strong,
            symbol: "chart.bar.fill",
            sourceIDs: ["dose-2026", "acsm-2026"]
        ),
        .init(
            id: "frequency-split",
            topic: "Frequency",
            title: "Frequency distributes work; the split is a delivery choice",
            summary: "When weekly volume is comparable, higher frequency and full-body routines do not show a clear hypertrophy advantage over lower frequency or split routines.",
            application: "Upper / Lower remains a strong fit because it reaches muscles repeatedly while leaving room for running and recovery.",
            limits: "Frequency can still improve session quality, adherence, and schedule fit. Those practical effects matter even when its independent hypertrophy effect is small.",
            confidence: .strong,
            symbol: "calendar.badge.clock",
            sourceIDs: ["frequency-2026", "split-2024", "dose-2026"]
        ),
        .init(
            id: "rep-range",
            topic: "Loading",
            title: "There is no single hypertrophy rep range",
            summary: "Muscle can grow across a broad loading range when sets are sufficiently effortful. Heavier loads retain an advantage for load-specific maximal strength.",
            application: "Today uses lower reps on stable, loadable movements and moderate-to-higher reps where joints, technique, or setup make very heavy work inefficient.",
            limits: "Evidence is thinner at true extremes. A practical range is not proof that every repetition count is equally comfortable or fatigue-efficient.",
            confidence: .strong,
            symbol: "arrow.left.and.right",
            sourceIDs: ["acsm-2026", "load-2023"]
        ),
        .init(
            id: "failure",
            topic: "Effort",
            title: "Momentary failure is an option, not a requirement",
            summary: "Training closer to failure is generally more stimulative than stopping very early, but repeated momentary failure has not shown a reliable hypertrophy advantage over hard non-failure training.",
            application: "Today keeps failure most defensible on stable machines and isolation work, while recommending a small buffer on squats, hinges, and other fatigue-heavy lifts.",
            limits: "The exact best RIR is unresolved, RIR estimates are noisy, and results depend on exercise, load, volume, and the lifter’s experience.",
            confidence: .moderate,
            symbol: "gauge.with.dots.needle.67percent",
            sourceIDs: ["failure-2026", "proximity-2024"]
        ),
        .init(
            id: "rest",
            topic: "Set quality",
            title: "Rest long enough to preserve useful work",
            summary: "Longer rests probably offer a small hypertrophy advantage over very short rests by preserving repetitions and load across sets.",
            application: "Today gives compounds longer rest ranges than isolation work and treats breathing, technique, and rep loss as reasons to wait longer.",
            limits: "The evidence does not identify one perfect timer. Antagonist supersets and individual recovery can change the practical answer.",
            confidence: .moderate,
            symbol: "timer",
            sourceIDs: ["rest-2024", "acsm-2026"]
        ),
        .init(
            id: "concurrent-training",
            topic: "Running + lifting",
            title: "Running and hypertrophy can coexist, but fatigue placement matters",
            summary: "Concurrent endurance and resistance training can support both goals, although high running stress may attenuate some muscle-fiber growth compared with lifting alone.",
            application: "Today separates demanding lower-body lifting from key runs where possible and avoids solving interference by simply removing leg training.",
            limits: "Interference varies with running dose, training status, nutrition, scheduling, and the outcome measured. This is not a reason to fear normal aerobic work.",
            confidence: .moderate,
            symbol: "figure.run",
            sourceIDs: ["concurrent-2022"]
        ),
        .init(
            id: "nutrition",
            topic: "Nutrition",
            title: "Protein and creatine are supported; neither replaces training",
            summary: "Protein intake around 1.6 g/kg/day captures most average resistance-training benefit, while creatine paired with training can improve strength and lean-mass outcomes.",
            application: "Today treats these as high-value fundamentals to discuss, not as required supplements or a substitute for adequate food, progressive training, and sleep.",
            limits: "Protein needs vary with energy intake and goals. Creatine changes water content and body mass; supplement quality and individual medical context still matter.",
            confidence: .strong,
            symbol: "fork.knife",
            sourceIDs: ["protein-2018", "creatine-2024"]
        ),
        .init(
            id: "sleep",
            topic: "Recovery",
            title: "Sleep is context, not a readiness verdict",
            summary: "Sleep loss can impair strength and performance, but a consumer sleep estimate cannot determine whether you are recovered from one score alone.",
            application: "Today compares your sleep with your own recent baseline and keeps the result descriptive. Training decisions should also consider performance, soreness, illness, and life stress.",
            limits: "Today’s 0–100 sleep signal is an app heuristic, not a validated clinical or recovery score. Direct evidence connecting one night’s wearable data to hypertrophy decisions is limited.",
            confidence: .moderate,
            symbol: "moon.stars.fill",
            sourceIDs: ["sleep-2025"]
        ),
    ]

    static func sources(for claim: FitnessEvidenceClaim) -> [FitnessResearchSource] {
        claim.sourceIDs.compactMap { id in sources.first { $0.id == id } }
    }
}

struct EvidenceBadge: View {
    let confidence: EvidenceConfidence

    var body: some View {
        Text(confidence.rawValue)
            .font(.caption2.weight(.bold))
            .foregroundStyle(confidence.tint)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(confidence.tint.opacity(0.11), in: Capsule())
            .accessibilityLabel("Evidence confidence: \(confidence.rawValue)")
    }
}

struct ResearchLibraryView: View {
    var body: some View {
        ScrollView {
            LazyVStack(spacing: 14) {
                evidenceHero
                heuristicNote
                ForEach(FitnessEvidence.claims) { claim in
                    EvidenceClaimCard(claim: claim)
                }
            }
            .padding(16)
            .padding(.bottom, 28)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Evidence guide")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var evidenceHero: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top) {
                Image(systemName: "books.vertical.fill")
                    .font(.title2)
                    .foregroundStyle(.white)
                    .frame(width: 46, height: 46)
                    .background(.white.opacity(0.16), in: RoundedRectangle(cornerRadius: 14))
                Spacer()
                Text("REVIEWED \(FitnessEvidence.reviewedAt.uppercased())")
                    .font(.caption2.weight(.bold))
                    .tracking(0.8)
                    .foregroundStyle(.white.opacity(0.72))
            }
            Text("What Today knows—and what it doesn’t")
                .font(.title2.weight(.bold))
                .foregroundStyle(.white)
            Text("Every training claim carries a confidence level, a practical use, and its limits. New evidence can change the defaults without rewriting your history.")
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.82))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(20)
        .background(
            LinearGradient(
                colors: [Color(red: 0.05, green: 0.22, blue: 0.15), TodayPalette.accent],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            in: RoundedRectangle(cornerRadius: 26, style: .continuous)
        )
        .shadow(color: TodayPalette.accent.opacity(0.16), radius: 18, y: 9)
    }

    private var heuristicNote: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "waveform.path.ecg.rectangle")
                .foregroundStyle(TodayPalette.warm)
            VStack(alignment: .leading, spacing: 4) {
                Text("Measured, estimated, and interpreted are different")
                    .font(.subheadline.weight(.semibold))
                Text("Loads, reps, body weight, and HealthKit samples are measurements. Muscle exposure, sleep signals, and coaching copy are estimates or interpretations and are labeled accordingly.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(16)
        .todayCard()
    }
}

private struct EvidenceClaimCard: View {
    let claim: FitnessEvidenceClaim
    @State private var isExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label(claim.topic, systemImage: claim.symbol)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(TodayPalette.accent)
                Spacer()
                EvidenceBadge(confidence: claim.confidence)
            }

            Text(claim.title)
                .font(.headline)
            Text(claim.summary)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: 4) {
                Text("HOW TODAY USES IT")
                    .font(.caption2.weight(.bold))
                    .tracking(0.7)
                    .foregroundStyle(.tertiary)
                Text(claim.application)
                    .font(.caption)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Button {
                withAnimation(.snappy) { isExpanded.toggle() }
            } label: {
                HStack {
                    Text(isExpanded ? "Hide limits and sources" : "Limits and sources")
                    Spacer()
                    Image(systemName: "chevron.down")
                        .font(.caption.weight(.bold))
                        .rotationEffect(.degrees(isExpanded ? 180 : 0))
                }
                .font(.caption.weight(.semibold))
                .foregroundStyle(TodayPalette.accent)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if isExpanded {
                VStack(alignment: .leading, spacing: 10) {
                    Text(claim.limits)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    ForEach(FitnessEvidence.sources(for: claim)) { source in
                        Link(destination: source.url) {
                            HStack(alignment: .top, spacing: 8) {
                                Image(systemName: "arrow.up.right.square")
                                    .padding(.top, 1)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(source.title)
                                        .font(.caption.weight(.semibold))
                                    Text(source.citation)
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }
                .padding(12)
                .background(Color(.tertiarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14))
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .todayCard()
    }
}

#Preview {
    NavigationStack { ResearchLibraryView() }
}
