(() => {
  const BACKENDS = ["ssh-socks", "local-endpoint", "sing-box", "mihomo", "http-connect"];

  const esc = (value) => value == null ? "" : String(value);
  const get = (root, id) => root.querySelector(`#${id}`);
  const field = (label, id, type = "text") => `
    <label>${label}<input id="${id}" type="${type}" /></label>`;
  const select = (label, id, options) => `
    <label>${label}<select id="${id}">${options.map(v => `<option value="${v}">${v}</option>`).join("")}</select></label>`;

  function mount() {
    const textarea = document.getElementById("config");
    if (!textarea || document.getElementById("structured-config")) return;
    const host = textarea.parentElement;
    const panel = document.createElement("div");
    panel.id = "structured-config";
    panel.style.cssText = "margin:12px 0;padding:12px;border:1px solid #374151;border-radius:8px;background:#111827";
    panel.innerHTML = `
      <div style="font-weight:600;margin-bottom:10px">结构化配置</div>
      <div class="grid" style="margin:0">
        <div class="card">
          ${select("Backend", "form-backend", BACKENDS)}
          <div id="backend-options"></div>
        </div>
        <div class="card">
          <div style="font-weight:600;margin-bottom:8px">Egress Path</div>
          <div id="egress-options"></div>
        </div>
        <div class="card">
          <div style="font-weight:600;margin-bottom:8px">Listeners</div>
          ${field("SOCKS bind", "form-socks-bind")}
          ${field("SOCKS port", "form-socks-port", "number")}
          <div style="height:6px"></div>
          <label>HTTP listener enabled<input id="form-http-enabled" type="checkbox" style="width:auto" /></label>
          ${field("HTTP bind", "form-http-bind")}
          ${field("HTTP port", "form-http-port", "number")}
        </div>
        <div class="card">
          <div style="font-weight:600;margin-bottom:8px">Health</div>
          <label>Network required<input id="form-health-network" type="checkbox" style="width:auto" /></label>
          ${field("Timeout", "form-health-timeout", "number")}
          ${field("Retries", "form-health-retries", "number")}
          ${field("Backoff", "form-health-backoff", "number")}
          <label>Auto recover<input id="form-health-recover" type="checkbox" style="width:auto" /></label>
        </div>
        <div class="card">
          <div style="font-weight:600;margin-bottom:8px">Security</div>
          ${select("SSH host-key checking", "form-ssh-check", ["yes", "accept-new"])}
        </div>
      </div>
      <div style="display:flex;gap:8px;margin-top:10px">
        <button id="form-load" type="button" class="secondary" style="width:auto">从 JSON 同步</button>
        <button id="form-apply" type="button" style="width:auto">写入 JSON</button>
      </div>
      <div id="form-msg" class="status" style="margin-top:8px"></div>`;
    host.insertBefore(panel, textarea);

    get(panel, "form-load").addEventListener("click", () => syncFromJson(panel));
    get(panel, "form-apply").addEventListener("click", () => writeToJson(panel));
    get(panel, "form-backend").addEventListener("change", () => renderBackendOptions(panel));
    syncFromJson(panel);
  }

  function renderBackendOptions(panel, cfg = null) {
    const type = get(panel, "form-backend").value;
    const opts = (cfg && cfg.backend && cfg.backend.options) || {};
    let html = "";
    if (type === "local-endpoint") html = field("Proxy URL", "form-opt-proxy-url");
    else if (type === "http-connect") html = field("Proxy URL", "form-opt-proxy-url");
    else if (type === "sing-box" || type === "mihomo") html = field("Config path", "form-opt-config-path") + field("Binary", "form-opt-binary");
    else if (type === "ssh-socks") {
      html = field("Remote host", "form-ssh-host") + field("Remote user", "form-ssh-user") + field("Remote port", "form-ssh-port", "number") + field("Identity ref", "form-ssh-key") + field("Known hosts ref", "form-ssh-known");
    }
    get(panel, "backend-options").innerHTML = html;
    if (type === "local-endpoint" || type === "http-connect") get(panel, "form-opt-proxy-url").value = esc(opts.proxy_url || "");
    if (type === "sing-box" || type === "mihomo") {
      get(panel, "form-opt-config-path").value = esc(opts.config_path || "");
      get(panel, "form-opt-binary").value = esc(opts.binary || type);
    }
    if (type === "ssh-socks") {
      const e = cfg && cfg.egress_path;
      const t = (e && e.target) || {};
      get(panel, "form-ssh-host").value = esc(t.host || opts.remote_host || "");
      get(panel, "form-ssh-user").value = esc(t.user || opts.remote_user || "");
      get(panel, "form-ssh-port").value = t.port || opts.remote_port || 22;
      get(panel, "form-ssh-key").value = esc(t.identity_ref || opts.remote_ssh_key_ref || "");
      get(panel, "form-ssh-known").value = esc(t.known_hosts_ref || opts.ssh_known_hosts_ref || "");
    }
  }

  function renderEgress(panel, cfg) {
    const type = get(panel, "form-backend").value;
    const current = cfg && cfg.egress_path;
    if (type !== "ssh-socks") {
      get(panel, "egress-options").innerHTML = '<div class="muted">当前 Backend 不使用 SSH Egress Path。</div>';
      return;
    }
    const mode = current?.mode || "direct";
    get(panel, "egress-options").innerHTML = `
      ${select("Mode", "form-egress-mode", ["direct", "jump"])}
      ${select("DNS mode", "form-egress-dns", ["remote", "local"])}
      <div id="egress-target"></div>
      <div id="egress-jump"></div>`;
    get(panel, "form-egress-mode").value = mode;
    get(panel, "form-egress-dns").value = current?.dns_mode || "remote";
    const renderEndpoint = (container, prefix, value, requiredRef) => {
      container.innerHTML = field("Host", `${prefix}-host`) + field("User", `${prefix}-user`) + field("Port", `${prefix}-port`, "number") + field("Identity ref", `${prefix}-key") + field("Known hosts ref", `${prefix}-known`);
      const endpoint = value || {};
      get(container, `${prefix}-host`).value = esc(endpoint.host || "");
      get(container, `${prefix}-user`).value = esc(endpoint.user || "");
      get(container, `${prefix}-port`).value = endpoint.port || 22;
      get(container, `${prefix}-key`).value = esc(endpoint.identity_ref || "");
      get(container, `${prefix}-known`).value = esc(endpoint.known_hosts_ref || "");
      if (!requiredRef) {
        get(container, `${prefix}-key`).removeAttribute("required");
        get(container, `${prefix}-known`).removeAttribute("required");
      }
    };
    renderEndpoint(get(panel, "egress-target"), "target", current?.target, mode === "jump");
    renderEndpoint(get(panel, "egress-jump"), "jump", current?.jump, true);
    if (mode !== "jump") get(panel, "egress-jump").classList.add("hidden");
    get(panel, "form-egress-mode").addEventListener("change", () => renderEgress(panel, cfg));
  }

  function syncFromJson(panel) {
    try {
      const cfg = JSON.parse(document.getElementById("config").value || "{}");
      get(panel, "form-backend").value = cfg.backend?.type || "local-endpoint";
      renderBackendOptions(panel, cfg);
      renderEgress(panel, cfg);
      get(panel, "form-socks-bind").value = esc(cfg.listeners?.socks5?.bind || "127.0.0.1");
      get(panel, "form-socks-port").value = cfg.listeners?.socks5?.port || 1080;
      get(panel, "form-http-enabled").checked = cfg.listeners?.http?.enabled === true;
      get(panel, "form-http-bind").value = esc(cfg.listeners?.http?.bind || "127.0.0.1");
      get(panel, "form-http-port").value = cfg.listeners?.http?.port || 8118;
      get(panel, "form-health-network").checked = cfg.health?.network_required === true;
      get(panel, "form-health-timeout").value = cfg.health?.timeout || 5;
      get(panel, "form-health-retries").value = cfg.health?.retries || 0;
      get(panel, "form-health-backoff").value = cfg.health?.backoff || 0;
      get(panel, "form-health-recover").checked = cfg.health?.auto_recover === true;
      get(panel, "form-ssh-check").value = cfg.security?.ssh_host_key_checking || "yes";
      get(panel, "form-msg").textContent = "已从当前 JSON 同步。";
    } catch (err) {
      get(panel, "form-msg").textContent = `JSON 解析失败：${err.message}`;
    }
  }

  function writeToJson(panel) {
    try {
      const cfg = JSON.parse(document.getElementById("config").value || "{}");
      cfg.schema_version = 1;
      cfg.backend = cfg.backend || {};
      cfg.backend.type = get(panel, "form-backend").value;
      cfg.backend.options = cfg.backend.options || {};
      const type = cfg.backend.type;
      if (type === "ssh-socks") {
        cfg.backend.options.remote_host = get(panel, "form-ssh-host").value.trim();
        cfg.backend.options.remote_user = get(panel, "form-ssh-user").value.trim();
        cfg.backend.options.remote_port = Number(get(panel, "form-ssh-port").value);
        cfg.backend.options.remote_ssh_key_ref = get(panel, "form-ssh-key").value.trim();
        cfg.backend.options.ssh_known_hosts_ref = get(panel, "form-ssh-known").value.trim();
      } else if (type === "local-endpoint" || type === "http-connect") {
        cfg.backend.options.proxy_url = get(panel, "form-opt-proxy-url").value.trim();
      } else if (type === "sing-box" || type === "mihomo") {
        cfg.backend.options.config_path = get(panel, "form-opt-config-path").value.trim();
        cfg.backend.options.binary = get(panel, "form-opt-binary").value.trim() || type;
      }
      cfg.listeners = cfg.listeners || {};
      cfg.listeners.socks5 = { bind: get(panel, "form-socks-bind").value.trim(), port: Number(get(panel, "form-socks-port").value) };
      cfg.listeners.http = { enabled: get(panel, "form-http-enabled").checked, bind: get(panel, "form-http-bind").value.trim(), port: Number(get(panel, "form-http-port").value) };
      cfg.health = cfg.health || {};
      cfg.health.network_required = get(panel, "form-health-network").checked;
      cfg.health.timeout = Number(get(panel, "form-health-timeout").value);
      cfg.health.retries = Number(get(panel, "form-health-retries").value);
      cfg.health.backoff = Number(get(panel, "form-health-backoff").value);
      cfg.health.auto_recover = get(panel, "form-health-recover").checked;
      cfg.security = cfg.security || {};
      cfg.security.ssh_host_key_checking = get(panel, "form-ssh-check").value;
      if (type === "ssh-socks") {
        const mode = get(panel, "form-egress-mode")?.value || "direct";
        const target = { host: get(panel, "target-host").value.trim(), user: get(panel, "target-user").value.trim(), port: Number(get(panel, "target-port").value) };
        if (get(panel, "target-key").value.trim()) target.identity_ref = get(panel, "target-key").value.trim();
        if (get(panel, "target-known").value.trim()) target.known_hosts_ref = get(panel, "target-known").value.trim();
        cfg.egress_path = { transport: "ssh", mode, target, dns_mode: get(panel, "form-egress-dns")?.value || "remote" };
        if (mode === "jump") {
          cfg.egress_path.jump = { host: get(panel, "jump-host").value.trim(), user: get(panel, "jump-user").value.trim(), port: Number(get(panel, "jump-port").value), identity_ref: get(panel, "jump-key").value.trim(), known_hosts_ref: get(panel, "jump-known").value.trim() };
        }
      } else {
        delete cfg.egress_path;
      }
      document.getElementById("config").value = JSON.stringify(cfg, null, 2);
      get(panel, "form-msg").textContent = "结构化字段已写回 JSON；请继续执行“校验 + Diff”。";
    } catch (err) {
      get(panel, "form-msg").textContent = `写回失败：${err.message}`;
    }
  }

  if (document.readyState === "loading") document.addEventListener("DOMContentLoaded", mount);
  else mount();
})();
