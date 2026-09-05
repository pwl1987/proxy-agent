(() => {
  const textarea = document.getElementById("config");
  const panel = document.getElementById("structured-config");
  if (!textarea || !panel || panel.dataset.configSyncBound === "1") return;
  panel.dataset.configSyncBound = "1";

  let lastObserved = textarea.value;
  let lastSynced = textarea.value;
  let userEditingJson = false;

  textarea.addEventListener("input", () => {
    userEditingJson = true;
    lastObserved = textarea.value;
  });
  textarea.addEventListener("blur", () => { userEditingJson = false; });

  const syncFromLoadedJson = () => {
    if (userEditingJson || textarea.value === lastObserved) return;
    const text = textarea.value;
    if (!text || text === lastSynced) {
      lastObserved = text;
      return;
    }
    try {
      JSON.parse(text);
    } catch (_) {
      lastObserved = text;
      return;
    }
    const loadButton = document.getElementById("form-load");
    if (loadButton) {
      loadButton.click();
      lastSynced = text;
      lastObserved = text;
    }
  };

  window.setInterval(syncFromLoadedJson, 250);
})();
