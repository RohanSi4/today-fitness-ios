import type { Metadata } from "next";
import { RecapDemo } from "@/components/recap-demo";
import { SiteFooter } from "@/components/site-footer";

export const metadata: Metadata = { title: "Sleep recap demo", description: "Interactive sample of Today's sleep and movement recap." };

export default function RecapPage() {
  return <main><section className="recap-intro shell"><p className="eyebrow">Interactive sample</p><h1>Sleep context,<br />not a diagnosis.</h1><p>Explore three sample days. The estimate summarizes sleep and movement; it cannot determine readiness or replace how you feel and perform.</p></section><RecapDemo /><SiteFooter /></main>;
}
