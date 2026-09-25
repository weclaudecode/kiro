// Chart colors come from CSS tokens, re-read when the theme changes. No hex in chart code.
import { useMemo, useSyncExternalStore } from "react";

export interface ChartTokens {
  surface: string;
  text: string;
  textSecondary: string;
  muted: string;
  grid: string;
  axis: string;
  border: string;
  font: string;
  series: string[];
  other: string;
}

export function readTokens(): ChartTokens {
  const cs = getComputedStyle(document.documentElement);
  const v = (name: string) => cs.getPropertyValue(name).trim();
  return {
    surface: v("--surface-1"),
    text: v("--text-primary"),
    textSecondary: v("--text-secondary"),
    muted: v("--text-muted"),
    grid: v("--grid"),
    axis: v("--axis"),
    border: v("--border-strong"),
    font: v("--font-sans"),
    series: Array.from({ length: 8 }, (_, i) => v(`--series-${i + 1}`)),
    other: v("--series-other"),
  };
}

export type Theme = "light" | "dark";

export function currentTheme(): Theme {
  const explicit = document.documentElement.dataset.theme;
  if (explicit === "light" || explicit === "dark") return explicit;
  return matchMedia("(prefers-color-scheme: dark)").matches ? "dark" : "light";
}

function subscribe(onChange: () => void) {
  const mq = matchMedia("(prefers-color-scheme: dark)");
  mq.addEventListener("change", onChange);
  document.addEventListener("themechange", onChange);
  return () => {
    mq.removeEventListener("change", onChange);
    document.removeEventListener("themechange", onChange);
  };
}

export function useTheme(): Theme {
  return useSyncExternalStore(subscribe, currentTheme, () => "light");
}

/** Tokens for the active theme; a new object only when the theme flips, so chart options memoize. */
export function useChartTokens(): ChartTokens {
  const theme = useTheme();
  // theme is the invalidation key: CSS variables changed, re-read them.
  return useMemo(readTokens, [theme]);
}

export function setTheme(theme: Theme): void {
  document.documentElement.dataset.theme = theme;
  try {
    localStorage.setItem("theme", theme);
  } catch {
    /* private mode / blocked storage: theme still applies for this page view */
  }
  document.dispatchEvent(new Event("themechange"));
}
