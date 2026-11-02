function WindowsLogo() {
  return (
    <svg viewBox="0 0 20 20" className="logo-glyph" aria-hidden>
      <path d="M0 2.8 8.2 1.7v7.9H0zM9.2 1.5 20 0v9.6H9.2zM0 10.5h8.2v7.9L0 17.2zM9.2 10.5H20V20L9.2 18.5z" />
    </svg>
  );
}

/** The way to the Mac install line, and Windows marked as not there yet. */
export function InstallButtons() {
  return (
    <div className="downloads">
      <a className="button primary" href="#install">
        Install for Mac
      </a>
      <button type="button" className="button glass-button" disabled aria-disabled="true">
        <WindowsLogo />
        Windows
        <span className="soon">Coming soon</span>
      </button>
    </div>
  );
}
