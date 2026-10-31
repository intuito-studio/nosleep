import { Cat } from "@/components/Cat";
import { Copy } from "@/components/Copy";
import { AppleLogo, DownloadButtons } from "@/components/Download";
import { Hero } from "@/components/Hero";
import * as I from "@/components/Icons";
import { Playground } from "@/components/Playground";
import { BREW_LINES, DMG_URL, INSOMNIA_URL, INSTALL_LINE, REPO_URL } from "@/lib/links";
import { FAQ, jsonLd } from "@/lib/site";

const RULES: [() => React.JSX.Element, string, string][] = [
  [I.Moon, "Lid shut at the end", "Sleeps straight away."],
  [I.Battery, "Battery", "Low Power Mode below 40%. Stops at 20%, or the level you set."],
  [I.Heat, "Heat", "Low Power Mode when hot. Stops when critical."],
  [I.Power, "Quit", "Sleep back on."],
  [I.Backstop, "Crash or force quit", "A backstop puts sleep back within a minute."],
];

export default function Home() {
  return (
    <>
      <script
        type="application/ld+json"
        // Static facts from lib/site.ts, serialised at build time.
        dangerouslySetInnerHTML={{ __html: JSON.stringify(jsonLd()).replace(/</g, "\\u003c") }}
      />
      <header className="nav glass">
        <a href="#top" className="nav-brand" aria-label="NoSleep, back to top">
          <Cat awake className="nav-cat" />
          NoSleep
        </a>
        <nav aria-label="Page">
          <a href="#install">Install</a>
          <a href={REPO_URL}>GitHub</a>
          <a className="button primary small" href={DMG_URL}>
            <AppleLogo />
            Download
          </a>
        </nav>
      </header>

      <main id="top">
        <Hero />

        <section className="section" aria-labelledby="panel-title">
          <div className="section-head">
            <h2 id="panel-title">One click in the menu bar.</h2>
            <p className="lede">Flip the switch. Pick when it lets go. Try it here.</p>
          </div>
          <Playground />
        </section>

        <section className="section" aria-labelledby="lid-title">
          <div className="section-head">
            <h2 id="lid-title">Shut, it goes quiet.</h2>
            <p className="lede">Closing the lid saves power. Opening it undoes only what NoSleep changed.</p>
          </div>
          <table className="lid-table">
            <thead>
              <tr>
                <th scope="col">
                  <span className="visually-hidden">Setting</span>
                </th>
                <th scope="col">Lid closes</th>
                <th scope="col">Lid opens</th>
              </tr>
            </thead>
            <tbody>
              <tr>
                <th scope="row">
                  <span className="with-icon">
                    <I.Display />
                    Display
                  </span>
                </th>
                <td>Off</td>
                <td>On</td>
              </tr>
              <tr>
                <th scope="row">
                  <span className="with-icon">
                    <I.Sound />
                    Sound
                  </span>
                </th>
                <td>Muted</td>
                <td>Unmuted, if NoSleep muted it</td>
              </tr>
              <tr>
                <th scope="row">
                  <span className="with-icon">
                    <I.LowPower />
                    Low Power Mode
                  </span>
                </th>
                <td>On</td>
                <td>Off, if NoSleep turned it on</td>
              </tr>
              <tr>
                <th scope="row">
                  <span className="with-icon">
                    <I.Timer />
                    Timer
                  </span>
                </th>
                <td>Keeps running</td>
                <td>Keeps running</td>
              </tr>
            </tbody>
          </table>
          <p className="fine narrow">
            The built-in mic is off while the lid is shut. Record with AirPods or an external mic.
          </p>
        </section>

        <section className="band bag" aria-labelledby="safe-title">
          <div className="split section">
            <div className="section-head">
              <h2 id="safe-title">It won’t leave your Mac awake in a bag.</h2>
              <p className="lede">Every way out puts sleep back.</p>
            </div>
            <dl className="rules glass">
              {RULES.map(([Icon, title, text]) => (
                <div key={title}>
                  <dt>
                    <Icon />
                    {title}
                  </dt>
                  <dd>{text}</dd>
                </div>
              ))}
            </dl>
          </div>
        </section>

        <section className="section" id="faq" aria-labelledby="faq-title">
          <div className="section-head center">
            <h2 id="faq-title">Questions.</h2>
          </div>
          <div className="faq">
            {FAQ.map(([q, a]) => (
              <details key={q} className="glass">
                <summary>
                  <h3>{q}</h3>
                </summary>
                <p>{a}</p>
              </details>
            ))}
          </div>
        </section>

        <section className="section install" id="install" aria-labelledby="install-title">
          <div className="section-head center">
            <img src="/app-icon.png" alt="" width={112} height={112} className="app-icon" />
            <h2 id="install-title">Get NoSleep.</h2>
            <p className="lede">Free, for macOS 14 or later. Updates in one click.</p>
            <DownloadButtons />
            <p className="fine narrow">
              Not notarised: on first launch, click <b>Open Anyway</b> in System Settings → Privacy &amp; Security.
              The two lines below skip this.
            </p>
          </div>

          <div className="methods">
            <div className="method">
              <h3>
                <I.Terminal />
                One line
              </h3>
              <Copy lines={[INSTALL_LINE]} label="the install command" />
            </div>
            <div className="method">
              <h3>
                <I.Mug />
                Homebrew
              </h3>
              <Copy lines={BREW_LINES} label="the Homebrew commands" />
            </div>
          </div>
        </section>
      </main>

      <footer className="footer">
        <span className="footer-brand">
          <Cat awake={false} className="nav-cat" />
          NoSleep by Intuito Studio
        </span>
        <span>
          Much of it follows <a href={INSOMNIA_URL}>Insomnia</a> (MIT), which got there first.
        </span>
        <a href={REPO_URL}>Source on GitHub</a>
      </footer>
    </>
  );
}
