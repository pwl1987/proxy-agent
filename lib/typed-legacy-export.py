#!/usr/bin/env python3
"""Render canonical typed config into the legacy runtime .conf format.

Only typed fields are rendered. Secret references remain references and their contents
are never read. Public listeners are rejected unless explicitly allowed by policy.
"""
from __future__ import annotations

import json
import shlex
import sys
from typing import Any

PUBLIC_BINDS = {"0.0.0.0", "::"}
SUPPORTED_BACKENDS = {"ssh-socks", "local-endpoint", "sing-box", "mihomo", "http-connect"}


def require(obj: dict[str, Any], key: str, path: str) -> Any:
    if key not in obj:
        raise ValueError(f"missing required field: {path}.{key}")
    return obj[key]


def assignment(name: str, value: Any) -> str:
    if isinstance(value, bool):
        return f'{name}="{'true' if value else 'false'}"'
    return f"{name}={shlex.quote(str(value))}"


def validate_file_ref(value: Any, path: str, required: bool = True) -> str | None:
    if value in (None, "") and not required:
        return None
    if not isinstance(value, str) or not value.startswith("file:") or len(value) <= 5:
        raise ValueError(f"{path} must be a non-empty file: reference")
    return value[5:]


def validate_host(value: Any, path: str) -> str:
    if not isinstance(value, str) or not value or any(ch.isspace() for ch in value):
        raise ValueError(f"{path} must be a non-empty string without whitespace")
    return value


def validate_user(value: Any, path: str) -> str:
    if not isinstance(value, str) or not value or any(ch.isspace() for ch in value):
        raise ValueError(f"{path} must be a non-empty string without whitespace")
    return value


def validate_port(value: Any, path: str) -> int:
    if not isinstance(value, int) or isinstance(value, bool) or not 1 <= value <= 65535:
        raise ValueError(f"{path} must be an integer between 1 and 65535")
    return value


def validate_ssh_endpoint(value: Any, path: str, identity_required: bool, known_hosts_required: bool) -> dict[str, Any]:
    if not isinstance(value, dict):
        raise ValueError(f"{path} must be an object")
    allowed = {"host", "user", "port", "identity_ref", "known_hosts_ref"}
    unknown = sorted(set(value) - allowed)
    if unknown:
        raise ValueError(f"{path} contains unknown fields: {','.join(unknown)}")
    target = {
        "host": validate_host(require(value, "host", path), f"{path}.host"),
        "user": validate_user(require(value, "user", path), f"{path}.user"),
        "port": validate_port(require(value, "port", path), f"{path}.port"),
    }
    identity = validate_file_ref(value.get("identity_ref"), f"{path}.identity_ref", identity_required)
    known_hosts = validate_file_ref(value.get("known_hosts_ref"), f"{path}.known_hosts_ref", known_hosts_required)
    if identity is not None:
        target["identity_ref"] = identity
    if known_hosts is not None:
        target["known_hosts_ref"] = known_hosts
    return target


def validate_direct_egress(config: dict[str, Any], backend: dict[str, Any]) -> dict[str, Any] | None:
    path = config.get("egress_path")
    if path is None:
        return None
    if not isinstance(path, dict):
        raise ValueError("egress_path must be an object")
    allowed = {"transport", "mode", "target", "jump", "dns_mode"}
    unknown = sorted(set(path) - allowed)
    if unknown:
        raise ValueError(f"egress_path contains unknown fields: {','.join(unknown)}")
    if path.get("transport") != "ssh":
        raise ValueError("egress_path.transport must be ssh")
    mode = path.get("mode")
    if mode not in {"direct", "jump"}:
        raise ValueError("egress_path.mode must be direct or jump")

    # 0.5.0 direct configs remain valid: identity/known-host references are optional here.
    target = validate_ssh_endpoint(path.get("target"), "egress_path.target", mode == "jump", mode == "jump")
    dns_mode = path.get("dns_mode", "remote")
    if dns_mode not in {"local", "remote"}:
        raise ValueError("egress_path.dns_mode must be local or remote")

    if mode == "direct":
        if "jump" in path:
            raise ValueError("egress_path.jump is not allowed for direct mode")
        if backend.get("type") != "ssh-socks":
            raise ValueError("egress_path requires backend.type=ssh-socks")
        options = backend.get("options", {})
        if not isinstance(options, dict):
            raise ValueError("backend.options must be an object")
        legacy_map = {"remote_host": target["host"], "remote_user": target["user"], "remote_port": target["port"]}
        for key, canonical in legacy_map.items():
            if key in options and options[key] not in (None, "") and options[key] != canonical:
                raise ValueError(f"egress_path.target.{key.removeprefix('remote_')} conflicts with backend.options.{key}")
        return {"mode": mode, "target": target, "dns_mode": dns_mode}

    if "jump" not in path:
        raise ValueError("egress_path.jump is required for jump mode")
    jump = validate_ssh_endpoint(path["jump"], "egress_path.jump", True, True)
    if jump["host"] == target["host"] and jump["port"] == target["port"] and jump["user"] == target["user"]:
        raise ValueError("egress_path.jump and target must not identify the same endpoint")
    if backend.get("type") != "ssh-socks":
        raise ValueError("egress_path requires backend.type=ssh-socks")
    return {"mode": mode, "target": target, "jump": jump, "dns_mode": dns_mode}


