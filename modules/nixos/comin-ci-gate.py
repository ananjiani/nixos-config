#!/usr/bin/env python3
"""Comin build-confirmer gate for NixCI + cache.nix-ci.com.

Approves a pending Comin *build* confirmation only when NixCI is green for
the exact (branch, commit) of the pending generation AND the authenticated
cache holds (or credibly held) that generation's output-path narinfo.
Not a full-closure guarantee: References are parsed for validity, never
walked. Native Nix may still build missing dependencies locally while the
cache is healthy. Outcomes per timer run:

  approve   Confirm(generationUuid, for="build") after a second GetState
            re-check (same UUID, explicit isSuspended=false).
  wait      Exit 0; the same UUID is retried next timer tick. CI errors,
            missing root narinfo (404), invalid metadata, unexpected 4xx,
            and an unclear isSuspended all wait. Each tick fetches that
            same root narinfo again; there is no walk progress to persist.
  fallback  approve + comin_nixci_cache_error metric when the cache is
            unreachable (transport/timeout/5xx) or credentials fail
            (401/403, missing netrc). Local/remote builds then cover it.

Comin is driven through grpcurl -emit-defaults against the pinned proto
(camelCase JSON). State.isSuspended is a BoolValue wrapper: grpcurl emits
an explicit boolean or null; anything but an explicit false blocks approval.

No credentials appear in argv, logs, or the state file. The Authorization
header is attached preemptively (Basic, base64 stdlib) and only to the
configured HTTPS cache origin; redirects are never followed.
"""

from __future__ import annotations

import base64
import json
import netrc
import os
import re
import subprocess
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
from pathlib import Path
from typing import Any

NIX32 = "0123456789abcdfghijklmnpqrsvwxyz"
STORE_RE = re.compile(rf"^/nix/store/([{NIX32}]{{32}})-[0-9A-Za-z._?+=-]+$")
BASENAME_RE = re.compile(rf"^([{NIX32}]{{32}})-[0-9A-Za-z._?+=-]+$")
NARHASH_RE = re.compile(rf"^sha256:[{NIX32}]{{52}}$")
COMMIT_RE = re.compile(r"^[0-9a-f]{40}$|^[0-9a-f]{64}$")

STATE_FILE = "state.json"
METRIC_FILE = "comin-ci-gate.prom"
HEALTH_PATH = "nix-cache-info"

HTTP_TIMEOUT = 8.0
CI_TIMEOUT = 15.0
GRPC_TIMEOUT = 15.0
MAX_BODY = 262144  # bytes; narinfo/JSON bodies are far smaller


def log(msg: str) -> None:
    print(f"comin-ci-gate: {msg}", file=sys.stderr, flush=True)


# ---------------------------------------------------------------- store paths


def store_hash(path: str) -> str | None:
    match = STORE_RE.fullmatch(path)
    return match.group(1) if match else None


def ref_to_store_path(ref: str) -> str | None:
    """Accept '/nix/store/<hash>-<name>' or '<hash>-<name>' basenames only."""
    ref = ref.strip()
    if STORE_RE.fullmatch(ref):
        return ref
    if BASENAME_RE.fullmatch(ref):
        return f"/nix/store/{ref}"
    return None


def narinfo_url(cache_url: str, path: str) -> str | None:
    """Requests are built from the 32-char hash only, never from metadata."""
    digest = store_hash(path)
    return f"{cache_url}/{digest}.narinfo" if digest else None


# --------------------------------------------------------------- cache format


def parse_narinfo(body: str, expect_path: str | None) -> list[str] | None:
    """Validate a narinfo; return referenced store paths or None if invalid.

    Mandatory: StorePath (matching when expect_path is given), nonempty URL,
    NarHash 'sha256:<52 nix-base32 chars>', NarSize nonnegative integer.
    'References' is optional: a missing field or empty value means no refs
    (real cache.nixos.org leaf narinfos omit it). FileHash/FileSize/
    Compression/Signature/Deriver are optional. URL is validated but never
    used to build requests.
    """
    fields: dict[str, str] = {}
    for line in body.splitlines():
        key, sep, value = line.partition(":")
        if sep and key in ("StorePath", "URL", "NarHash", "NarSize", "References"):
            fields[key] = value.strip()
    store_path = fields.get("StorePath", "")
    if expect_path is not None:
        if store_path != expect_path:
            return None
    elif not STORE_RE.fullmatch(store_path):
        return None
    if not fields.get("URL"):
        return None
    if not NARHASH_RE.fullmatch(fields.get("NarHash", "")):
        return None
    try:
        nar_size = int(fields["NarSize"])
    except (KeyError, ValueError):
        return None
    if nar_size < 0:
        return None
    refs: list[str] = []
    for token in fields.get("References", "").split():
        ref = ref_to_store_path(token)
        if ref is None:
            return None
        refs.append(ref)
    return refs


