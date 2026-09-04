#!/usr/bin/env python3
"""Convert the validated legacy shell-config environment to canonical typed JSON.

This module intentionally reads only an explicit allow-list of environment variables.
It never executes or parses shell syntax, never reads secret material, and fails closed
for unsupported backends or public listener exposure.
"""

from __future__ import annotations

import json
import os
import sys
from typing import Any


PUBLIC_BINDS = {"0.0.0.0", "::"}
SUPPORTED_BACKENDS = {"ssh-socks", "local-endpoint", "sing-box", "mihomo", "http-connect"}


def env(name: str, default: str = "") -> str:
    return os.environ.get(name, default)


def boolean(name: str, default: bool = False) -> bool:
    value = env(name, "true" if default else "false")
    if value not in {"true", "false"}:
        raise ValueError(f"{name} must be true or false")
    return value == "true"


def integer(name: str, default: int | None = None) -> int:
    raw = env(name, "" if default is None else str(default))
    if not raw.isdigit():
        raise ValueError(f"{name} must be an integer")
    return int(raw)


def split_csv(name: str) -> list[str]:
    raw = env(name)
    if not raw:
        return []
    values = [item for item in raw.split(",") if item]
    return list(dict.fromkeys(values))


def split_targets(name: str) -> list[str]:
    return split_csv(name)


def require(name: str) -> str:
    value = env(name)
    if not value:
        raise ValueError(f"{name} is required")
    return value


def backend_options(backend: str) -> dict[str, Any]:
    if backend == "ssh-socks":
        # REMOTE_SSH_KEY is a path/reference, not key material. Never read its contents.
        return {
            "remote_host": require("REMOTE_HOST"),
            "remote_user": require("REMOTE_USER"),
            "remote_port": integer("REMOTE_PORT", 22),
            "remote_ssh_key_ref": require("REMOTE_SSH_KEY"),
            "autossh_monitor_port": integer("AUTOSSH_MONITOR_PORT", 0),
            "ssh_server_alive_interval": integer("SSH_SERVER_ALIVE_INTERVAL", 30),
            "ssh_server_alive_count_max": integer("SSH_SERVER_ALIVE_COUNT_MAX", 3),
            "ssh_strict_host_key_checking": require("SSH_STRICT_HOST_KEY_CHECKING"),
            "ssh_known_hosts_ref": env("SSH_KNOWN_HOSTS", "~/.ssh/known_hosts"),
        }
    if backend == "local-endpoint":
        options: dict[str, Any] = {"proxy_url": require("LOCAL_PROXY_URL")}
        status_target = env("LOCAL_PROXY_STATUS_TARGET")
        if status_target:
            options["status_target"] = status_target
        return options
    if backend == "sing-box":
        return {
            "config_path": require("SING_BOX_CONFIG"),
            "binary": env("SING_BOX_BIN", "sing-box"),
        }
    if backend == "mihomo":
        return {
            "config_path": require("MIHOMO_CONFIG"),
            "binary": env("MIHOMO_BIN", "mihomo"),
        }
    if backend == "http-connect":
        return {"proxy_url": require("HTTP_CONNECT_PROXY_URL")}
    raise ValueError(f"unsupported backend: {backend}")


def rules() -> list[dict[str, Any]]:
    result: list[dict[str, Any]] = []
    raw = env("ROUTE_RULES")
    for line_no, line in enumerate(raw.splitlines(), 1):
        if not line:
            continue
        parts = line.split("|")
        if len(parts) != 4:
            raise ValueError(
                f"ROUTE_RULES line {line_no} must be priority|action|matcher|pattern"
            )
        priority, action, matcher, pattern = parts
        if not priority.isdigit():
            raise ValueError(f"ROUTE_RULES line {line_no} has invalid priority: {priority}")
        action = action.lower()
        if action not in {"direct", "proxy"}:
            raise ValueError(f"ROUTE_RULES line {line_no} has invalid action: {action}")
        if matcher not in {"exact", "suffix", "wildcard", "cidr"}:
            raise ValueError(f"ROUTE_RULES line {line_no} has invalid matcher: {matcher}")
        if not pattern or any(ch.isspace() for ch in pattern):
            raise ValueError(f"ROUTE_RULES line {line_no} has an invalid pattern")
        if matcher == "cidr" and "/" not in pattern:
            raise ValueError(f"ROUTE_RULES line {line_no} has an invalid CIDR: {pattern}")
        result.append(
            {
                "priority": int(priority),
                "action": action,
                "matcher": matcher,
                "pattern": pattern,
            }
        )
    return sorted(result, key=lambda item: (item["priority"], item["action"], item["matcher"], item["pattern"]))


def build() -> dict[str, Any]:
    backend = require("BACKEND")
    if backend not in SUPPORTED_BACKENDS:
        raise ValueError(f"unsupported backend: {backend}")

    socks_bind = require("SOCKS_BIND")
    http_bind = require("HTTP_BIND")
    if socks_bind in PUBLIC_BINDS or (boolean("HTTP_ENABLED") and http_bind in PUBLIC_BINDS):
        raise ValueError(
            "public listener exposure cannot be migrated implicitly; keep listeners on loopback and make any exposure explicit in typed config"
        )

    return {
        "schema_version": 1,
        "profile": env("PA_ACTIVE_PROFILE", "default"),
        "backend": {"type": backend, "options": backend_options(backend)},
        "listeners": {
            "socks5": {"bind": socks_bind, "port": integer("SOCKS_PORT")},
            "http": {
                "enabled": boolean("HTTP_ENABLED"),
                "bind": http_bind,
                "port": integer("HTTP_PORT"),
            },
        },
        "routing": {
            "direct_cidrs": split_csv("DIRECT_CIDRS"),
            "direct_domains": split_csv("DIRECT_DOMAINS"),
            "no_proxy_extra": split_csv("NO_PROXY_EXTRA"),
            "rules": rules(),
        },
        "health": {
            "network_required": boolean("HEALTH_NETWORK_REQUIRED"),
            "timeout": integer("HEALTH_TIMEOUT"),
            "retries": integer("HEALTH_RETRIES"),
            "backoff": integer("HEALTH_BACKOFF"),
            "auto_recover": boolean("HEALTH_AUTO_RECOVER"),
            "targets": split_targets("HEALTH_TARGETS"),
        },
        "integrations": {
            "git": boolean("INTEGRATE_GIT"),
            "docker": boolean("INTEGRATE_DOCKER"),
            "pip": boolean("INTEGRATE_PIP"),
            "npm": boolean("INTEGRATE_NPM"),
        },
        "security": {
            "ssh_host_key_checking": require("SSH_STRICT_HOST_KEY_CHECKING"),
            "allow_public_listener": False,
        },
    }


def main() -> int:
    try:
        document = build()
    except ValueError as exc:
        print(f"legacy typed export: ERROR: {exc}", file=sys.stderr)
        return 2
    json.dump(document, sys.stdout, ensure_ascii=False, indent=2, sort_keys=True)
    sys.stdout.write("\n")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
