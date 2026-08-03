type ExternalTarget = {
  webUrl: string;
  appUrl?: string;
  androidIntent?: string;
  androidIntents?: string[];
  nativeUrls?: string[];
  marketUrl?: string;
  preferIntent?: boolean;
  disableAndroidCascade?: boolean;
  singleAndroidIntent?: boolean;
};

function isAndroid(userAgent: string) {
  return /Android/i.test(userAgent);
}

function tryNativeBridge(url: string, fallbackUrl?: string) {
  const w = window as any;
  const payload = { type: "openExternal", url, fallbackUrl };
  try {
    const bridgeNames = ["Android", "NativeBridge", "WebAppInterface", "LalaoMada"];
    const methodNames = ["openExternal", "openUrl", "openInBrowser", "openIntent", "launchIntent", "openApp"];

    for (const bridgeName of bridgeNames) {
      const bridge = w[bridgeName];
      if (!bridge) continue;
      for (const methodName of methodNames) {
        if (typeof bridge[methodName] === "function") {
          bridge[methodName](url, fallbackUrl || "");
          return true;
        }
      }
    }

    if (w.ReactNativeWebView?.postMessage) {
      w.ReactNativeWebView.postMessage(JSON.stringify(payload));
      return true;
    }

    if (w.webkit?.messageHandlers?.openExternal?.postMessage) {
      w.webkit.messageHandlers.openExternal.postMessage(payload);
      return true;
    }
  } catch {
    return false;
  }
  return false;
}

function openWithAnchor(url: string, target: "_blank" | "_top" | "_self" = "_top") {
  const a = document.createElement("a");
  a.href = url;
  a.target = target;
  a.rel = "noopener noreferrer";
  a.style.display = "none";
  document.body.appendChild(a);
  a.click();
  window.setTimeout(() => a.remove(), 300);
}

function openWithHiddenFrame(url: string) {
  try {
    const frame = document.createElement("iframe");
    frame.src = url;
    frame.style.display = "none";
    frame.setAttribute("aria-hidden", "true");
    document.body.appendChild(frame);
    window.setTimeout(() => frame.remove(), 1200);
  } catch {
    // Ignore unsupported custom schemes in regular browsers.
  }
}

function openNativeUrl(url: string, target: "_self" | "_top" | "_blank") {
  openWithHiddenFrame(url);
  openWithAnchor(url, target);
  try {
    window.location.assign(url);
  } catch {
    // Last fallback can fail for unknown schemes.
  }
}

function compactUrls(urls: Array<string | undefined>) {
  return urls.filter((url, index, list): url is string => Boolean(url) && list.indexOf(url) === index);
}

export function openExternal({ webUrl, appUrl, androidIntent, androidIntents = [], nativeUrls = [], marketUrl, preferIntent, disableAndroidCascade }: ExternalTarget) {
  if (typeof window === "undefined") return;

  const ua = navigator.userAgent || "";
  const androidDevice = isAndroid(ua);
  const topTarget = window.top !== window.self ? "_top" : "_blank";

  if (androidDevice) {
    const intents = compactUrls([...androidIntents, androidIntent]);
    const candidates = preferIntent
      ? compactUrls([...intents, ...nativeUrls, appUrl, marketUrl, webUrl])
      : compactUrls([appUrl, ...intents, ...nativeUrls, marketUrl, webUrl]);
    const primary = candidates[0] || webUrl;
    const fallback = marketUrl || webUrl;

    if (disableAndroidCascade) {
      openWithAnchor(primary, "_self");
      window.setTimeout(() => {
        try {
          window.location.href = primary;
        } catch {
          // The WebView may block intent navigation; do not fallback to Play Store.
        }
      }, 50);
      return;
    }

    const bridgeTried = tryNativeBridge(primary, fallback);
    if (!bridgeTried) {
      openWithHiddenFrame(primary);
      openWithAnchor(primary, "_top");
    }

    if (!disableAndroidCascade) {
      candidates.slice(1, 4).forEach((url, i) => {
        window.setTimeout(() => {
          if (document.visibilityState === "visible") openWithAnchor(url, "_top");
        }, 300 + i * 500);
      });

      window.setTimeout(() => {
        if (document.visibilityState === "visible" && fallback && !candidates.slice(0, 4).includes(fallback)) {
          openWithAnchor(fallback, "_top");
        }
      }, 2200);
    }
    return;
  }

  const nativeTarget = appUrl || webUrl;
  if (!tryNativeBridge(nativeTarget, webUrl)) openNativeUrl(nativeTarget, topTarget);

  window.setTimeout(() => {
    if (document.visibilityState === "visible") {
      const opened = window.open(webUrl, "_blank", "noopener,noreferrer");
      if (!opened) openWithAnchor(webUrl, window.top !== window.self ? "_top" : "_blank");
    }
  }, 1200);
}

