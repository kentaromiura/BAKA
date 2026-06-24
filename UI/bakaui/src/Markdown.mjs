import MarkdownIt from "markdown-it";
import Shiki from "@shikijs/markdown-it";
import { bundledLanguages } from "shiki";
import rescriptGrammar from "./rescript.tmLanguage.json";

const rescriptLang = {
  ...rescriptGrammar,
  name: "rescript",
  embeddedLangs: ["javascript"],
};

const langs = [...Object.keys(bundledLanguages), rescriptLang];

let lightMd = null;
let darkMd = null;
let preloadError = null;
let loadedThemeKey = null;
let requestedThemeKey = null;
const markdownCache = new Map();

function createMarkdown(theme) {
  if (markdownCache.has(theme)) return markdownCache.get(theme);
  const promise = (async () => {
    const plugin = await Shiki({ theme, langs });
    const markdown = new MarkdownIt({
      html: false,
      linkify: true,
      breaks: true,
    });
    markdown.use(plugin);
    return markdown;
  })();
  markdownCache.set(theme, promise);
  return promise;
}

async function preloadMarkdown(lightTheme, darkTheme) {
  const themeKey = `${lightTheme}:${darkTheme}`;
  requestedThemeKey = themeKey;
  if (loadedThemeKey === themeKey && lightMd && darkMd) return;

  preloadError = null;
  try {
    console.log("[Markdown] preload starting");
    const [nextLightMd, nextDarkMd] = await Promise.all([
      createMarkdown(lightTheme),
      createMarkdown(darkTheme),
    ]);
    if (requestedThemeKey === themeKey) {
      lightMd = nextLightMd;
      darkMd = nextDarkMd;
      loadedThemeKey = themeKey;
      console.log("[Markdown] preload done, instances ready");
    }
  } catch (err) {
    markdownCache.delete(lightTheme);
    markdownCache.delete(darkTheme);
    preloadError = err;
    console.error("[Markdown] preload failed:", err);
  }
}

function escapeHtml(s) {
  return s
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;")
    .replace(/'/g, "&#39;");
}

function plainFallback(text) {
  return `<pre class="plain-fallback">${escapeHtml(text)}</pre>`;
}

// Some models emit string-escaped sequences (\n, \t, \", \', \\) as
// literal text instead of the real characters. Decode the common JSON
// string escapes so markdown layout (paragraphs, code fences, etc.)
// works as expected.
function unescapeStringEscapes(s) {
  return s
    .replace(/\\n/g, "\n")
    .replace(/\\r/g, "\r")
    .replace(/\\t/g, "\t")
    .replace(/\\"/g, '"')
    .replace(/\\'/g, "'")
    .replace(/\\\\/g, "\\");
}

function renderMarkdown(text, themeType) {
  if (!text) return "";
  const instance = themeType === "light" ? lightMd : darkMd;
  if (!instance) {
    console.warn(
      "[Markdown] instance not ready, using fallback. preloadError:",
      preloadError,
    );
    return plainFallback(unescapeStringEscapes(text));
  }
  try {
    return instance.render(unescapeStringEscapes(text));
  } catch (err) {
    console.warn("[Markdown] render failed, falling back to plain text:", err);
    return plainFallback(unescapeStringEscapes(text));
  }
}

export { preloadMarkdown, renderMarkdown };
