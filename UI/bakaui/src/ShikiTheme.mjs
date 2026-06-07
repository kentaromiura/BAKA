const themeCache = new Map();
let preloadPromise = null;

async function preloadShiki() {
  if (preloadPromise) return preloadPromise;
  preloadPromise = (async () => {
    const { preloadHighlighter } = await import("@pierre/diffs");
    await preloadHighlighter({
      themes: ["rose-pine-dawn", "tokyo-night"],
      langs: ["javascript", "typescript", "json", "html", "css", "markdown", "tsx", "jsx", "rescript", "odin"],
    });
  })();
  return preloadPromise;
}

async function loadThemeColors(themeName) {
  if (themeCache.has(themeName)) {
    return themeCache.get(themeName);
  }

  const { bundledThemes } = await import("shiki/themes");
  const themeLoader = bundledThemes[themeName];

  if (!themeLoader) {
    console.warn(`Shiki theme "${themeName}" not found, returning fallback colors`);
    const fallback = getFallbackColors(themeName);
    themeCache.set(themeName, fallback);
    return fallback;
  }

  const { default: theme } = await themeLoader();
  const colors = theme.colors || {};

  const extracted = {
    bg: colors["editor.background"] || colors["sideBar.background"] || "#1e1e2e",
    fg: colors["editor.foreground"] || colors["foreground"] || "#cdd6f4",
    border: colors["editorGroup.border"] || colors["panel.border"] || "#313244",
    buttonBg: colors["button.background"] || "#89b4fa",
    buttonFg: colors["button.foreground"] || "#1e1e2e",
    buttonHoverBg: colors["button.hoverBackground"] || "#74c7ec",
    inputBg: colors["input.background"] || colors["list.dropBackground"] || "#313244",
    inputFg: colors["input.foreground"] || colors["editor.foreground"] || "#cdd6f4",
    inputBorder: colors["input.border"] || "#45475a",
    inputPlaceholder: colors["input.placeholderForeground"] || "#6c7086",
    focusBorder: colors["focusBorder"] || "#89b4fa",
    selectionBg: colors["editor.selectionBackground"] || "#585b70",
    hoverBg: colors["list.hoverBackground"] || colors["toolbar.hoverBackground"] || "#313244",
    activeSelectionBg: colors["list.activeSelectionBackground"] || "#45475a",
    descriptionFg: colors["descriptionForeground"] || colors["icon.foreground"] || "#6c7086",
    surfaceBg: colors["sideBar.background"] || colors["panel.background"] || "#1e1e2e",
    surfaceBorder: colors["sideBar.border"] || colors["panel.border"] || "#313244",
    badgeBg: colors["badge.background"] || "#45475a",
    dangerBg: colors["checkbox.border"] || colors["errorForeground"] || "#f38ba8",
    dangerHoverBg: colors["settings.checkbox.hoverBackground"] || "#eba0ac",
    themeType: theme.type || "dark",
  };

  themeCache.set(themeName, extracted);
  return extracted;
}

async function loadBothThemes(lightTheme, darkTheme) {
  try {
    const [lightColors, darkColors] = await Promise.all([
      loadThemeColors(lightTheme),
      loadThemeColors(darkTheme),
    ]);
    return { light: lightColors, dark: darkColors };
  } catch (error) {
    console.error("Failed to load themes:", error);
    return undefined;
  }
}

function getFallbackColors(themeName) {
  const isDark = !themeName.includes("light") && !themeName.includes("dawn") && !themeName.includes("lotus");
  if (isDark) {
    return {
      bg: "#1e1e2e",
      fg: "#cdd6f4",
      border: "#313244",
      buttonBg: "#89b4fa",
      buttonFg: "#1e1e2e",
      buttonHoverBg: "#74c7ec",
      inputBg: "#313244",
      inputFg: "#cdd6f4",
      inputBorder: "#45475a",
      inputPlaceholder: "#6c7086",
      focusBorder: "#89b4fa",
      selectionBg: "#585b70",
      hoverBg: "#313244",
      activeSelectionBg: "#45475a",
      descriptionFg: "#6c7086",
      surfaceBg: "#1e1e2e",
      surfaceBorder: "#313244",
      badgeBg: "#45475a",
      dangerBg: "#f38ba8",
      dangerHoverBg: "#eba0ac",
      themeType: "dark",
    };
  }
  return {
    bg: "#fafafa",
    fg: "#4c4f69",
    border: "#e6e9ef",
    buttonBg: "#8839ef",
    buttonFg: "#fafafa",
      buttonHoverBg: "#a060ff",
    inputBg: "#eff1f5",
    inputFg: "#4c4f69",
    inputBorder: "#dcc0e8",
    inputPlaceholder: "#9ca0b0",
    focusBorder: "#8839ef",
    selectionBg: "#e0e7ef",
    hoverBg: "#e6e9ef",
    activeSelectionBg: "#dcc0e8",
    descriptionFg: "#9ca0b0",
    surfaceBg: "#fafafa",
    surfaceBorder: "#e6e9ef",
    badgeBg: "#ccd0da",
    dangerBg: "#d20f39",
    dangerHoverBg: "#ff6b81",
    themeType: "light",
  };
}

export { loadThemeColors, loadBothThemes, preloadShiki };
