import MarkdownIt from "markdown-it";
import Shiki from "@shikijs/markdown-it";
import { bundledLanguages } from "shiki";
import rescriptGrammar from "./rescript.tmLanguage.json";

const SHIKI_LIGHT = "rose-pine-dawn";
const SHIKI_DARK = "tokyo-night";

const rescriptLang = {
  ...rescriptGrammar,
  name: "rescript",
  embeddedLangs: ["javascript"],
};

const langs = [...Object.keys(bundledLanguages), rescriptLang];

let preloadPromise = null;
let lightMd = null;
let darkMd = null;
let preloadError = null;

async function preloadMarkdown() {
  if (preloadPromise) return preloadPromise;
  preloadPromise = (async () => {
    try {
      console.log("[Markdown] preload starting");
      const [lightPlugin, darkPlugin] = await Promise.all([
        Shiki({ theme: SHIKI_LIGHT, langs }),
        Shiki({ theme: SHIKI_DARK, langs }),
      ]);

      lightMd = new MarkdownIt({
        html: false,
        linkify: true,
        breaks: true,
      });
      lightMd.use(lightPlugin);

      darkMd = new MarkdownIt({
        html: false,
        linkify: true,
        breaks: true,
      });
      darkMd.use(darkPlugin);
      console.log("[Markdown] preload done, instances ready");
    } catch (err) {
      preloadError = err;
      console.error("[Markdown] preload failed:", err);
    }
  })();
  return preloadPromise;
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
