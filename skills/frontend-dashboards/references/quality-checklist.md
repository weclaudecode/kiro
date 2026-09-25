# Quality checklist: run before calling a dashboard done

## 1. Build and data

- [ ] `python3 scripts/to_rows.py validate <data file>` prints `ok`.
- [ ] React: `npm run build` passes (typecheck + bundle). No new `any`, and no disabled strict flags.
- [ ] Vanilla: served over HTTP, not `file://`.

## 2. Look at it in a real browser (not optional)

Chromium plus Playwright is the reliable way for an agent to see the page. A minimal check script:

```js
// check.mjs - node check.mjs http://localhost:8000/ out.png [light|dark] [width]
import { chromium } from "playwright";
const [url, out, scheme = "light", width = "1440"] = process.argv.slice(2);
const browser = await chromium.launch();
const page = await browser.newPage({ viewport: { width: +width, height: 900 }, colorScheme: scheme });
const errors = [];
page.on("console", (m) => m.type() === "error" && errors.push(m.text()));
page.on("pageerror", (e) => errors.push(e.message));
await page.goto(url, { waitUntil: "networkidle" });
await page.screenshot({ path: out, fullPage: true });
const overflow = await page.evaluate(() => document.documentElement.scrollWidth > innerWidth);
console.log(JSON.stringify({ errors, overflow }));
await browser.close();
```

- [ ] Screenshots at **1440 light**, **1440 dark**, and **390 light**, and you actually looked at them.
- [ ] Zero console errors and page errors.
- [ ] No horizontal page scroll at 390px (tables scroll inside their card).
- [ ] No clipped bar labels, overlapping axis labels, or legend overflowing its card.
- [ ] Dark mode: nothing stays light, and charts re-theme when you use the toggle, not just on reload.

## 3. Behavior

- [ ] Every range preset works. The previous-period text is correct or says "no prior data".
- [ ] Each dimension filter narrows all widgets, and "Reset filters" restores everything.
- [ ] Cross-filter: a chart click or table row click toggles, and a second click clears it.
- [ ] Reloading with the URL hash restores the view, and back/forward works.
- [ ] Table search, sort (both directions, nulls last), pagination bounds, and totals are right.
- [ ] CSV opens in a spreadsheet with rounded numbers and full names.
- [ ] Filters that match nothing show the empty state, not a crash or NaN.
- [ ] A missing data file shows the error state with the fix.

## 4. Accessibility

- [ ] All controls are reachable and operable by keyboard: segmented buttons, multiselect (Escape
      closes it), sort headers, table rows (Enter), pager.
- [ ] Visible focus ring (`:focus-visible` uses `--focus`).
- [ ] Charts have `role="img"` + `aria-label` and a visible card title. The table is the accessible alternative to the charts.
- [ ] Color is never the only signal: deltas carry arrows and signs, legends accompany any chart with 2+ series, and movers have signed labels.
- [ ] Text contrast is 4.5:1 or better (muted text included). Reduced motion disables animation and shimmer.

## 5. Performance

- [ ] Formatters are cached. Selectors are memoized. No aggregation inside render loops.
- [ ] The chart count per page is reasonable (under ~8). Charts use one `ResizeObserver` each and are disposed on unmount.
- [ ] The data payload is under ~20 MB raw. Beyond that, pre-aggregate upstream.
- [ ] React: widgets re-render only when their selector output changes (check with React DevTools "Highlight updates").

## 6. Security

- [ ] Data values that reach `innerHTML` go through `esc()`. There is no `dangerouslySetInnerHTML` in React.
- [ ] CDN scripts are exact-pinned with `integrity` + `crossorigin`. There are no other third-party origins.
- [ ] CSV export keeps the formula-injection guard.
- [ ] Real cost data is not committed to git and not hosted publicly. Hosting sits behind auth.
- [ ] If hosted: a CSP of `default-src 'self'; script-src 'self' https://cdn.jsdelivr.net; style-src 'self' 'unsafe-inline'; img-src 'self' data:`.
      `'unsafe-inline'` for styles is required because ECharts, the share bars, and the skeletons set inline `style`.
      Both kits' `index.html` have an inline theme script: add its `sha256-` hash to `script-src`, or move it to a file.
