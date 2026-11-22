// Keep (Phil, 21 November 2026: "SPECIFIC INDIVIDUAL TABS"): a kept tab is that tab, not its address. Chrome
// knows a tab by a number that lasts only until it quits, so after a restart a kept tab is found again by
// window, position, and address; when two restored tabs match, the popup asks which (design, "Keep").

// Windows get new IDs after a restart, but Chrome hands out IDs in the order windows open and restores them
// in their old order, so a window's place among the open windows is what survives.
export function windowOrdinals(tabs) {
  const ids = [...new Set(tabs.map((t) => t.windowId))].sort((a, b) => a - b);
  return new Map(ids.map((id, i) => [id, i]));
}

export function keepRecord(tab, ordinals) {
  return { tabId: tab.id, url: tab.url, title: tab.title || '', index: tab.index, windowOrdinal: ordinals.get(tab.windowId) ?? 0 };
}

// Returns { kept: [record with its current tabId], questions: [{ record, candidates: [tabId] }], lost: [record] }.
export function rematch(records, tabs, ordinals = windowOrdinals(tabs)) {
  const byId = new Map(tabs.map((t) => [t.id, t]));
  const claimed = new Set();
  const kept = [];
  const questions = [];
  const lost = [];
  const pending = [];

  // First, tabs that never went away (the extension was reloaded or updated, not Chrome).
  for (const r of records) {
    const t = byId.get(r.tabId);
    if (t && t.url === r.url && !claimed.has(t.id)) {
      claimed.add(t.id);
      kept.push({ ...r, index: t.index, windowOrdinal: ordinals.get(t.windowId) ?? r.windowOrdinal });
    } else pending.push(r);
  }

  for (const r of pending) {
    const candidates = tabs.filter((t) => t.url === r.url && !claimed.has(t.id));
    if (candidates.length === 0) { lost.push(r); continue; }
    if (candidates.length === 1) {
      claimed.add(candidates[0].id);
      kept.push({ ...r, tabId: candidates[0].id });
      continue;
    }
    const score = (t) => (t.index === r.index ? 2 : 0) + ((ordinals.get(t.windowId) ?? -1) === r.windowOrdinal ? 1 : 0);
    const best = Math.max(...candidates.map(score));
    const top = candidates.filter((t) => score(t) === best);
    // Only a match on both window and position is sure enough to choose without asking.
    if (best === 3 && top.length === 1) {
      claimed.add(top[0].id);
      kept.push({ ...r, tabId: top[0].id });
    } else {
      questions.push({ record: r, candidates: candidates.map((t) => t.id) });
    }
  }
  return { kept, questions, lost };
}
