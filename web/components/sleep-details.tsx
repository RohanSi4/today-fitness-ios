import type { Recap } from "@/lib/recaps";

type SleepDetailsProps = {
  recap: Recap;
};

export function SleepDetails({ recap }: SleepDetailsProps) {
  const metrics = [
    { label: "Time asleep", value: recap.sleep, note: "7-day avg 6h 42m", icon: "☾" },
    { label: "Efficiency", value: recap.efficiency, note: "7-day avg 93%", icon: "◔" },
    { label: "Bedtime", value: recap.bedtime, note: "Near your average", icon: "⌂" },
    { label: "Wake time", value: recap.wakeTime, note: "10m earlier than average", icon: "☼" },
  ];

  return (
    <section className="phone-card sleep-details" aria-labelledby="sleep-heading">
      <h3 id="sleep-heading"><span aria-hidden="true">☾</span> Sleep details</h3>
      <div className="metric-grid">
        {metrics.map((metric) => (
          <div className="metric-tile" key={metric.label}>
            <span className="metric-icon" aria-hidden="true">{metric.icon}</span>
            <span>{metric.label}</span>
            <strong>{metric.value}</strong>
            <small>{metric.note}</small>
          </div>
        ))}
      </div>
      <div className="time-in-bed"><span>Time in bed</span><strong>{recap.timeInBed}</strong></div>
    </section>
  );
}