def parse_cache_info(body: str) -> bool:
    for line in body.splitlines():
        if line.startswith("StoreDir:"):
            return line.partition(":")[2].strip() == "/nix/store"
    return False


# ----------------------------------------------------------------- NixCI API


def check_ci(payload: Any, commit: str, ref: str, check_attr: str) -> str:
    """Return '' when NixCI is green for the exact commit/ref, else a reason."""
    if not isinstance(payload, dict):
        return "NixCI payload malformed"
    if payload.get("commit") != commit:
        return "NixCI commit mismatch"
    if payload.get("ref") != ref:
        return "NixCI ref mismatch"
    if payload.get("status") != "success":
        return f"NixCI suite {payload.get('status')!r}"
    runs = payload.get("runs")
    if not isinstance(runs, list) or not runs:
        return "NixCI runs empty"
    config_ok = show_ok = host_ok = False
    for run in runs:
        if not isinstance(run, dict):
            return "NixCI run malformed"
        rtype = run.get("type")
        status = run.get("status")
        if rtype == "config":
            if status != "success":
                return f"NixCI config {status!r}"
            config_ok = True
        elif rtype == "show":
            if status not in ("success", "cached"):
                return f"NixCI show {status!r}"
            show_ok = True
        elif rtype == "build" and run.get("attribute") == check_attr:
            if status not in ("success", "cached"):
                return f"NixCI {check_attr} {status!r}"
            host_ok = True
    if not config_ok:
        return "NixCI config run missing"
    if not show_ok:
        return "NixCI show run missing"
    if not host_ok:
        return f"NixCI {check_attr} run missing"
    return ""


# ---------------------------------------------------------------- Comin API


def suspension(state: Any) -> bool | None:
    """Explicit bool only: grpcurl emits BoolValue as bool or null."""
    value = state.get("isSuspended") if isinstance(state, dict) else None
    return value if isinstance(value, bool) else None


def pending_build(state: Any) -> tuple[str, dict[str, Any] | None]:
    """Return (submitted uuid, matched generation or None); '' means none."""
    confirmer = state.get("buildConfirmer")
    uuid = confirmer.get("submitted") if isinstance(confirmer, dict) else None
    if not isinstance(uuid, str) or not uuid:
        return "", None
    store = state.get("store")
    generations = store.get("generations") if isinstance(store, dict) else None
    if not isinstance(generations, list):
        return uuid, None
    for gen in generations:
        if isinstance(gen, dict) and gen.get("uuid") == uuid:
            return uuid, gen
    return uuid, None


def grpc_call(
    cfg: dict[str, str], method: str, payload: dict[str, Any], runner: Any
) -> tuple[int, str, str]:
    cmd = [
        cfg["grpcurl"],
        "-plaintext",
        "-emit-defaults",
        "-import-path",
        cfg["proto_import"],
        "-proto",
        Path(cfg["proto"]).name,
        "-d",
        json.dumps(payload, separators=(",", ":")),
        "unix://" + cfg["sock"].removeprefix("unix://"),
        method,
    ]
    try:
        proc = runner(cmd, check=False, capture_output=True, text=True, timeout=GRPC_TIMEOUT)
    except subprocess.TimeoutExpired:
        return 1, "", "grpcurl timeout"
    except OSError as exc:
        return 1, "", f"grpcurl failed: {exc}"
    return proc.returncode, proc.stdout or "", proc.stderr or ""


def comin_get_state(cfg: dict[str, str], runner: Any) -> Any | None:
    code, out, err = grpc_call(cfg, "protobuf.Comin/GetState", {}, runner)
    if code != 0:
        log(f"GetState failed: {err.strip()[:200]}")
        return None
    try:
        return json.loads(out)
    except json.JSONDecodeError:
        log("GetState returned invalid JSON")
        return None


