import Link from "next/link";

export function SiteFooter() {
  return (
    <footer className="site-footer">
      <div>
        <span className="footer-mark" aria-hidden="true">T</span>
        <p><strong>Today</strong><br />A focused training and health companion.</p>
      </div>
      <div className="footer-links">
        <Link href="/science">Evidence guide</Link>
        <Link href="/privacy">Privacy</Link>
        <a href="https://github.com/RohanSi4/today-fitness-ios">GitHub</a>
      </div>
      <p className="footer-note">Personal build · Open source<br />Not medical advice.</p>
    </footer>
  );
}