def validate(config: dict[str, Any]) -> dict[str, Any] | None:
    if config.get("schema_version") != 1:
        raise ValueError("schema_version must be 1")
    for section in ("backend", "listeners", "health", "integrations", "routing", "security"):
        if not isinstance(config.get(section), dict):
            raise ValueError(f"{section} must be an object")
    backend = config["backend"]
    backend_type = require(backend, "type", "backend")
    if backend_type not in SUPPORTED_BACKENDS:
        raise ValueError(f"unsupported backend: {backend_type}")
    listeners = config["listeners"]
    socks = require(listeners, "socks5", "listeners")
    if not isinstance(socks, dict):
        raise ValueError("listeners.socks5 must be an object")
    http = listeners.get("http", {"enabled": False, "bind": "127.0.0.1", "port": 8118})
    for name, listener in (("socks5", socks), ("http", http)):
        if listener.get("bind") in PUBLIC_BINDS and name == "socks5":
            raise ValueError("public SOCKS listener requires explicit deployment policy")
        if name == "http" and listener.get("enabled") and listener.get("bind") in PUBLIC_BINDS:
            raise ValueError("public HTTP listener requires explicit deployment policy")
    if config["security"].get("allow_public_listener") is True and (
        socks.get("bind") in PUBLIC_BINDS or (http.get("enabled") and http.get("bind") in PUBLIC_BINDS)
    ):
        raise ValueError("authenticated public deployment policy is not implemented by the legacy runtime")
    return validate_direct_egress(config, backend)