def confirm_build(cfg: dict[str, str], runner: Any, uuid: str) -> bool:
    code, _out, err = grpc_call(
        cfg, "protobuf.Comin/Confirm", {"generationUuid": uuid, "for": "build"}, runner
    )
    if code != 0:
        log(f"Confirm failed: {err.strip()[:200]}")
        return False
    return True


# --------------------------------------------------------------------- HTTP


class HttpResult:
    __slots__ = ("status", "body", "error")

    def __init__(self, status: int | None = None, body: str = "", error: str = ""):
        self.status = status
        self.body = body
        self.error = error


def classify(res: HttpResult) -> str:
    """ok | auth | unavailable | missing | invalid (unexpected 3xx/4xx)."""
    if res.status is None:
        return "unavailable"  # timeout / transport
    if res.error:
        return "invalid"
    if res.status == 200:
        return "ok"
    if res.status in (401, 403):
        return "auth"
    if res.status == 404:
        return "missing"
    if res.status >= 500:
        return "unavailable"
    return "invalid"


class _NoRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, newurl):  # type: ignore[override]
        return None  # never follow redirects; opener raises HTTPError(3xx)


class Http:
    """HTTPS GET. Preemptive Basic auth goes only to the fixed cache origin."""

    def __init__(self, cache_origin: str, auth_header: str | None, opener: Any | None = None):
        parts = urllib.parse.urlsplit(cache_origin)
        self.cache_origin = (parts.scheme, parts.hostname, parts.port or 443)
        self.auth_header = auth_header
        self.opener = opener or urllib.request.build_opener(_NoRedirect())

    def get(self, url: str, timeout: float, *, accept: str | None = None) -> HttpResult:
        parts = urllib.parse.urlsplit(url)
        if parts.scheme != "https" or not parts.hostname:
            return HttpResult(error=f"refused non-https url")
        req = urllib.request.Request(url, method="GET")
        if accept is not None:
            req.add_header("Accept", accept)
        if self.auth_header and (parts.scheme, parts.hostname, parts.port or 443) == self.cache_origin:
            req.add_header("Authorization", self.auth_header)
        try:
            with self.opener.open(req, timeout=timeout) as resp:
                raw = resp.read(MAX_BODY + 1)
                if len(raw) > MAX_BODY:
                    return HttpResult(
                        status=resp.status, error="response exceeds size limit"
                    )
                return HttpResult(
                    status=resp.status, body=raw.decode("utf-8", "replace")
                )
        except urllib.error.HTTPError as exc:
            try:
                body = exc.read(MAX_BODY).decode("utf-8", "replace")
            except Exception:
                body = ""
            return HttpResult(status=exc.code, body=body)
        except urllib.error.URLError as exc:
            reason = getattr(exc, "reason", exc)
            if isinstance(reason, TimeoutError):
                return HttpResult(error="timeout")
            return HttpResult(error=f"transport: {reason}")
        except TimeoutError:
            return HttpResult(error="timeout")


def load_basic_auth(netrc_path: str, cache_host: str | None) -> str | None:
    """Preemptive 'Basic <b64>' header value from the netrc, or None."""
    if not netrc_path or not cache_host or not os.path.isfile(netrc_path):
        return None
    try:
        entry = netrc.netrc(netrc_path).authenticators(cache_host)
    except (OSError, ValueError, netrc.NetrcParseError):
        return None
    if not entry:
        return None
    login, _account, password = entry
    if not login or password is None:
        return None
    raw = f"{login}:{password}".encode("utf-8")
    return "Basic " + base64.b64encode(raw).decode("ascii")


# -------------------------------------------------------------- state/metrics


def default_state() -> dict[str, Any]:
    return {
        "cache_error": None,
        "probe": None,  # HEALTH_PATH or a store path; never creds or URLs
        "last_success": 0.0,
    }


def load_state(path: Path) -> dict[str, Any]:
    state = default_state()
    try:
        data = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError):
        return state
    if not isinstance(data, dict):
        return state
    if data.get("cache_error") in ("auth", "unavailable"):
        state["cache_error"] = data["cache_error"]
    probe = data.get("probe")
    if probe == HEALTH_PATH or (isinstance(probe, str) and STORE_RE.fullmatch(probe)):
        state["probe"] = probe
    if isinstance(data.get("last_success"), (int, float)):
        state["last_success"] = float(data["last_success"])
    return state


