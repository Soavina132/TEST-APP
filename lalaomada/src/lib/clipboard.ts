// Robust clipboard copy helper.
//
// navigator.clipboard.writeText silently rejects (or is unavailable) in a
// number of real-world contexts: in-app browsers/webviews (WhatsApp,
// Facebook, Messenger, TikTok), non-HTTPS contexts, or pages without the
// "clipboard-write" permission. When that happens the original code did
// nothing visible — the button looked broken. This helper always falls
// back to a hidden-textarea + document.execCommand("copy"), which works in
// virtually every webview, so a click always actually copies the text.
export async function copyText(text: string): Promise<boolean> {
  if (!text) return false;

  if (navigator.clipboard?.writeText) {
    try {
      await navigator.clipboard.writeText(text);
      return true;
    } catch {
      // fall through to the legacy fallback below
    }
  }

  try {
    const textarea = document.createElement("textarea");
    textarea.value = text;
    textarea.setAttribute("readonly", "");
    textarea.style.position = "fixed";
    textarea.style.top = "0";
    textarea.style.left = "0";
    textarea.style.width = "1px";
    textarea.style.height = "1px";
    textarea.style.padding = "0";
    textarea.style.border = "none";
    textarea.style.outline = "none";
    textarea.style.boxShadow = "none";
    textarea.style.background = "transparent";
    textarea.style.opacity = "0";
    document.body.appendChild(textarea);
    textarea.focus();
    textarea.select();
    textarea.setSelectionRange(0, textarea.value.length);
    const ok = document.execCommand("copy");
    document.body.removeChild(textarea);
    return ok;
  } catch {
    return false;
  }
}
