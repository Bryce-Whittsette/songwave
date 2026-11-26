chrome.runtime.onConnect.addListener(tab => {
  if (tab.name !== "songwave-youtube" || !tab.sender.tab) return;
  const browser = chrome.runtime.getURL("").startsWith("moz-extension:") ? "firefox" : "chrome";
  let host, muted = tab.sender.tab.mutedInfo?.muted === true;
  function release() {
    const previous = host;
    host = undefined;
    previous?.disconnect();
  }
  function tabUpdated(id, change) {
    if (id !== tab.sender.tab.id || !change.mutedInfo) return;
    muted = change.mutedInfo.muted;
    if (muted) release();
  }
  chrome.tabs.onUpdated.addListener(tabUpdated);
  tab.onDisconnect.addListener(() => {
    chrome.tabs.onUpdated.removeListener(tabUpdated);
    release();
  });
  tab.onMessage.addListener(({ category, title, videoID, position, duration }) => {
    if (muted) return;
    if (!host) {
      const port = chrome.runtime.connectNative("studio.songwave.youtube");
      host = port;
      port.onDisconnect.addListener(() => {
        void chrome.runtime.lastError;
        if (host === port) { host = undefined; tab.disconnect(); }
      });
    }
    host.postMessage({ browser, category, title, videoID, position, duration });
  });
});
