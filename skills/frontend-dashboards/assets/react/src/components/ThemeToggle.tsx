import { setTheme, useTheme } from "../charts/theme";

export function ThemeToggle() {
  const theme = useTheme();
  return (
    <button
      type="button"
      className="btn btn-ghost"
      aria-label="Toggle dark mode"
      onClick={() => setTheme(theme === "dark" ? "light" : "dark")}
    >
      {theme === "dark" ? "Light mode" : "Dark mode"}
    </button>
  );
}
