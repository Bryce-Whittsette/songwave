// Only publish a tab while its video is playing. SPA navigation invalidates the
// category immediately so a previous music video's metadata cannot open the gate.
(() => {
  let port, videoID, category, title = "", generation = 0;
  let lookupInProgress = false, retryAt = 0;
  const runtime = chrome.runtime;
  const meta = (doc, key) => doc.querySelector('meta[itemprop="' + key + '"]')?.content || "";
  async function identify(id, version) {
    try {
      let doc = document;
      if (meta(doc, "videoId") !== id || !meta(doc, "genre")) {
        const url = new URL("/watch", location.origin);
        url.searchParams.set("v", id);
        const reply = await fetch(url, { credentials: "same-origin" });
        if (!reply.ok) return;
        doc = new DOMParser().parseFromString(await reply.text(), "text/html");
      }
      if (version !== generation || meta(doc, "videoId") !== id) return;
      const genre = meta(doc, "genre").trim().toLowerCase();
      category = genre === "music" ? "music" : genre ? "other" : "unknown";
      title = (doc.querySelector('meta[property="og:title"]')?.content || "").slice(0, 200);
    } catch { /* Unavailable category keeps haptics paused. */ }
    finally {
      if (version === generation) {
        lookupInProgress = false;
        retryAt = Date.now() + 5000;
      }
    }
  }
  function stop() {
    if (port) { port.disconnect(); port = undefined; }
  }
  function update() {
    const video = document.querySelector("video");
    const page = new URL(location.href);
    const id = page.searchParams.get("v") || page.pathname.match(/^\/shorts\/([^/]+)/)?.[1];
    if (id !== videoID) {
      videoID = id; category = "unknown"; title = ""; generation++;
      lookupInProgress = false; retryAt = 0;
    }
    if (!video || video.paused || video.ended || video.muted || video.volume === 0 || !id) { stop(); return; }
    if (category === "unknown" && !lookupInProgress && Date.now() >= retryAt) {
      lookupInProgress = true;
      identify(id, generation);
    }
    if (!port) {
      const connection = runtime.connect({ name: "songwave-youtube" });
      connection.onDisconnect.addListener(() => { if (port === connection) port = undefined; });
      port = connection;
    }
    port.postMessage({ category: document.querySelector(".ad-showing") ? "other" : category, title, videoID: id,
      position: Number.isFinite(video.currentTime) ? video.currentTime : null,
      duration: Number.isFinite(video.duration) ? video.duration : null });
  }
  for (const event of ["playing", "pause", "ended", "volumechange", "yt-navigate-finish"]) {
    document.addEventListener(event, update, true);
  }
  window.addEventListener("pagehide", stop);
  setInterval(update, 1000);
})();
