"use client";

import { useState } from "react";
import { MovementList } from "@/components/movement-list";
import { ScoreRing } from "@/components/score-ring";
import { SleepDetails } from "@/components/sleep-details";
import { recaps } from "@/lib/recaps";

export function RecapDemo() {
  const [activeIndex, setActiveIndex] = useState(1);
  const recap = recaps[activeIndex];

  return (
    <section className="demo-section" aria-labelledby="demo-heading">
      <div className="demo-copy">
        <p className="eyebrow">Try the recap</p>
        <h2 id="demo-heading">Three days. Three different stories.</h2>
        <p>Switch days to see how the same health signals turn into a different, useful takeaway.</p>
        <div className="day-picker" role="group" aria-label="Choose a sample day">
          {recaps.map((day, index) => (
            <button
              aria-pressed={index === activeIndex}
              className={index === activeIndex ? "active" : ""}
              key={day.id}
              onClick={() => setActiveIndex(index)}
              type="button"
            >
              <span>{day.shortDay}</span>
              <strong>{13 + index}</strong>
            </button>
          ))}
        </div>
        <div className="demo-disclosure">
          <span aria-hidden="true">●</span>
          Interactive sample data
        </div>
        <p className="disclosure-copy">The browser demo mirrors the native app’s sample-data path. Only the iPhone app can request access to Apple Health.</p>
      </div>

      <div className="device-wrap">
        <div className="device" aria-live="polite">
          <div className="device-bar"><span>9:41</span><span className="dynamic-island" /><span aria-hidden="true">● ◔</span></div>
          <div className="app-bar"><span>Health Recap</span><button type="button" aria-label="Demo options" disabled>•••</button></div>
          <div className="sample-pill"><span aria-hidden="true">✦</span><span><strong>Sample data</strong> Private demo day</span></div>

          <article className="hero-card">
            <div className="hero-top"><span><small>DAILY RECAP</small><strong>{recap.date}</strong></span><span aria-hidden="true">☾</span></div>
            <div className="hero-main">
              <ScoreRing score={recap.score} />
              <div>
                <h3>{recap.status}</h3>
                <p>You slept {recap.sleep} with {recap.efficiency} efficiency.</p>
                <strong>↗ {recap.comparison}</strong>
              </div>
            </div>
          </article>

          <article className="phone-card takeaway">
            <span className="takeaway-icon" aria-hidden="true">✦</span>
            <div><h3>Today’s takeaway</h3><p>{recap.insight}</p></div>
          </article>

          <SleepDetails recap={recap} />
          <MovementList metrics={recap.movement} />
        </div>
      </div>
    </section>
  );
}
