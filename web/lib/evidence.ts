export type EvidenceLevel = "Strong" | "Moderate" | "Emerging" | "Heuristic";

export type EvidenceSource = {
  title: string;
  detail: string;
  href: string;
};

export type EvidenceClaim = {
  id: string;
  level: EvidenceLevel;
  title: string;
  summary: string;
  todayUse: string;
  limit: string;
  sources: EvidenceSource[];
};

export const evidenceClaims: EvidenceClaim[] = [
  {
    id: "volume",
    level: "Strong",
    title: "Weekly hard-set volume is a useful programming lever",
    summary:
      "More weekly resistance-training volume generally produces more hypertrophy, but returns diminish and the best dose varies by muscle and lifter.",
    todayUse:
      "Today estimates recent muscle-region exposure so you can spot obvious gaps or abrupt jumps before changing a program.",
    limit:
      "A logged set is not a direct measurement of stimulus, recovery, or growth. The map is an estimate, not a verdict.",
    sources: [
      {
        title: "ACSM resistance-training prescription position stand",
        detail: "Medicine & Science in Sports & Exercise, 2026",
        href: "https://pubmed.ncbi.nlm.nih.gov/41843416/",
      },
      {
        title: "Weekly volume and frequency dose-response meta-regression",
        detail: "Sports Medicine, 2026",
        href: "https://pubmed.ncbi.nlm.nih.gov/41343037/",
      },
    ],
  },
  {
    id: "split",
    level: "Strong",
    title: "The split is a delivery system, not the growth mechanism",
    summary:
      "Full-body and split routines produce similar strength and hypertrophy when weekly volume is equated. Frequency mainly helps distribute useful work and fatigue.",
    todayUse:
      "Your upper/lower plan stays flexible. The app prioritizes completed weekly exposure over declaring one split universally optimal.",
    limit:
      "Schedule, exercise quality, recovery, and adherence can make one arrangement much better for an individual even when group averages are similar.",
    sources: [
      {
        title: "Split versus full-body resistance training meta-analysis",
        detail: "Journal of Strength and Conditioning Research, 2024",
        href: "https://pubmed.ncbi.nlm.nih.gov/38595233/",
      },
      {
        title: "Training frequency dose-response meta-analysis",
        detail: "International Journal of Sports Science & Coaching, 2026",
        href: "https://doi.org/10.1177/17479541261428779",
      },
    ],
  },
  {
    id: "loads",
    level: "Strong",
    title: "Hypertrophy is possible across a broad loading range",
    summary:
      "Muscle growth can occur with low, moderate, and high loads when sets are sufficiently effortful. Moderate rep ranges are often the most practical, not uniquely anabolic.",
    todayUse:
      "Today uses practical ranges by exercise: lower reps for stable compounds and higher reps for isolations where joint comfort and technique matter more.",
    limit:
      "Very low-load sets may require closer proximity to failure, while very heavy sets can add joint and skill demands without adding hypertrophy.",
    sources: [
      {
        title: "Resistance-training prescription network meta-analysis",
        detail: "British Journal of Sports Medicine, 2023",
        href: "https://doi.org/10.1136/bjsports-2023-106807",
      },
    ],
  },
  {
    id: "failure",
    level: "Moderate",
    title: "Failure is a tool, not a requirement",
    summary:
      "Training to momentary failure is not consistently superior for hypertrophy when effort and volume are comparable. It usually creates more acute fatigue.",
    todayUse:
      "The plan suggests leaving more reps in reserve on demanding compounds and makes failure optional on stable isolations. Your explicit failure logs remain visible as a fatigue signal.",
    limit:
      "Repetitions in reserve are subjective, especially for unfamiliar lifts. Technique failure and true momentary failure are not always the same event.",
    sources: [
      {
        title: "Failure versus non-failure resistance training",
        detail: "Systematic review and meta-analysis, 2026",
        href: "https://pubmed.ncbi.nlm.nih.gov/42410632/",
      },
      {
        title: "Proximity to failure and muscle hypertrophy",
        detail: "Sports Medicine, 2024",
        href: "https://doi.org/10.1007/s40279-024-02069-2",
      },
    ],
  },
  {
    id: "rest",
    level: "Moderate",
    title: "Rest long enough to preserve useful performance",
    summary:
      "Longer rests often help maintain repetitions and load across sets. Roughly two to four minutes on compounds and 90 seconds to three minutes on isolations are practical defaults.",
    todayUse:
      "Exercise prescriptions favor performance-preserving rest instead of treating short rest as inherently better for growth.",
    limit:
      "The right interval depends on the exercise, cardiovascular demand, training age, and whether the next set can meet its target quality.",
    sources: [
      {
        title: "Rest interval duration and hypertrophy meta-analysis",
        detail: "Frontiers in Sports and Active Living, 2024",
        href: "https://doi.org/10.3389/fspor.2024.1429789",
      },
    ],
  },
  {
    id: "sleep",
    level: "Heuristic",
    title: "Sleep context is useful; a readiness score is not a diagnosis",
    summary:
      "Sleep loss can impair performance and recovery-related outcomes, but consumer sleep estimates cannot determine whether a specific workout will be productive.",
    todayUse:
      "Today describes sleep duration and consistency as context, then asks you to combine it with soreness, motivation, illness, and warm-up performance.",
    limit:
      "The in-app sleep signal is a transparent heuristic, not a validated clinical or readiness measure.",
    sources: [
      {
        title: "Sleep loss and physical performance meta-analysis",
        detail: "Systematic review and meta-analysis, 2025",
        href: "https://pubmed.ncbi.nlm.nih.gov/40663194/",
      },
    ],
  },
];

