import { RecapDemo } from "@/components/recap-demo";

export default function Home() {
  return (
    <main>
      <header className="site-header">
        <a className="brand" href="#top" aria-label="Health Recap home">
          <span className="brand-mark" aria-hidden="true">H</span>
          <span>Health Recap</span>
        </a>
        <a className="text-link" href="https://github.com/RohanSi4/today-fitness-ios">
          View the iOS source
          <span aria-hidden="true">↗</span>
        </a>
      </header>

      <section className="intro" id="top">
        <div className="intro-copy">
          <p className="eyebrow">A calmer way to read Apple Health</p>
          <h1>Your sleep and movement, without the spreadsheet feeling.</h1>
          <p className="lede">
            Health Recap turns last night and today into one useful check-in. It shows what changed,
            what matters, and when an easier day may be the right call.
          </p>
          <div className="privacy-note">
            <span className="privacy-icon" aria-hidden="true">✓</span>
            <span><strong>Private by design.</strong> The iPhone app reads HealthKit on-device. Nothing is uploaded.</span>
          </div>
        </div>
        <dl className="build-notes" aria-label="Product details">
          <div><dt>Platform</dt><dd>SwiftUI + HealthKit</dd></div>
          <div><dt>Focus</dt><dd>Sleep + daily movement</dd></div>
          <div><dt>Baseline</dt><dd>Previous 7 days</dd></div>
        </dl>
      </section>

      <RecapDemo />

      <section className="how-it-works" aria-labelledby="how-heading">
        <div>
          <p className="eyebrow">Under the hood</p>
          <h2 id="how-heading">The useful part is the interpretation.</h2>
        </div>
        <div className="principles">
          <article>
            <span>01</span>
            <h3>Clean the signal</h3>
            <p>Overlapping sleep stages are merged so the same minutes never count twice.</p>
          </article>
          <article>
            <span>02</span>
            <h3>Keep comparisons fair</h3>
            <p>Today is compared with the seven full days before it, not a baseline that includes itself.</p>
          </article>
          <article>
            <span>03</span>
            <h3>Say it plainly</h3>
            <p>The strongest sleep and movement changes become one short takeaway, not another chart to decode.</p>
          </article>
        </div>
      </section>

      <footer>
        <p>Built by Rohan Singh as an iOS health-data project.</p>
        <p>This browser demo uses sample data and does not connect to Apple Health.</p>
      </footer>
    </main>
  );
}