def atomic_write(path: Path, body: str) -> None:
    tmp = path.with_name(path.name + ".tmp")
    tmp.write_text(body, encoding="utf-8")
    tmp.replace(path)


def finish(state: dict[str, Any], state_dir: Path, fresh: bool, code: int) -> int:
    """Persist one state shape + textfile metrics; return the exit code.

    last_success is 'last successful gate timer run' — it advances on clean
    waits too; it is not an approval timestamp.
    """
    if fresh:
        state["last_success"] = time.time()
    atomic_write(state_dir / STATE_FILE, json.dumps(state, separators=(",", ":")) + "\n")
    err = state["cache_error"]
    atomic_write(
        state_dir / METRIC_FILE,
        "# HELP comin_nixci_cache_error NixCI cache probe error by reason (1=error)\n"
        "# TYPE comin_nixci_cache_error gauge\n"
        f'comin_nixci_cache_error{{reason="auth"}} {1 if err == "auth" else 0}\n'
        f'comin_nixci_cache_error{{reason="unavailable"}} {1 if err == "unavailable" else 0}\n'
        "# HELP comin_nixci_gate_last_success_timestamp_seconds"
        " Unix time of the last successful gate timer run (waits included)\n"
        "# TYPE comin_nixci_gate_last_success_timestamp_seconds gauge\n"
        f"comin_nixci_gate_last_success_timestamp_seconds {state['last_success']:.0f}\n",
    )
    return code


# ---------------------------------------------------------------------- main


