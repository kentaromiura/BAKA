const DEFAULT_FONT_SIZE = 13;
const MIN_FONT_SIZE = 11;
// At sizes above 24px, the diff component's fixed line geometry starts
// clipping the bottom of rendered lines.
const MAX_FONT_SIZE = 24;
const STORAGE_KEY = "baka.baseFontSize";

const clamp = size =>
  Math.min(MAX_FONT_SIZE, Math.max(MIN_FONT_SIZE, Math.round(size)));

const readFontSize = () => {
  try {
    const stored = Number.parseInt(window.localStorage.getItem(STORAGE_KEY), 10);
    return Number.isFinite(stored) ? clamp(stored) : DEFAULT_FONT_SIZE;
  } catch {
    return DEFAULT_FONT_SIZE;
  }
};

const applyFontSize = size => {
  const nextSize = clamp(size);
  document.documentElement.style.setProperty(
    "--baka-base-font-size",
    `${nextSize}px`,
  );
  document.documentElement.dataset.bakaFontSize = String(nextSize);
  try {
    window.localStorage.setItem(STORAGE_KEY, String(nextSize));
  } catch {
    // Persistence can be unavailable in locked-down webviews.
  }
  return nextSize;
};

const zoomAction = event => {
  if (!(event.metaKey || event.ctrlKey) || event.altKey) return null;

  if (event.key === "0" || event.code === "Numpad0") return "reset";
  if (
    event.key === "+" ||
    event.key === "=" ||
    event.code === "NumpadAdd"
  ) {
    return "in";
  }
  if (event.key === "-" || event.code === "NumpadSubtract") return "out";
  return null;
};

export const installZoomShortcuts = () => {
  let currentSize = applyFontSize(readFontSize());
  if (window.__bakaZoomShortcutsInstalled) return;
  window.__bakaZoomShortcutsInstalled = true;

  window.addEventListener(
    "keydown",
    event => {
      const action = zoomAction(event);
      if (action == null) return;

      event.preventDefault();
      currentSize = applyFontSize(
        action === "reset"
          ? DEFAULT_FONT_SIZE
          : currentSize + (action === "in" ? 1 : -1),
      );
    },
    { capture: true },
  );
};
