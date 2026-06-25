const STORAGE_PREFIX = "baka.commitDraft.v1.";

function hash(text) {
  let value = 2166136261;
  for (let index = 0; index < text.length; index += 1) {
    value ^= text.charCodeAt(index);
    value = Math.imul(value, 16777619);
  }
  return (value >>> 0).toString(16).padStart(8, "0");
}

export function storageKey(repoRoot) {
  return repoRoot ? STORAGE_PREFIX + hash(repoRoot) : "";
}

export function fingerprintFiles(fileDiffs) {
  const fingerprints = {};
  for (const file of fileDiffs) {
    const name = file?.name || "";
    if (!name) continue;
    fingerprints[name] = hash(JSON.stringify({
      name,
      prevName: file.prevName || "",
      type: file.type || "",
      mode: file.mode || "",
      prevObjectId: file.prevObjectId || "",
      newObjectId: file.newObjectId || "",
      hunks: file.hunks || [],
      additionLines: file.additionLines || [],
      deletionLines: file.deletionLines || [],
    }));
  }
  return fingerprints;
}

export function fingerprintSignature(fingerprints) {
  return Object.keys(fingerprints)
    .sort()
    .map(name => name + ":" + fingerprints[name])
    .join("|");
}

export function loadDraft(key) {
  if (!key) return null;
  try {
    const value = JSON.parse(window.localStorage.getItem(key) || "null");
    return value && typeof value === "object" ? value : null;
  } catch {
    return null;
  }
}

export function reconcileDraft(draft, fileNames, fingerprints) {
  const selectedFiles = {};
  const excludedLines = {};
  let resetCount = 0;

  for (const name of fileNames) {
    const unchanged =
      draft?.fingerprints?.[name] !== undefined &&
      draft.fingerprints[name] === fingerprints[name];
    if (unchanged) {
      selectedFiles[name] = draft?.selectedFiles?.[name] !== false;
      const prefix = name + "|";
      for (const [key, value] of Object.entries(draft?.excludedLines || {})) {
        if (key.startsWith(prefix) && value === true) excludedLines[key] = true;
      }
    } else {
      selectedFiles[name] = true;
      if (draft?.fingerprints?.[name] !== undefined) resetCount += 1;
    }
  }

  const activeFileName = fileNames.includes(draft?.activeFileName)
    ? draft.activeFileName
    : (fileNames[0] || "");

  return {
    message: typeof draft?.message === "string" ? draft.message : "",
    body: typeof draft?.body === "string" ? draft.body : "",
    selectedFiles,
    excludedLines,
    activeFileName,
    resetCount,
  };
}

export function saveDraft(key, draft) {
  if (!key) return;
  try {
    window.localStorage.setItem(key, JSON.stringify(draft));
  } catch {
    // Persistence is a convenience; storage failures must not block commits.
  }
}

export function clearDraft(key) {
  if (!key) return;
  try {
    window.localStorage.removeItem(key);
  } catch {
    // Ignore unavailable storage.
  }
}
