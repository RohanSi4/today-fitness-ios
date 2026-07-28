import Link from "next/link";
import { SiteFooter } from "@/components/site-footer";
import { evidenceClaims } from "@/lib/evidence";

const pulseRows = [
  ["Chest", "7.1", "82%"],
  ["Back", "6.6", "76%"],
  ["Delts", "5.2", "60%"],
  ["Arms", "4.4", "51%"],
] as const;

export default function Home() {
  return (
    <main>
      <section className="home-hero shell">
        <div className="hero-copy">
          <p className="eyebrow">Training, health, and the signal between them</p>
          <h1>Train with context.</h1>
          <p className="hero-lede">
            Today puts the next useful action first: run the plan, log cleanly, then learn from
            training history without pretending every estimate is a measurement.
          </p>
          <div className="hero-actions">
            <Link className="button button-primary" href="/training">Explore the training system</Link>
            <Link className="button button-secondary" href="/science">Read the evidence guide</Link>
          </div>
          <div className="trust-line">
            <span>iPhone + Apple Watch</span>
            <span>HealthKit on-device</span>
            <span>Optional coach sync</span>
          </div>
        </div>

        <div className="app-preview" aria-label="Illustration of the Today app training pulse">
          <div className="preview-topline"><span>9:41</span><span className="preview-island" /><span>● ◔</span></div>
          <div className="preview-greeting"><span>Tuesday</span><strong>Upper A is ready.</strong></div>
          <article className="preview-workout">
            <div><span className="preview-status">TODAY&apos;S WORKOUT</span><h2>Upper A</h2><p>7 exercises · Hypertrophy</p></div>
            <span className="preview-play" aria-hidden="true">▶</span>
          </article>
          <article className="preview-card">
            <div className="preview-card-title"><div><span className="preview-icon red">↗</span><strong>Training pulse</strong></div><span>7 days</span></div>
            <div className="preview-stats"><div><strong>4</strong><span>sessions</span></div><div><strong>31</strong><span>hard sets</span></div><div><strong>8</strong><span>regions</span></div></div>
            <div className="pulse-list">
              {pulseRows.map(([name, value, width]) => (
                <div className="pulse-row" key={name}>
                  <span>{name}</span><div><i style={{ width }} /></div><strong>{value}</strong>
                </div>
              ))}
            </div>
            <p className="preview-disclaimer">Estimated set exposure—not activation, recovery, or growth.</p>
          </article>
          <nav className="preview-tabs" aria-hidden="true"><span className="active">Today</span><span>Workout</span><span>History</span><span>Insights</span></nav>
        </div>
      </section>

      <section className="dark-section">
        <div className="shell product-flow">
          <div className="section-heading light-heading">
            <p className="eyebrow">A tighter loop</p>
            <h2>Plan. Log. Learn.</h2>
            <p>No dashboard maze. The app changes emphasis depending on what you are doing now.</p>
          </div>
          <div className="flow-grid">
            <article><span>01</span><h3>See the next move</h3><p>Your active workout comes first. Exercise order, targets, and recent performance stay close to the set you are doing.</p></article>
            <article><span>02</span><h3>Capture the work</h3><p>Fast set entry, drag-to-reorder exercises, and persistent active sessions keep logging out of the way.</p></article>
            <article><span>03</span><h3>Adjust with evidence</h3><p>Reps, load, estimated regional exposure, sleep context, and history support a decision without manufacturing certainty.</p></article>
          </div>
        </div>
      </section>

      <section className="shell evidence-preview">
        <div className="section-heading split-heading">
          <div><p className="eyebrow">Evidence, with boundaries</p><h2>Useful claims deserve visible limits.</h2></div>
          <p>Every training principle is labeled by confidence, connected to peer-reviewed research, and paired with what the app can—and cannot—infer.</p>
        </div>
        <div className="evidence-card-grid">
          {evidenceClaims.slice(0, 3).map((claim) => (
            <article className="evidence-summary" key={claim.id}>
              <span className={`level level-${claim.level.toLowerCase()}`}>{claim.level}</span>
              <h3>{claim.title}</h3>
              <p>{claim.summary}</p>
            </article>
          ))}
        </div>
        <Link className="inline-arrow" href="/science">Open the complete evidence guide <span>→</span></Link>
      </section>

      <section className="shell privacy-band">
        <div><p className="eyebrow">Private by default</p><h2>Your health data stays close.</h2></div>
        <div><p>HealthKit reads and workout history stay on iPhone by default. Coach sync is optional, encrypted, and explicitly connected.</p><Link href="/privacy">See the exact data boundaries →</Link></div>
      </section>

      <SiteFooter />
    </main>
  );
}
