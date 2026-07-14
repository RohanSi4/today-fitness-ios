import type { MovementMetric } from "@/lib/recaps";

type MovementListProps = {
  metrics: MovementMetric[];
};

export function MovementList({ metrics }: MovementListProps) {
  return (
    <section className="movement" aria-labelledby="movement-heading">
      <h3 id="movement-heading"><span aria-hidden="true">↗</span> Movement</h3>
      {metrics.map((metric) => (
        <article className="phone-card movement-row" key={metric.label}>
          <span className={`movement-icon ${metric.tone}`} aria-hidden="true">{metric.icon}</span>
          <div className="movement-copy">
            <div><strong>{metric.label}</strong><strong>{metric.value}</strong></div>
            <p>{metric.delta}<span>{metric.average}</span></p>
            <div className="progress" aria-hidden="true"><span className={metric.tone} style={{ width: `${metric.progress}%` }} /></div>
          </div>
        </article>
      ))}
    </section>
  );
}