def main(env: dict[str, str] | None = None, *, deps: dict[str, Any] | None = None) -> int:
    env = os.environ if env is None else env
    deps = deps or {}
    runner = deps.get("runner") or subprocess.run
    state_dir = Path(env.get("STATE_DIR", "/var/lib/comin-gate/textfile"))
    nixci_base = env.get("NIXCI_URL_BASE", "https://nix-ci.com/cb:ananjiani:infra").rstrip("/")
    cache_url = env.get("CACHE_URL", "https://cache.nix-ci.com").rstrip("/")
    hostname = env.get("GATE_HOSTNAME", "")
    check_attr = env.get("CHECK_ATTR") or (
        f"checks.x86_64-linux.nixos-{hostname}" if hostname else ""
    )
    cfg = {
        "grpcurl": env.get("GRPCURL", "grpcurl"),
        "proto": env.get("COMIN_PROTO", ""),
        "proto_import": env.get("COMIN_PROTO_IMPORT", ""),
        "sock": env.get("COMIN_GRPC_SOCK", "/var/lib/comin/grpc.sock"),
    }
    if not (cfg["proto"] and cfg["proto_import"] and check_attr):
        log("missing COMIN_PROTO/COMIN_PROTO_IMPORT/CHECK_ATTR configuration")
        return 1
    cache_parts = urllib.parse.urlsplit(cache_url)
    if cache_parts.scheme != "https" or not cache_parts.hostname:
        log("CACHE_URL must be an https origin")
        return 1
    auth = deps["auth"] if "auth" in deps else load_basic_auth(
        env.get("NETRC", ""), cache_parts.hostname
    )
    http = deps.get("http") or Http(cache_url, auth)

    st = load_state(state_dir / STATE_FILE)
    comin = comin_get_state(cfg, runner)
    if comin is None:
        return finish(st, state_dir, fresh=False, code=1)

    suspended = suspension(comin)
    if suspended is None:
        log("isSuspended is not an explicit bool; wait")
        return finish(st, state_dir, fresh=True, code=0)
    if suspended:
        log("comin is suspended; wait")
        return finish(st, state_dir, fresh=True, code=0)

    def approve() -> int:
        # Confirm only after a second GetState: same UUID, explicit not-suspended.
        second = comin_get_state(cfg, runner)
        if second is None:
            return finish(st, state_dir, fresh=False, code=1)
        if suspension(second) is not False:
            log("suspension unclear before confirm; wait")
            return finish(st, state_dir, fresh=True, code=0)
        uuid2, _gen = pending_build(second)
        if uuid2 != uuid:
            log("pending UUID changed before confirm; wait")
            return finish(st, state_dir, fresh=True, code=0)
        if not confirm_build(cfg, runner, uuid):
            return finish(st, state_dir, fresh=False, code=1)
        log(f"confirmed build for {uuid}")
        return finish(st, state_dir, fresh=True, code=0)

    uuid, gen = pending_build(comin)
    if not uuid:
        return no_pending(st, state_dir, http, cache_url)

    commit = ref = out_path = ""
    if gen is not None:
        source = gen.get("source")
        git = source.get("git") if isinstance(source, dict) else None
        if isinstance(git, dict):
            commit = git.get("selectedCommitId") or ""
            ref = git.get("selectedBranchName") or ""
        out_path = gen.get("outPath") or ""
    if not COMMIT_RE.fullmatch(commit) or not ref or not STORE_RE.fullmatch(out_path):
        log("pending generation lacks commit/ref/outPath; wait")
        return finish(st, state_dir, fresh=True, code=0)

    ci_url = f"{nixci_base}/{urllib.parse.quote(ref, safe='')}/{commit}"
    ci_res = http.get(ci_url, CI_TIMEOUT, accept="application/json")
    ci_payload = None
    if ci_res.status == 200:
        try:
            ci_payload = json.loads(ci_res.body)
        except json.JSONDecodeError:
            log("NixCI returned invalid JSON; wait")
    reason = (
        f"NixCI HTTP {ci_res.status}" if ci_res.status != 200 else check_ci(ci_payload, commit, ref, check_attr)
    )
    if reason:
        log(f"CI not green: {reason}; wait")
        return finish(st, state_dir, fresh=True, code=0)

    if auth is None:
        log("netrc missing or has no cache entry; fallback approve (auth)")
        st["cache_error"] = "auth"
        st["probe"] = HEALTH_PATH
        return approve()

    # Outage check before the root narinfo fetch: never probe a sick cache.
    health = http.get(f"{cache_url}/{HEALTH_PATH}", HTTP_TIMEOUT)
    kind = classify(health)
    if kind == "ok" and not parse_cache_info(health.body):
        kind = "invalid"
    if kind in ("auth", "unavailable"):
        log(f"cache health {kind}; fallback approve")
        st["cache_error"] = kind
        st["probe"] = HEALTH_PATH
        return approve()
    if kind != "ok":
        log(f"cache health unexpected HTTP {health.status}; wait")
        return finish(st, state_dir, fresh=True, code=0)

    url = narinfo_url(cache_url, out_path)
    res = http.get(url, HTTP_TIMEOUT) if url else HttpResult(error="bad store path")
    kind = classify(res)
    if kind in ("auth", "unavailable"):
        log(f"cache {kind} on root narinfo; fallback approve")
        st["cache_error"] = kind
        st["probe"] = out_path
        return approve()
    if kind != "ok" or parse_narinfo(res.body, out_path) is None:
        reason = (
            (res.error or f"narinfo HTTP {res.status}")
            if kind != "ok"
            else "invalid narinfo"
        )
        log(f"root narinfo not ready ({reason}); wait")
        return finish(st, state_dir, fresh=True, code=0)
    log("CI green and root narinfo present; approve")
    st["cache_error"] = None
    st["probe"] = None
    return approve()


def no_pending(st: dict[str, Any], state_dir: Path, http: Any, cache_url: str) -> int:
    """Nothing pending: probe a persisted cache error.

    The probe re-hits the recorded failing path (health endpoint or root
    narinfo store path). A plain healthy nix-cache-info never clears an
    outage that was recorded on a narinfo path.
    """
    if not st["cache_error"]:
        st["probe"] = None
        return finish(st, state_dir, fresh=True, code=0)
    if st["probe"] and st["probe"] != HEALTH_PATH:
        url = narinfo_url(cache_url, st["probe"]) or f"{cache_url}/{HEALTH_PATH}"
        is_narinfo = url.endswith(".narinfo")
    else:
        url = f"{cache_url}/{HEALTH_PATH}"
        is_narinfo = False
    res = http.get(url, HTTP_TIMEOUT)
    kind = classify(res)
    valid = parse_narinfo(res.body, None) is not None if is_narinfo else parse_cache_info(res.body)
    if (kind == "ok" and valid) or kind == "missing":
        log("cache recovered; clear error")
        st["cache_error"] = None
        st["probe"] = None
    elif kind in ("auth", "unavailable"):
        log(f"cache still {kind}")
        st["cache_error"] = kind
    else:
        log(f"cache probe inconclusive (HTTP {res.status}); keep error")
    return finish(st, state_dir, fresh=True, code=0)


if __name__ == "__main__":
    sys.exit(main())
