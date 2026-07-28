import type { Metadata } from "next";
import { SiteFooter } from "@/components/site-footer";

export const metadata: Metadata = { title: "Privacy", description: "The exact data boundaries in Today." };

const rows = [
  ["HealthKit sleep and movement", "Read with iOS permission", "On your iPhone", "Never sold or used for ads"],
  ["Workout logs and body weight", "Created by you", "On your iPhone", "Remains local by default"],
  ["Apple Watch workout data", "Written with permission", "HealthKit", "Controlled through Apple Health permissions"],
  ["Coach connection", "Only after explicit setup", "Encrypted sync", "Optional and disconnectable"],
  ["Browser sleep demo", "Sample values only", "In your browser", "Never connects to HealthKit"],
] as const;

export default function PrivacyPage() {
  return (
    <main>
      <section className="page-hero shell compact-hero"><p className="eyebrow">Privacy, in plain language</p><h1>Your data is not<br />the business model.</h1><p className="hero-lede">Today is a personal, open-source build. Health and workout data stay on your devices by default, and optional sharing requires a deliberate connection.</p></section>
      <section className="shell privacy-table" aria-label="Today data boundaries">
        <div className="privacy-row privacy-head"><span>Data</span><span>Access</span><span>Default location</span><span>Boundary</span></div>
        {rows.map((row) => <div className="privacy-row" key={row[0]}>{row.map((cell, index) => <span data-label={rows[0][index]} key={cell}>{cell}</span>)}</div>)}
      </section>
      <section className="shell privacy-principles"><article><span>01</span><h2>Permissioned</h2><p>You choose which Apple Health types the app can read or write and can revoke them in iOS Settings.</p></article><article><span>02</span><h2>Minimal</h2><p>The product asks for data that supports its training, sleep, movement, and workout-history features.</p></article><article><span>03</span><h2>Explicit sharing</h2><p>Coach sync is not the default path. It requires setup and clearly changes where selected data can travel.</p></article></section>
      <SiteFooter />
    </main>
  );
}

