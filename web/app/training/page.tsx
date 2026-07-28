import type { Metadata } from "next";
import Link from "next/link";
import { SiteFooter } from "@/components/site-footer";

export const metadata: Metadata = {
  title: "Training",
  description: "How Today structures hypertrophy training, progression, and fatigue context.",
};

const sessions = [
  { name: "Upper A", tone: "red", exercises: "Incline press · T-bar row · Pec deck · Pulldown · Delts · Triceps · Biceps" },
  { name: "Lower A", tone: "orange", exercises: "Hack squat · Romanian deadlift · Leg extension · Leg curl · Calves · Abs" },
  { name: "Upper B", tone: "green", exercises: "Pulldown · Pec deck · Cable row · Delts · Triceps · Bayesian curl · Rear delts" },
  { name: "Lower B", tone: "blue", exercises: "Leg press · Hip hinge · Split squat · Leg curl · Calves · Abs" },
];

export default function TrainingPage() {
  return (
    <main>
      <section className="page-hero shell compact-hero">
        <p className="eyebrow">The current training system</p>
        <h1>Built for hypertrophy.<br />Designed to evolve.</h1>
        <p className="hero-lede">An upper/lower starting structure matched to the equipment you actually use. Exercise prescriptions are defaults; logged performance is what earns the next adjustment.</p>
      </section>

      <section className="shell session-grid" aria-label="Four day upper lower training plan">
        {sessions.map((session, index) => (
          <article className="session-card" key={session.name}>
            <span className={`session-number ${session.tone}`}>{String(index + 1).padStart(2, "0")}</span>
            <div><h2>{session.name}</h2><p>{session.exercises}</p></div>
          </article>
        ))}
      </section>

      <section className="shell programming-grid">
        <div className="section-heading sticky-heading"><p className="eyebrow">Programming defaults</p><h2>Simple rules, honestly framed.</h2><p>These ranges make quality work practical. They are not magic hypertrophy zones.</p></div>
        <div className="rule-list">
          <article><span>Stable compounds</span><strong>5–10 reps · 2–3 RIR · 3–5 min</strong><p>Use enough rest to preserve technique and output. Add reps before load.</p></article>
          <article><span>Machine compounds</span><strong>6–10 reps · 1–2 RIR · 2–4 min</strong><p>Stable loading makes lower reps practical without making them uniquely anabolic.</p></article>
          <article><span>Most isolations</span><strong>8–15 reps · 0–2 RIR · 90 sec–3 min</strong><p>Failure can be used selectively when the movement is stable and recovery cost is manageable.</p></article>
          <article><span>Delts and small isolations</span><strong>10–20 reps · 0–2 RIR · 90 sec–3 min</strong><p>Choose the range that keeps the target muscle and joint comfort consistent.</p></article>
          <article><span>Progression</span><strong>Reps first, then load</strong><p>Reach the top of the range across comparable sets, then take the smallest available increase.</p></article>
        </div>
      </section>

      <section className="shell decision-band">
        <div><span className="level level-moderate">Personalization loop</span><h2>The program is a hypothesis.</h2></div>
        <div><p>Today watches what you completed, how performance moved, and how much estimated regional work accumulated. Add volume gradually only when performance, recovery, and motivation support it.</p><Link href="/science">See why these rules exist →</Link></div>
      </section>
      <SiteFooter />
    </main>
  );
}

