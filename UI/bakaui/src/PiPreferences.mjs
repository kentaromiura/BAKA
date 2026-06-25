const STORAGE_KEY = "baka.piPreferences";
const INHERIT_MODEL = "";

const defaults = {
  defaultModel: "",
  inlineReviewModel: INHERIT_MODEL,
  codeReviewModel: INHERIT_MODEL,
  securityReviewModel: INHERIT_MODEL,
  specReviewModel: INHERIT_MODEL,
  suggestionModel: INHERIT_MODEL,
  validationModel: INHERIT_MODEL,
  planModel: INHERIT_MODEL,
  implementationModel: INHERIT_MODEL,
};

function loadPiPreferences() {
  try {
    const stored = JSON.parse(localStorage.getItem(STORAGE_KEY) || "{}");
    return {...defaults, ...stored};
  } catch {
    return {...defaults};
  }
}

function savePiPreferences(preferences) {
  try {
    localStorage.setItem(STORAGE_KEY, JSON.stringify(preferences));
  } catch {
    // WebView storage may be unavailable. Preferences still work in-memory.
  }
}

function resolvePiModel(preferences, actionModel) {
  return actionModel || preferences.defaultModel || "";
}

export {
  INHERIT_MODEL,
  loadPiPreferences,
  resolvePiModel,
  savePiPreferences,
};
