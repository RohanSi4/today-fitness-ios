import type { Metadata } from "next";
import { SiteFooter } from "@/components/site-footer";
import { evidenceClaims } from "@/lib/evidence";

export const metadata: Metadata = {
  title: "Evidence guide",
  description: "The peer-reviewed evidence, product decisions, and limits behind Today.",
};

export default function SciencePage() {
  return (
    <main>
      <section className="page-hero shell compact-hero">
        <p className="eyebrow">Evidence guide · reviewed July 2026</p>
        <h1>What we know.<br />What we estimate.</h1>
        <p className="hero-lede">Research should sharpen a decision, not decorate it. These are the claims Today uses, their confidence, and the line the product refuses to cross.</p>
      </section>
      <section className="shell evidence-list">
        {evidenceClaims.map((claim, index) => (
          <article className="evidence-detail" id={claim.id} key={claim.id}>
            <div className="evidence-index"><span>{String(index + 1).padStart(2, "0")}</span><span className={`level level-${claim.level.toLowerCase()}`}>{claim.level}</span></div>
            <div className="evidence-body">
              <h2>{claim.title}</h2>
              <p className="claim-summary">{claim.summary}</p>
              <dl><div><dt>How Today uses it</dt><dd>{claim.todayUse}</dd></div><div><dt>Boundary</dt><dd>{claim.limit}</dd></div></dl>
              <div className="source-list">
                {claim.sources.map((source) => (
                  <a href={source.href} key={source.href}><span>{source.title}<small>{source.detail}</small></span><b aria-hidden="true">↗</b></a>
                ))}
              </div>
            </div>
          </article>
        ))}
      </section>
      <section className="shell science-note"><strong>Evidence standard</strong><p>Priority goes to systematic reviews, meta-analyses, position stands, and controlled trials. Group averages guide defaults; your longitudinal data guides personalization. Today does not diagnose injury, recovery, or medical conditions.</p></section>
      <SiteFooter />
    </main>
  );
}

