(() => {
  const BACKENDS = ["ssh-socks", "local-endpoint", "sing-box", "mihomo", "http-connect"];

  const esc = (value) => value == null ? "" : String(value);
  const get = (root, id) => root.querySelector(`#${id}`);
  const field = (label, id, type = "text") => `<label>${label}<input id="${id}" type="${type}" /></label>`;
  const select = (label, id, options) => `<label>${label}<select id="${id}">${options.map(v => `<option value="${v}">${v}</option>`).join("")}</select></label>`;

  function mount() {
    const textarea = document.getElementById("config");
    if (!textarea || document.getElementById("structured-config")) return;
    const panel = document.createElement("div");
    panel.id = "structured-config";
    panel.style.cssText = "margin:12px 0;padding:12px;border:1px solid #374151;border-radius:8px;background:#111827";
    panel.innerHTML = `<div style="font-weight:600;margin-bottom:10px">结构化配置</div><div class="grid" style="margin:0">
      <div class="card">${select("Backend", "form-backend", BACKENDS)}<div id="backend-options"></div></div>
      <div class="card"><div style="font-weight:600;margin-bottom:8px">Egress Path</div><div id="egress-options"></div></div>
      <div class="card"><div style="font-weight:600;margin-bottom:8px">Listeners</div>${field("SOCKS bind", "form-socks-bind")}${field("SOCKS port", "form-socks-port", "number")}<label>HTTP listener enabled<input id="form-http-enabled" type="checkbox" style="width:auto" /></label>${field("HTTP bind", "form-http-bind")}${field("HTTP port", "form-http-port", "number")}</div>
      <div class="card"><div style="font-weight:600;margin-bottom:8px">Health</div><label>Network required<input id="form-health-network" type="checkbox" style="width:auto" /></label>${field("Timeout", "form-health-timeout", "number")}${field("Retries", "form-health-retries", "number")}${field("Backoff", "form-health-backoff", "number")}<label>Auto recover<input id="form-health-recover" type="checkbox" style="width:auto" /></label></div>
      <div class="card"><div style="font-weight:600;margin-bottom:8px">Security</div>${select("SSH host-key checking", "form-ssh-check", ["yes", "accept-new"])}</div>
    </div><div style="display:flex;gap:8px;margin-top:10px"><button id="form-load" type="button" class="secondary" style="width:auto">从 JSON 同步</button><button id="form-apply" type="button" style="width:auto">写入 JSON</button></div><div id="form-msg" class="status" style="margin-top:8px"></div>`;
    textarea.parentElement.insertBefore(panel, textarea);
    get(panel, "form-load").addEventListener("click", () => syncFromJson(panel));
    get(panel, "form-apply").addEventListener("click", () => writeToJson(panel));
    get(panel, "form-backend").addEventListener("change", () => { renderBackendOptions(panel); renderEgress(panel, null); });
    syncFromJson(panel);
  }

  function renderBackendOptions(panel, cfg = null) {
    const type = get(panel, "form-backend").value;
    const opts = (cfg && cfg.backend && cfg.backend.options) || {};
    let html = "";
    if (type === "local-endpoint" || type === "http-connect") html = field("Proxy URL", "form-opt-proxy-url");
    else if (type === "sing-box" || type === "mihomo") html = field("Config path", "form-opt-config-path") + field("Binary", "form-opt-binary");
    else if (type === "ssh-socks") html = field("Remote host", "form-ssh-host") + field("Remote user", "form-ssh-user") + field("Remote port", "form-ssh-port", "number") + field("Identity ref", "form-ssh-key") + field("Known hosts ref", "form-ssh-known");
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

  function endpointEditor(prefix) {
    return field("Host", `${prefix}-host`) + field("User", `${prefix}-user`) + field("Port", `${prefix}-port`, "number") + field("Identity ref", `${prefix}-key`) + field("Known hosts ref", `${prefix}-known`);
  }

  function readEndpoint(panel, prefix) {
    const endpoint = { host: get(panel, `${prefix}-host`).value.trim(), user: get(panel, `${prefix}-user`).value.trim(), port: Number(get(panel, `${prefix}-port`).value) };
    const key = get(panel, `${prefix}-key`).value.trim();
    const known = get(panel, `${prefix}-known`).value.trim();
    if (key) endpoint.identity_ref = key;
    if (known) endpoint.known_hosts_ref = known;
    return endpoint;
  }

  function fillEndpoint(panel, prefix, value) {
    const endpoint = value || {};
    get(panel, `${prefix}-host`).value = esc(endpoint.host || "");
    get(panel, `${prefix}-user`).value = esc(endpoint.user || "");
    get(panel, `${prefix}-port`).value = endpoint.port || 22;
    get(panel, `${prefix}-key`).value = esc(endpoint.identity_ref || "");
    get(panel, `${prefix}-known`).value = esc(endpoint.known_hosts_ref || "");
  }

  function currentEgressFromForm(panel) {
    const mode = get(panel, "form-egress-mode")?.value || "direct";
    const current = { transport: "ssh", mode, target: readEndpoint(panel, "target"), dns_mode: get(panel, "form-egress-dns")?.value || "remote" };
    if (mode === "jump") current.jump = readEndpoint(panel, "jump");
    return current;
  }

  function renderEgress(panel, cfg) {
    const type = get(panel, "form-backend").value;
    const current = cfg && cfg.egress_path;
    if (type !== "ssh-socks") {
      get(panel, "egress-options").innerHTML = '<div class="muted">当前 Backend 不使用 SSH Egress Path。</div>';
      return;
    }
    const mode = current?.mode || "direct";
    get(panel, "egress-options").innerHTML = `${select("Mode", "form-egress-mode", ["direct", "jump"])}${select("DNS mode", "form-egress-dns", ["remote", "local"])}<div id="egress-target">${endpointEditor("target")}</div><div id="egress-jump">${endpointEditor("jump")}</div>`;
    get(panel, "form-egress-mode").value = mode;
    get(panel, "form-egress-dns").value = current?.dns_mode || "remote";
    fillEndpoint(panel, "target", current?.target);
    fillEndpoint(panel, "jump", current?.jump);
    get(panel, "egress-jump").classList.toggle("hidden", mode !== "jump");
    get(panel, "form-egress-mode").addEventListener("change", () => {
      const preserved = currentEgressFromForm(panel);
      preserved.mode = get(panel, "form-egress-mode").value;
      get(panel, "egress-options").innerHTML = `${select("Mode", "form-egress-mode", ["direct", "jump"])}${select("DNS mode", "form-egress-dns", ["remote", "local"])}<div id="egress-target">${endpointEditor("target")}</div><div id="egress-jump">${endpointEditor("jump")}</div>`;
      get(panel, "form-egress-mode").value = preserved.mode;
      get(panel, "form-egress-dns").value = preserved.dns_mode;
      fillEndpoint(panel, "target", preserved.target);
      fillEndpoint(panel, "jump", preserved.jump);
      get(panel, "egress-jump").classList.toggle("hidden", preserved.mode !== "jump");
      get(panel, "form-egress-mode").addEventListener("change", () => renderEgress(panel, { egress_path: currentEgressFromForm(panel) }));
    });
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
        const target = readEndpoint(panel, "target");
        Object.assign(cfg.backend.options, { remote_host: target.host, remote_user: target.user, remote_port: target.port, remote_ssh_key_ref: target.identity_ref || "", ssh_known_hosts_ref: target.known_hosts_ref || "" });
      } else if (type === "local-endpoint" || type === "http-connect") cfg.backend.options.proxy_url = get(panel, "form-opt-proxy-url").value.trim();
      else if (type === "sing-box" || type === "mihomo") { cfg.backend.options.config_path = get(panel, "form-opt-config-path").value.trim(); cfg.backend.options.binary = get(panel, "form-opt-binary").value.trim() || type; }
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
      if (type === "ssh-socks") cfg.egress_path = currentEgressFromForm(panel);
      else delete cfg.egress_path;
      document.getElementById("config").value = JSON.stringify(cfg, null, 2);
      get(panel, "form-msg").textContent = "结构化字段已写回 JSON；请继续执行“校验 + Diff”。";
    } catch (err) {
      get(panel, "form-msg").textContent = `写回失败：${err.message}`;
    }
  }

  if (document.readyState === "loading") document.addEventListener("DOMContentLoaded", mount);
  else mount();
})();
