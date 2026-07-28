import Link from "next/link";

const links = [
  ["Training", "/training"],
  ["Science", "/science"],
  ["Sleep demo", "/recap"],
  ["Privacy", "/privacy"],
] as const;

export function SiteHeader() {
  return (
    <header className="site-header">
      <Link className="brand" href="/" aria-label="Today home">
        <span className="brand-mark" aria-hidden="true">
          T
        </span>
        <span>Today</span>
      </Link>
      <nav className="site-nav" aria-label="Primary navigation">
        {links.map(([label, href]) => (
          <Link href={href} key={href}>
            {label}
          </Link>
        ))}
      </nav>
      <a className="header-source" href="https://github.com/RohanSi4/today-fitness-ios">
        Source <span aria-hidden="true">↗</span>
      </a>
    </header>
  );
}

