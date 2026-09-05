(() => {
  const profileInput = document.getElementById("profile");
  if (!profileInput || profileInput.dataset.profileSelectorBound === "1") return;
  profileInput.dataset.profileSelectorBound = "1";

  const placeholder = "Profile（留空使用默认 profile）";
  const select = document.createElement("select");
  select.id = profileInput.id;
  select.name = profileInput.name || "profile";
  select.className = profileInput.className;
  select.style.cssText = profileInput.style.cssText;
  select.dataset.profileSelector = "1";
  select.setAttribute("aria-label", placeholder);

  const empty = document.createElement("option");
  empty.value = "";
  empty.textContent = placeholder;
  select.appendChild(empty);
  profileInput.replaceWith(select);

  const setMessage = (text) => {
    const msg = document.getElementById("actionMsg");
    if (msg && text) {
      msg.textContent = text;
      msg.className = "status warn";
    }
  };

  const loadProfiles = async () => {
    try {
      const response = await fetch("/api/v1/profiles", { credentials: "same-origin" });
      const text = await response.text();
      let payload;
      try {
        payload = text ? JSON.parse(text) : null;
      } catch (_) {
        throw new Error(`HTTP ${response.status}: invalid JSON`);
      }
      if (!response.ok) {
        throw new Error(payload?.error?.message || `HTTP ${response.status}`);
      }
      const names = Array.isArray(payload?.data?.profiles) ? payload.data.profiles : [];
      for (const name of names) {
        const option = document.createElement("option");
        option.value = name;
        option.textContent = name;
        select.appendChild(option);
      }
      if (names.length === 0) {
        select.title = "当前没有已发现的 named profile；空值继续表示默认 profile。";
      }
    } catch (error) {
      select.value = "";
      setMessage(`Profile discovery failed: ${error.message}；继续使用默认 profile。`);
    }
  };

  loadProfiles();
})();