def build(config: dict[str, Any]) -> str:
    egress = validate(config)
    backend = config["backend"]
    options = backend.get("options", {})
    listeners = config["listeners"]
    socks = listeners["socks5"]
    http = listeners.get("http", {})
    routing = config["routing"]
    health = config["health"]
    integrations = config["integrations"]
    security = config["security"]

    lines = ["# Generated by proxy-agent from canonical typed config", assignment("BACKEND", backend["type"])]
    if backend["type"] == "ssh-socks":
        if egress is not None:
            target = egress["target"]
            mapping = {
                "REMOTE_HOST": target["host"], "REMOTE_USER": target["user"], "REMOTE_PORT": target["port"],
                "REMOTE_SSH_KEY": target.get("identity_ref", options.get("remote_ssh_key_ref", "")),
                "AUTOSSH_MONITOR_PORT": options.get("autossh_monitor_port", 0),
                "SSH_SERVER_ALIVE_INTERVAL": options.get("ssh_server_alive_interval", 30),
                "SSH_SERVER_ALIVE_COUNT_MAX": options.get("ssh_server_alive_count_max", 3),
                "SSH_STRICT_HOST_KEY_CHECKING": options.get("ssh_strict_host_key_checking", security.get("ssh_host_key_checking", "yes")),
                "SSH_KNOWN_HOSTS": target.get("known_hosts_ref", options.get("ssh_known_hosts_ref", "~/.ssh/known_hosts")),
                "SSH_DNS_MODE": egress.get("dns_mode", "remote"),
                "SSH_EGRESS_MODE": egress["mode"],
            }
            if egress["mode"] == "jump":
                jump = egress["jump"]
                mapping.update({
                    "SSH_JUMP_HOST": jump["host"], "SSH_JUMP_USER": jump["user"], "SSH_JUMP_PORT": jump["port"],
                    "SSH_JUMP_KEY": jump["identity_ref"], "SSH_JUMP_KNOWN_HOSTS": jump["known_hosts_ref"],
                    "SSH_TARGET_KEY": target["identity_ref"], "SSH_TARGET_KNOWN_HOSTS": target["known_hosts_ref"],
                })
        else:
            mapping = {
                "REMOTE_HOST": options.get("remote_host", ""), "REMOTE_USER": options.get("remote_user", ""), "REMOTE_PORT": options.get("remote_port", 22),
                "REMOTE_SSH_KEY": options.get("remote_ssh_key_ref", ""), "AUTOSSH_MONITOR_PORT": options.get("autossh_monitor_port", 0),
                "SSH_SERVER_ALIVE_INTERVAL": options.get("ssh_server_alive_interval", 30), "SSH_SERVER_ALIVE_COUNT_MAX": options.get("ssh_server_alive_count_max", 3),
                "SSH_STRICT_HOST_KEY_CHECKING": options.get("ssh_strict_host_key_checking", security.get("ssh_host_key_checking", "yes")),
                "SSH_KNOWN_HOSTS": options.get("ssh_known_hosts_ref", "~/.ssh/known_hosts"), "SSH_DNS_MODE": "remote", "SSH_EGRESS_MODE": "direct",
            }
    elif backend["type"] == "local-endpoint":
        mapping = {"LOCAL_PROXY_URL": options.get("proxy_url", ""), "LOCAL_PROXY_STATUS_TARGET": options.get("status_target", "")}
    elif backend["type"] == "sing-box":
        mapping = {"SING_BOX_CONFIG": options.get("config_path", ""), "SING_BOX_BIN": options.get("binary", "sing-box")}
    elif backend["type"] == "mihomo":
        mapping = {"MIHOMO_CONFIG": options.get("config_path", ""), "MIHOMO_BIN": options.get("binary", "mihomo")}
    else:
        mapping = {"HTTP_CONNECT_PROXY_URL": options.get("proxy_url", "")}
    lines.extend(assignment(k, v) for k, v in mapping.items())
    lines.extend([
        assignment("SOCKS_BIND", socks["bind"]), assignment("SOCKS_PORT", socks["port"]),
        assignment("HTTP_ENABLED", http.get("enabled", False)), assignment("HTTP_BIND", http.get("bind", "127.0.0.1")),
        assignment("HTTP_PORT", http.get("port", 8118)), assignment("SSH_STRICT_HOST_KEY_CHECKING", security.get("ssh_host_key_checking", "yes")),
    ])
    lines.extend([
        assignment("DIRECT_CIDRS", ",".join(routing.get("direct_cidrs", []))), assignment("DIRECT_DOMAINS", ",".join(routing.get("direct_domains", []))),
        assignment("NO_PROXY_EXTRA", ",".join(routing.get("no_proxy_extra", []))),
    ])
    rules = routing.get("rules", [])
    legacy_rules = [f'{rule["priority"]}|{rule["action"].upper()}|{rule["matcher"]}|{rule["pattern"]}' for rule in sorted(rules, key=lambda x: (x["priority"], x["action"], x["matcher"], x["pattern"]))]
    lines.append(assignment("ROUTE_RULES", "\n".join(legacy_rules)))
    lines.extend([
        assignment("HEALTH_TARGETS", ",".join(health.get("targets", []))), assignment("HEALTH_NETWORK_REQUIRED", health["network_required"]),
        assignment("HEALTH_TIMEOUT", health["timeout"]), assignment("HEALTH_RETRIES", health["retries"]), assignment("HEALTH_BACKOFF", health["backoff"]),
        assignment("HEALTH_AUTO_RECOVER", health["auto_recover"]), assignment("INTEGRATE_GIT", integrations["git"]), assignment("INTEGRATE_DOCKER", integrations["docker"]),
        assignment("INTEGRATE_PIP", integrations["pip"]), assignment("INTEGRATE_NPM", integrations["npm"]),
    ])
    return "\n".join(lines) + "\n"


def main() -> int:
    try:
        config = json.load(sys.stdin)
        if not isinstance(config, dict):
            raise ValueError("typed config must be a JSON object")
        sys.stdout.write(build(config))
    except (OSError, ValueError, json.JSONDecodeError) as exc:
        print(f"typed legacy export: ERROR: {exc}", file=sys.stderr)
        return 2
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
