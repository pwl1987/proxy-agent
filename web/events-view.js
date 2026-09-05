(() => {
  const app = document.getElementById("app");
  if (!app || app.dataset.eventsViewBound === "1") return;
  app.dataset.eventsViewBound = "1";

  const card = document.createElement("div");
  card.className = "card wide";
  card.innerHTML = '<div class="muted">Audit Events</div><div id="events-view" class="status" style="margin-top:8px">加载中…</div>';
  const grid = app.querySelector(".grid:nth-of-type(2)") || app.lastElementChild;
  if (grid) grid.appendChild(card); else app.appendChild(card);

  const output = card.querySelector("#events-view");
  const render = (events) => {
    if (!Array.isArray(events) || events.length === 0) {
      output.textContent = "暂无审计事件。";
      return;
    }
    output.replaceChildren(...events.slice(-30).reverse().map((event) => {
      const row = document.createElement("div");
      row.className = "diff-item";
      row.textContent = JSON.stringify(event);
      return row;
    }));
  };

  const loadEvents = async () => {
    try {
      const response = await fetch("/api/v1/events", { credentials: "same-origin" });
      const text = await response.text();
      let payload;
      try {
        payload = text ? JSON.parse(text) : null;
      } catch (_) {
        throw new Error(`HTTP ${response.status}: invalid JSON`);
      }
      if (!response.ok) throw new Error(payload?.error?.message || `HTTP ${response.status}`);
      render(payload?.data);
    } catch (error) {
      output.textContent = `事件加载失败：${error.message}`;
    }
  };

  const waitForAuthentication = () => {
    const login = document.getElementById("login");
    if (login && login.classList.contains("hidden")) {
      void loadEvents();
      return;
    }
    window.setTimeout(waitForAuthentication, 250);
  };

  waitForAuthentication();
})();
