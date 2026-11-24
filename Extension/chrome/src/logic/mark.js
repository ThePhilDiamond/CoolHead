// The sleeping tab's title mark. Chrome shows no sign of a tab an extension put to sleep: its own dashed ring is only
// for tabs Chrome slept itself (Chromium's tab_renderer_data.cc, checked at versions 131 and 139). So just before a tab
// sleeps, Cool Head puts "zzZ" before its title, and the page brings back its own title when it wakes and reloads.
// Nothing stays loaded to show it, unlike a suspender's stand-in page.
//
// Plain letters, not an emoji: Chrome draws a title in the tab's own text color, which it picks to stand out on the
// theme, whether light, dark, or colored, while an emoji's colors are fixed and can vanish on a blue theme.
//
// The space after the letters is an en space (U+2002), which a page's own title doesn't have after "zzZ", so Cool
// Head can tell its mark from the page's words and take it off wherever it shows or saves a title: Saved windows'
// bookmarks, the popup's lists, and what Cool Head remembers about kept tabs. It comes off wherever it is in the
// title, since a page that rewrites its title as it goes to sleep (an unread count put before it) can push it along.
export const SLEEP_MARK = 'zzZ\u2002';

// The page's own title, without Cool Head's mark.
export function realTitle(title) {
  return typeof title === 'string' && title.includes(SLEEP_MARK) ? title.split(SLEEP_MARK).join('') : title;
}

// A tab as Chrome reports it, with the page's own title.
export function withRealTitle(tab) {
  return tab && typeof tab.title === 'string' && tab.title.includes(SLEEP_MARK) ? { ...tab, title: realTitle(tab.title) } : tab;
}

// These two run in the page, through chrome.scripting, so each stands alone: Chrome sends only its own text.
// A page with no title of its own (a PDF, a text file, a page without one) shows what Chrome gives it instead: the
// PDF's own title or the page's address. That comes in as `shown`, so the mark goes before it and nothing is lost.
export function markInPage(mark, shown) {
  if (!document.title.includes(mark)) document.title = mark + (document.title || shown || location.hostname || '');
  return document.title.includes(mark);
}

export function unmarkInPage(mark) {
  if (document.title.includes(mark)) document.title = document.title.split(mark).join('');
  return !document.title.includes(mark);
}
