import { bundledThemesInfo } from "shiki/themes";

const STORAGE_KEY = "baka.themePreferences";
const DEFAULT_THEMES = {
  light: "rose-pine-dawn",
  dark: "tokyo-night",
};

const themesById = new Map(bundledThemesInfo.map((theme) => [theme.id, theme]));

function isThemeOfType(themeName, type) {
  return themesById.get(themeName)?.type === type;
}

function loadThemePreferences() {
  try {
    const stored = JSON.parse(localStorage.getItem(STORAGE_KEY) || "{}");
    return {
      light: isThemeOfType(stored.light, "light")
        ? stored.light
        : DEFAULT_THEMES.light,
      dark: isThemeOfType(stored.dark, "dark")
        ? stored.dark
        : DEFAULT_THEMES.dark,
    };
  } catch {
    return { ...DEFAULT_THEMES };
  }
}

function saveThemePreferences(themes) {
  try {
    localStorage.setItem(STORAGE_KEY, JSON.stringify(themes));
  } catch (error) {
    console.warn("[Themes] Could not persist theme preferences:", error);
  }
}

function getThemeOptions(type) {
  return bundledThemesInfo
    .filter((theme) => theme.type === type)
    .map((theme) => ({
      id: theme.id,
      displayName: theme.displayName,
    }))
    .sort((a, b) => a.displayName.localeCompare(b.displayName));
}

export {
  DEFAULT_THEMES,
  getThemeOptions,
  loadThemePreferences,
  saveThemePreferences,
};