export function whatsappTargets(phone: string) {
  const number = phone.replace(/\D/g, "");
  const marketUrl = "market://details?id=com.whatsapp";
  return {
    webUrl: `https://api.whatsapp.com/send?phone=${number}`,
    appUrl: `whatsapp://send?phone=${number}`,
    androidIntent: `intent://send?phone=${number}#Intent;scheme=whatsapp;package=com.whatsapp;action=android.intent.action.VIEW;S.browser_fallback_url=${encodeURIComponent(marketUrl)};end`,
    marketUrl,
  };
}

export function facebookTargets(url: string) {
  const normalizedUrl = /^https?:\/\//i.test(url)
    ? url.trim()
    : `https://www.facebook.com/${url.trim().replace(/^@/, "")}`;
  const webUrl = normalizedUrl
    .replace(/^https?:\/\/(?:m\.|mobile\.|web\.|www\.)?facebook\.com/i, "https://www.facebook.com")
    .replace(/^https?:\/\/fb\.com/i, "https://www.facebook.com");

  let exactProfileUrl = webUrl;
  try {
    const parsed = new URL(webUrl);
    parsed.protocol = "https:";
    parsed.hostname = "www.facebook.com";
    exactProfileUrl = parsed.toString();
  } catch {
    exactProfileUrl = `https://www.facebook.com/${url.trim().replace(/^@/, "").replace(/^\/+/, "")}`;
  }

  const profilePath = (() => {
    try {
      return new URL(exactProfileUrl).pathname.replace(/^\/+|\/+$/g, "");
    } catch {
      return url.trim().replace(/^@/, "").replace(/^\/+/, "");
    }
  })();

  const postTarget = (() => {
    try {
      const parsed = new URL(exactProfileUrl);
      const parts = parsed.pathname.split("/").filter(Boolean);
      const postsIndex = parts.findIndex((part) => part.toLowerCase() === "posts");
      const ownerId = postsIndex > 0 ? parts[postsIndex - 1] : parsed.searchParams.get("id") || "";
      const postId = postsIndex >= 0 ? parts[postsIndex + 1] : parsed.searchParams.get("story_fbid") || "";
      if (!ownerId || !postId) return null;

      const storyUrl = new URL("https://www.facebook.com/story.php");
      storyUrl.searchParams.set("story_fbid", postId);
      storyUrl.searchParams.set("id", ownerId);

      const nativeProfileUrl = `fb://profile/${ownerId}`;
      const nativePostUrl = `fb://post/${postId}`;
      const nativeWebUrl = `fb://facewebmodal/f?href=${encodeURIComponent(storyUrl.toString())}`;

      return {
        webUrl: storyUrl.toString(),
        appUrl: nativeProfileUrl,
        nativeUrls: [
          nativeProfileUrl,
          nativePostUrl,
          nativeWebUrl,
        ],
      };
    } catch {
      return null;
    }
  })();

  if (postTarget) {
    return {
      ...postTarget,
      preferIntent: false,
      disableAndroidCascade: true,
    };
  }

  const directProfileId = (() => {
    try {
      const parsed = new URL(exactProfileUrl);
      if (parsed.pathname.replace(/^\/+|\/+$/g, "").toLowerCase() === "profile.php") {
        return parsed.searchParams.get("id") || "";
      }
      return "";
    } catch {
      return "";
    }
  })();

  if (directProfileId) {
    const nativeProfileUrl = `fb://profile/${directProfileId}`;
    return {
      webUrl: exactProfileUrl,
      appUrl: nativeProfileUrl,
      nativeUrls: [nativeProfileUrl, `fb://facewebmodal/f?href=${encodeURIComponent(exactProfileUrl)}`],
      preferIntent: false,
      disableAndroidCascade: true,
    };
  }

  const knownProfileIds: Record<string, string> = {
    "rjean.pierrit": "100060433585093",
  };
  const profileId = knownProfileIds[profilePath.toLowerCase()];
  const nativeProfileUrl = profileId
    ? `fb://profile/${profileId}`
    : `fb://facewebmodal/f?href=${encodeURIComponent(exactProfileUrl)}`;

  return {
    webUrl: exactProfileUrl,
    appUrl: nativeProfileUrl,
    nativeUrls: [nativeProfileUrl],
    preferIntent: false,
    disableAndroidCascade: true,
  };
}