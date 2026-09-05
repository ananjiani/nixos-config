#!/usr/bin/env python3
"""Unit tests for the Comin NixCI cache gate. No network, no secrets.

Mocks replace only transport (subprocess runner, HTTP). All parsing,
classification, decisions, state, and metrics run for real.
"""

from __future__ import annotations

import base64
import importlib.util
import json
import tempfile
import threading
import unittest
import urllib.error
from pathlib import Path
from types import SimpleNamespace

HELPER = Path(__file__).resolve().parents[1] / "comin-ci-gate.py"
SPEC = importlib.util.spec_from_file_location("comin_ci_gate", HELPER)
gate = importlib.util.module_from_spec(SPEC)
assert SPEC.loader is not None
SPEC.loader.exec_module(gate)

NIX32 = gate.NIX32


def h32(n: int) -> str:
    """Distinct valid nix-base32 hashes (n in base 32, zero padded)."""
    digits = ""
    for _ in range(32):
        digits = NIX32[n % 32] + digits
        n //= 32
    return digits


def h52(n: int) -> str:
    digits = ""
    for _ in range(52):
        digits = NIX32[n % 32] + digits
        n //= 32
    return digits


def sp(n: int, name: str = "pkg") -> str:
    return f"/nix/store/{h32(n)}-{name}"


SHA = "d79cff448a5e45d51bc0c204b303be4d38dced7a"
UUID = "11111111-2222-3333-4444-555555555555"
UUID2 = "99999999-2222-3333-4444-555555555555"
HOST = "boromir"
ATTR = f"checks.x86_64-linux.nixos-{HOST}"
OUT, DEP, DEP2 = sp(0, "nixos-system"), sp(1, "hello"), sp(2, "glibc")
CACHE = "https://cache.nix-ci.com"
NIXCI = "https://nix-ci.com/cb:ananjiani:infra"
CI_URL = f"{NIXCI}/main/{SHA}"
HEALTH_URL = f"{CACHE}/nix-cache-info"
BASIC = "Basic " + base64.b64encode(b"ci:pw").decode()


def narinfo_url(n: int) -> str:
    return f"{CACHE}/{h32(n)}.narinfo"


def narinfo(path: str, refs: list[str] | None = None) -> str:
    """Real narinfo shape (cache.nixos.org style); refs None omits References."""
    digest = path.split("/nix/store/")[1][:32]
    lines = [
        f"StorePath: {path}",
        f"URL: nar/{digest}",
        "Compression: xz",
        f"FileHash: sha256:{h52(7)}",
        "FileSize: 40728",
        f"NarHash: sha256:{h52(3)}",
        "NarSize: 202320",
    ]
    if refs is not None:
        names = [r.rsplit("/", 1)[-1] for r in refs]
        lines.append("References: " + " ".join(names))
    lines += [f"Deriver: {digest}-pkg.drv", f"Sig: cache.nix-ci.com-1:aaaa"]
    return "\n".join(lines) + "\n"


CACHE_INFO = "StoreDir: /nix/store\nWantMassQuery: 1\nPriority: 41\n"


def ci_payload(
    *,
    commit: str = SHA,
    ref: str = "main",
    status: str = "success",
    runs: list | None = None,
) -> dict:
    if runs is None:
        runs = [
            {"type": "config", "status": "success"},
            {"type": "show", "status": "success"},
            {"type": "build", "attribute": ATTR, "status": "success"},
        ]
    return {"commit": commit, "ref": ref, "status": status, "runs": runs}


def comin_state(
    *,
    submitted: str | None = UUID,
    confirmed: str = "",
    suspended: object = False,
    uuid: str = UUID,
    gen: dict | None = None,
    with_generation: bool = True,
) -> dict:
    """Actual grpcurl -emit-defaults shape: camelCase, plain bool wrapper."""
    return {
        "isSuspended": suspended,
        "buildConfirmer": {
            "mode": 2,
            "submitted": submitted or "",
            "confirmed": confirmed,
        },
        "store": {
            "generations": []
            if not with_generation
            else [
                gen
                or {
                    "uuid": uuid,
                    "outPath": OUT,
                    "source": {
                        "git": {
                            "selectedCommitId": SHA,
                            "selectedBranchName": "main",
                            "selectedBranchIsTesting": False,
                        }
                    },
                }
            ]
        },
    }


class FakeHttp:
    """Transport mock: url -> HttpResult. Records every request."""

    def __init__(self, mapping: dict):
        self.mapping = mapping
        self.urls: list[str] = []
        self.accepts: list[str | None] = []
        self._lock = threading.Lock()

    def get(self, url: str, timeout: float, *, accept: str | None = None) -> gate.HttpResult:
        with self._lock:
            self.urls.append(url)
            self.accepts.append(accept)
        res = self.mapping.get(url)
        if res is None:
            res = gate.HttpResult(status=599, error=f"unexpected url {url}")
        return res

    def count(self, url: str) -> int:
        return self.urls.count(url)


class Runner:
    """Transport mock for grpcurl: queued GetState states, records Confirm."""

    def __init__(self, states: list, confirm_code: int = 0):
        self.states = list(states)
        self.confirm_code = confirm_code
        self.calls: list[list[str]] = []
        self.confirmed: list[dict] = []

    def __call__(self, argv, check=False, capture_output=True, text=True, timeout=None):
        self.calls.append(list(argv))
        method = argv[-1]
        proc = SimpleNamespace(returncode=1, stdout="", stderr=f"unknown {method}")
        if method == "protobuf.Comin/GetState":
            if self.states:
                proc = SimpleNamespace(
                    returncode=0, stdout=json.dumps(self.states.pop(0)), stderr=""
                )
        elif method == "protobuf.Comin/Confirm":
            self.confirmed.append(json.loads(argv[argv.index("-d") + 1]))
            proc = SimpleNamespace(
                returncode=self.confirm_code,
                stdout="{}",
                stderr="" if self.confirm_code == 0 else "confirm failed",
            )
        return proc


def make_env(tmp: str) -> dict:
    return {
        "STATE_DIR": tmp,
        "GRPCURL": "grpcurl",
        "COMIN_PROTO": "/etc/comin/services.proto",
        "COMIN_PROTO_IMPORT": "/etc/comin",
        "COMIN_GRPC_SOCK": "/var/lib/comin/grpc.sock",
        "NIXCI_URL_BASE": NIXCI,
        "CACHE_URL": CACHE,
        "NETRC": "/nonexistent-netrc",
        "GATE_HOSTNAME": HOST,
        "CHECK_ATTR": ATTR,
    }


def run_main(tmp: str, runner: Runner, http: FakeHttp, auth: str | None = BASIC) -> int:
    return gate.main(make_env(tmp), deps={"runner": runner, "http": http, "auth": auth})


def ok_http(extra: dict | None = None, host_refs: list[str] | None = None) -> FakeHttp:
    mapping = {
        CI_URL: gate.HttpResult(status=200, body=json.dumps(ci_payload())),
        HEALTH_URL: gate.HttpResult(status=200, body=CACHE_INFO),
        narinfo_url(0): gate.HttpResult(status=200, body=narinfo(OUT, host_refs or [])),
    }
    mapping.update(extra or {})
    return FakeHttp(mapping)


def read_state(tmp: str) -> dict:
    return json.loads(Path(tmp, "state.json").read_text())


def read_metrics(tmp: str) -> str:
    return Path(tmp, "comin-ci-gate.prom").read_text()


class NarinfoTests(unittest.TestCase):
    def test_real_shape_omitted_references_means_empty(self):
        refs = gate.parse_narinfo(narinfo(OUT, None), OUT)
        self.assertEqual(refs, [])

    def test_real_shape_with_references(self):
        refs = gate.parse_narinfo(narinfo(OUT, [DEP, DEP2]), OUT)
        self.assertEqual(refs, [DEP, DEP2])

    def test_fake_two_field_narinfo_rejected(self):
        fake = f"StorePath: {OUT}\nReferences: {DEP.rsplit('/', 1)[-1]}\n"
        self.assertIsNone(gate.parse_narinfo(fake, OUT))

    def test_mandatory_field_table(self):
        cases = {
            "store path mismatch": narinfo(DEP, []),
            "missing URL": narinfo(OUT, []).replace("URL: nar/" + h32(0) + "\n", ""),
            "bad narhash": narinfo(OUT, []).replace("sha256:" + h52(3), "sha256:short"),
            "narhash wrong algo": narinfo(OUT, []).replace("sha256:", "md5:"),
            "missing narsize": narinfo(OUT, []).replace("NarSize: 202320\n", ""),
            "negative narsize": narinfo(OUT, []).replace("NarSize: 202320", "NarSize: -1"),
            "nonint narsize": narinfo(OUT, []).replace("NarSize: 202320", "NarSize: big"),
        }
        for name, body in cases.items():
            with self.subTest(name):
                self.assertIsNone(gate.parse_narinfo(body, OUT))

    def test_reference_parsing_strict(self):
        body = narinfo(OUT, None).replace(
            "NarSize: 202320", "NarSize: 202320\nReferences: "
            + h32(5)
            + "-name-with+weird?=.chars"
        )
        self.assertEqual(gate.parse_narinfo(body, OUT), [sp(5, "name-with+weird?=.chars")])
        for bad in ("../../etc/passwd", "https://evil.example/x", h32(6) + "-x/../../y"):
            with self.subTest(bad):
                body = narinfo(OUT, None).replace(
                    "NarSize: 202320", f"NarSize: 202320\nReferences: {bad}"
                )
                self.assertIsNone(gate.parse_narinfo(body, OUT))

    def test_full_store_path_reference(self):
        body = narinfo(OUT, None).replace(
            "NarSize: 202320", f"NarSize: 202320\nReferences: {DEP}"
        )
        self.assertEqual(gate.parse_narinfo(body, OUT), [DEP])

    def test_hash_lengths(self):
        self.assertTrue(gate.STORE_RE.fullmatch(sp(9)))
        self.assertFalse(gate.STORE_RE.fullmatch(f"/nix/store/{h32(9)[:29]}-pkg"))
        self.assertFalse(gate.STORE_RE.fullmatch(f"/nix/store/{h32(9)}-"))
        self.assertEqual(gate.narinfo_url(CACHE, OUT), narinfo_url(0))

    def test_cache_info(self):
        self.assertTrue(gate.parse_cache_info(CACHE_INFO))
        self.assertFalse(gate.parse_cache_info("StoreDir: /nope\n"))
        self.assertFalse(gate.parse_cache_info("garbage"))


class CiTests(unittest.TestCase):
    def test_decision_table(self):
        ok = [
            ("green", ci_payload()),
            ("host cached", ci_payload(runs=[
                {"type": "config", "status": "success"},
                {"type": "show", "status": "cached"},
                {"type": "build", "attribute": ATTR, "status": "cached"},
            ])),
        ]
        blocked = [
            ("suite failure", ci_payload(status="failure"), "failure"),
            ("suite pending", ci_payload(status="pending"), "pending"),
            ("status missing", {k: v for k, v in ci_payload().items() if k != "status"}, "suite"),
            ("empty runs", ci_payload(runs=[]), "empty"),
            ("config failed", ci_payload(runs=[
                {"type": "config", "status": "failure"},
                {"type": "show", "status": "success"},
            ]), "config"),
            ("show failed", ci_payload(runs=[
                {"type": "config", "status": "success"},
                {"type": "show", "status": "failure"},
            ]), "show"),
            ("host build failed", ci_payload(runs=[
                {"type": "config", "status": "success"},
                {"type": "show", "status": "success"},
                {"type": "build", "attribute": ATTR, "status": "failure"},
            ]), ATTR),
            ("host build missing", ci_payload(runs=[
                {"type": "config", "status": "success"},
                {"type": "show", "status": "success"},
                {"type": "build", "attribute": "other.attr", "status": "success"},
            ]), "missing"),
            ("commit mismatch", ci_payload(commit="f" * 40), "commit"),
            ("ref mismatch", ci_payload(ref="feat/x"), "ref"),
            ("malformed", None, "malformed"),
        ]
        for name, payload in ok:
            with self.subTest(name):
                self.assertEqual(gate.check_ci(payload, SHA, "main", ATTR), "")
        for name, payload, needle in blocked:
            with self.subTest(name):
                reason = gate.check_ci(payload, SHA, "main", ATTR)
                self.assertTrue(reason, name)
                self.assertIn(needle, reason.lower())

    def test_no_alias_type_names(self):
        runs = [
            {"type": "configure", "status": "success"},
            {"type": "eval", "status": "success"},
            {"type": "build", "attribute": ATTR, "status": "success"},
        ]
        self.assertIn("missing", gate.check_ci(ci_payload(runs=runs), SHA, "main", ATTR))


class CominStateTests(unittest.TestCase):
    def test_is_suspended_explicit_bool_only(self):
        self.assertIs(gate.suspension({"isSuspended": False}), False)
        self.assertIs(gate.suspension({"isSuspended": True}), True)
        for bad in (None, "false", 0, {"value": False}, {}, "true"):
            with self.subTest(repr(bad)):
                self.assertIsNone(gate.suspension({"isSuspended": bad}))

    def test_pending_identity_is_submitted_only(self):
        # Stale Confirm can leave confirmed=oldUUID while submitted=newUUID.
        # The gate must process the new submission, not stall on confirmed.
        state = comin_state(submitted=UUID2, confirmed=UUID, uuid=UUID2)
        uuid, gen = gate.pending_build(state)
        self.assertEqual(uuid, UUID2)
        self.assertEqual(gen["uuid"], UUID2)

    def test_pending_missing(self):
        self.assertEqual(gate.pending_build({"buildConfirmer": {"submitted": ""}}), ("", None))
        uuid, gen = gate.pending_build(comin_state(with_generation=False))
        self.assertEqual((uuid, gen), (UUID, None))
        uuid, gen = gate.pending_build(comin_state(submitted=None))
        self.assertEqual((uuid, gen), ("", None))

    def test_grpcurl_command_shape(self):
        rec = Runner([comin_state()])
        gate.comin_get_state(
            {
                "grpcurl": "grpcurl",
                "proto": "/pin/pkg/protobuf/services.proto",
                "proto_import": "/pin/pkg/protobuf",
                "sock": "/var/lib/comin/grpc.sock",
            },
            rec,
        )
        cmd = rec.calls[0]
        self.assertIn("-plaintext", cmd)
        self.assertIn("-emit-defaults", cmd)
        self.assertIn("-import-path", cmd)
        self.assertIn("/pin/pkg/protobuf", cmd)
        self.assertEqual(cmd[cmd.index("-proto") + 1], "services.proto")
        self.assertIn("unix:///var/lib/comin/grpc.sock", cmd)
        self.assertEqual(cmd[-1], "protobuf.Comin/GetState")
        rec2 = Runner([])
        rec2.states = [comin_state(), comin_state()]
        code, _payload = rec2.__call__(cmd + ["protobuf.Comin/GetState"]), 0
        # Confirm payload exactness is covered in MainTests via runner.confirmed.


class HttpAuthTests(unittest.TestCase):
    class FakeResponse:
        def __init__(self, res):
            self.status = res.status
            self._body = res.body.encode()

        def read(self, n=-1):
            if n is None or n < 0:
                data, self._body = self._body, b""
                return data
            data, self._body = self._body[:n], self._body[n:]
            return data

        def __enter__(self):
            return self

        def __exit__(self, *args):
            return False

    class FakeOpener:
        def __init__(self, mapping):
            self.mapping = mapping
            self.requests: list[urllib.request.Request] = []

        def open(self, req, timeout=None):
            self.requests.append(req)
            hit = self.mapping[req.full_url]
            if isinstance(hit, Exception):
                raise hit
            return HttpAuthTests.FakeResponse(hit)

    def http(self, urls, auth=BASIC):
        opener = self.FakeOpener(urls)
        return gate.Http(CACHE, auth, opener=opener), opener

    def test_preemptive_basic_before_challenge_cache_origin_only(self):
        urls = {u: gate.HttpResult(status=200) for u in (
            f"{CACHE}/x", f"{NIXCI}/main/x", "https://evil.example/cache/x")}
        http, opener = self.http(urls)
        self.assertIsNone(http.get(f"{CACHE}/x", 1).error or None)
        self.assertEqual(opener.requests[0].get_header("Authorization"), BASIC)
        self.assertIsNone(http.get(f"{NIXCI}/main/x", 1).error or None)
        self.assertIsNone(opener.requests[1].get_header("Authorization"))
        self.assertIsNone(http.get("https://evil.example/cache/x", 1).error or None)
        self.assertIsNone(opener.requests[2].get_header("Authorization"))

    def test_accept_json_header_explicit_auth_still_cache_only(self):
        urls = {
            f"{NIXCI}/main/x": gate.HttpResult(status=200, body="{}"),
            f"{CACHE}/x": gate.HttpResult(status=200, body="ok"),
        }
        http, opener = self.http(urls)
        http.get(f"{NIXCI}/main/x", 1, accept="application/json")
        self.assertEqual(opener.requests[0].get_header("Accept"), "application/json")
        self.assertIsNone(opener.requests[0].get_header("Authorization"))
        http.get(f"{CACHE}/x", 1)
        self.assertIsNone(opener.requests[1].get_header("Accept"))
        self.assertEqual(opener.requests[1].get_header("Authorization"), BASIC)

    def test_same_host_different_port_no_authorization(self):
        url = "https://cache.nix-ci.com:8443/x"
        http, opener = self.http({url: gate.HttpResult(status=200)})
        http.get(url, 1)
        self.assertIsNone(opener.requests[0].get_header("Authorization"))

    def test_no_auth_header_without_credentials(self):
        http, opener = self.http({f"{CACHE}/x": gate.HttpResult(status=200)}, auth=None)
        http.get(f"{CACHE}/x", 1)
        self.assertIsNone(opener.requests[0].get_header("Authorization"))

    def test_302_not_followed_reported_as_status(self):
        err = urllib.error.HTTPError(f"{CACHE}/x", 302, "Found", {}, None)
        http, _ = self.http({f"{CACHE}/x": err})
        res = http.get(f"{CACHE}/x", 1)
        self.assertEqual(res.status, 302)
        self.assertEqual(gate.classify(res), "invalid")

    def test_default_opener_never_follows_redirects(self):
        http = gate.Http(CACHE, BASIC)
        for handler in http.opener.handlers:
            if isinstance(handler, urllib.request.HTTPRedirectHandler):
                self.assertIsInstance(handler, gate._NoRedirect)

    def test_non_https_refused(self):
        http, opener = self.http({})
        self.assertNotEqual(http.get("http://cache.nix-ci.com/x", 1).error, "")
        self.assertEqual(opener.requests, [])

    def test_load_basic_auth_from_netrc(self):
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp, "netrc")
            path.write_text("machine cache.nix-ci.com login ci password pw\n")
            self.assertEqual(
                gate.load_basic_auth(str(path), "cache.nix-ci.com"), BASIC
            )
            self.assertIsNone(gate.load_basic_auth(str(path), "other.host"))
            path.write_text("garbage {{{\n")
            self.assertIsNone(gate.load_basic_auth(str(path), "cache.nix-ci.com"))
        self.assertIsNone(gate.load_basic_auth("/nonexistent", "cache.nix-ci.com"))

    def test_status_classification(self):
        table = [
            (200, None, "ok"),
            (401, None, "auth"),
            (403, None, "auth"),
            (404, None, "missing"),
            (500, None, "unavailable"),
            (503, None, "unavailable"),
            (302, None, "invalid"),
            (400, None, "invalid"),
            (418, None, "invalid"),
            (None, "timeout", "unavailable"),
            (None, "transport: reset", "unavailable"),
            (200, "response exceeds size limit", "invalid"),
        ]
        for status, error, want in table:
            with self.subTest((status, error)):
                self.assertEqual(gate.classify(gate.HttpResult(status, "", error or "")), want)

    def _padded_narinfo(self, path, refs=None, total=None, over_by=None):
        """Valid narinfo; pad so total size is exact or References sit past MAX_BODY."""
        base = narinfo(path, None)
        ref_line = ""
        if refs is not None:
            names = " ".join(r.rsplit("/", 1)[-1] for r in refs)
            ref_line = f"References: {names}\n"
        prefix = f"{base}Padding: "
        if total is not None:
            suffix = "\n"
            pad = total - len(prefix) - len(suffix)
            self.assertGreaterEqual(pad, 0)
            body = prefix + ("x" * pad) + suffix
            self.assertEqual(len(body), total)
            return body
        # prefix+pad reaches MAX_BODY+(over_by-1); References sits past the limit.
        over_by = 1 if over_by is None else over_by
        pad = gate.MAX_BODY - len(prefix) + over_by - 1
        body = prefix + ("x" * pad) + "\n" + ref_line
        self.assertGreater(len(body), gate.MAX_BODY)
        self.assertNotIn("References:", body[: gate.MAX_BODY])
        return body

    def test_oversized_body_rejected_not_truncated(self):
        body = self._padded_narinfo(OUT, refs=[DEP], over_by=1)
        # Truncation would drop References and falsely parse as a leaf.
        self.assertEqual(gate.parse_narinfo(body[: gate.MAX_BODY], OUT), [])
        http, _ = self.http({f"{CACHE}/x": gate.HttpResult(status=200, body=body)})
        res = http.get(f"{CACHE}/x", 1)
        self.assertEqual(res.error, "response exceeds size limit")
        self.assertEqual(res.body, "")
        self.assertEqual(gate.classify(res), "invalid")
        self.assertIsNone(gate.parse_narinfo(res.body, OUT))

    def test_exact_max_body_accepted(self):
        body = self._padded_narinfo(OUT, refs=None, total=gate.MAX_BODY)
        http, _ = self.http({f"{CACHE}/x": gate.HttpResult(status=200, body=body)})
        res = http.get(f"{CACHE}/x", 1)
        self.assertEqual(res.error, "")
        self.assertEqual(gate.classify(res), "ok")
        self.assertEqual(res.body, body)
        self.assertEqual(gate.parse_narinfo(res.body, OUT), [])


class MainTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.dir = self.tmp.name

    def tearDown(self):
        self.tmp.cleanup()

    def test_approve_confirms_exact_build_only(self):
        runner = Runner([comin_state(), comin_state()])
        http = ok_http()
        self.assertEqual(run_main(self.dir, runner, http), 0)
        self.assertEqual(len(runner.confirmed), 1)
        self.assertEqual(runner.confirmed[0], {"generationUuid": UUID, "for": "build"})
        self.assertIn('reason="auth"} 0', read_metrics(self.dir))

    def test_ci_requests_json_cache_does_not(self):
        runner = Runner([comin_state(), comin_state()])
        http = ok_http()
        self.assertEqual(run_main(self.dir, runner, http), 0)
        by_url = dict(zip(http.urls, http.accepts))
        self.assertEqual(by_url[CI_URL], "application/json")
        self.assertIsNone(by_url[HEALTH_URL])
        self.assertIsNone(by_url[narinfo_url(0)])

    def test_root_ready_approves_without_walking_references(self):
        # Root narinfo is valid and names DEP; DEP would 404 if queried.
        # Policy: Confirm the root only. Never fetch dependency narinfos.
        runner = Runner([comin_state(), comin_state()])
        http = ok_http(
            extra={narinfo_url(1): gate.HttpResult(status=404)},
            host_refs=[DEP],
        )
        self.assertEqual(run_main(self.dir, runner, http), 0)
        self.assertEqual(runner.confirmed, [{"generationUuid": UUID, "for": "build"}])
        self.assertNotIn(narinfo_url(1), http.urls)

    def test_stale_uuid_or_suspension_before_confirm_aborts(self):
        for second in (comin_state(submitted=UUID2, uuid=UUID2), comin_state(suspended=True)):
            with self.subTest(second["isSuspended"]):
                runner = Runner([comin_state(), second])
                self.assertEqual(run_main(self.dir, runner, ok_http()), 0)
                self.assertEqual(runner.confirmed, [])

    def test_unclear_is_suspended_waits_without_any_fetch(self):
        for bad in (None, "false", {"value": False}):
            with tempfile.TemporaryDirectory() as t, self.subTest(repr(bad)):
                runner = Runner([comin_state(suspended=bad)])
                self.assertEqual(run_main(t, runner, FakeHttp({})), 0)
                self.assertEqual(runner.confirmed, [])
                metrics = read_metrics(t)
                self.assertIn('reason="auth"} 0', metrics)
                self.assertIn('reason="unavailable"} 0', metrics)

    def test_stale_confirmed_field_does_not_block_new_pending(self):
        # Race: Confirm(oldUUID) landed late; confirmed stays old while a new
        # generation is submitted. The gate must confirm the new UUID.
        runner = Runner([
            comin_state(submitted=UUID2, confirmed=UUID, uuid=UUID2),
            comin_state(submitted=UUID2, confirmed=UUID, uuid=UUID2),
        ])
        http = ok_http()
        self.assertEqual(run_main(self.dir, runner, http), 0)
        self.assertEqual(runner.confirmed, [{"generationUuid": UUID2, "for": "build"}])

    def test_ci_errors_wait_and_keep_prior_cache_error(self):
        for res in (gate.HttpResult(status=500), gate.HttpResult(error="timeout")):
            with tempfile.TemporaryDirectory() as t, self.subTest(res.error or res.status):
                Path(t, "state.json").write_text(
                    json.dumps({"cache_error": "unavailable", "last_success": 1})
                )
                runner = Runner([comin_state()])
                http = FakeHttp({CI_URL: res})
                self.assertEqual(run_main(t, runner, http), 0)
                self.assertEqual(runner.confirmed, [])
                self.assertEqual(http.urls, [CI_URL])  # cache untouched on CI error
                self.assertIn('reason="unavailable"} 1', read_metrics(t))

    def test_ci_not_green_never_falls_back(self):
        runner = Runner([comin_state()])
        http = FakeHttp({
            CI_URL: gate.HttpResult(status=200, body=json.dumps(ci_payload(status="failure")))
        })
        self.assertEqual(run_main(self.dir, runner, http), 0)
        self.assertEqual(runner.confirmed, [])
        self.assertEqual(http.urls, [CI_URL])
        self.assertIn('reason="auth"} 0', read_metrics(self.dir))

    def test_missing_netrc_fallback_auth_metric(self):
        runner = Runner([comin_state(), comin_state()])
        http = FakeHttp({CI_URL: gate.HttpResult(status=200, body=json.dumps(ci_payload()))})
        self.assertEqual(run_main(self.dir, runner, http, auth=None), 0)
        self.assertEqual(runner.confirmed, [{"generationUuid": UUID, "for": "build"}])
        self.assertEqual(http.urls, [CI_URL])
        self.assertIn('reason="auth"} 1', read_metrics(self.dir))

    def test_health_auth_or_outage_fallback(self):
        for res, reason in (
            (gate.HttpResult(status=401), "auth"),
            (gate.HttpResult(status=503), "unavailable"),
            (gate.HttpResult(error="timeout"), "unavailable"),
        ):
            with tempfile.TemporaryDirectory() as t, self.subTest(reason + str(res.status)):
                runner = Runner([comin_state(), comin_state()])
                http = ok_http({HEALTH_URL: res})
                self.assertEqual(run_main(t, runner, http), 0)
                self.assertEqual(len(runner.confirmed), 1)
                self.assertIn(f'reason="{reason}"}} 1', read_metrics(t))

    def test_health_404_waits_no_fallback_no_metric(self):
        runner = Runner([comin_state()])
        http = ok_http({HEALTH_URL: gate.HttpResult(status=404)})
        self.assertEqual(run_main(self.dir, runner, http), 0)
        self.assertEqual(runner.confirmed, [])
        self.assertIn('reason="unavailable"} 0', read_metrics(self.dir))
        self.assertNotIn(narinfo_url(0), http.urls)
        st = read_state(self.dir)
        self.assertNotIn("uuid", st)
        self.assertNotIn("pending_paths", st)

    def test_root_404_waits_two_ticks_then_approves(self):
        missing = ok_http({narinfo_url(0): gate.HttpResult(status=404)})
        for _ in (1, 2):
            runner = Runner([comin_state(), comin_state()])
            self.assertEqual(run_main(self.dir, runner, missing), 0)
            self.assertEqual(runner.confirmed, [])
            st = read_state(self.dir)
            self.assertIsNone(st["cache_error"])
            self.assertNotIn("pending_paths", st)
        self.assertEqual(missing.count(narinfo_url(0)), 2)
        runner3 = Runner([comin_state(), comin_state()])
        http3 = ok_http()
        self.assertEqual(run_main(self.dir, runner3, http3), 0)
        self.assertEqual(runner3.confirmed, [{"generationUuid": UUID, "for": "build"}])

    def test_root_auth_or_outage_fallback(self):
        for res, reason in (
            (gate.HttpResult(status=401), "auth"),
            (gate.HttpResult(status=503), "unavailable"),
            (gate.HttpResult(error="timeout"), "unavailable"),
        ):
            with tempfile.TemporaryDirectory() as t, self.subTest(reason + str(res.status)):
                runner = Runner([comin_state(), comin_state()])
                http = ok_http({narinfo_url(0): res})
                self.assertEqual(run_main(t, runner, http), 0)
                self.assertEqual(
                    runner.confirmed, [{"generationUuid": UUID, "for": "build"}]
                )
                self.assertIn(f'reason="{reason}"}} 1', read_metrics(t))
                self.assertEqual(read_state(t)["probe"], OUT)

    def test_root_invalid_or_unexpected_waits_across_ticks(self):
        bad_refs = narinfo(OUT, None).replace(
            "NarSize: 202320",
            "NarSize: 202320\nReferences: https://evil.example/x ../../p",
        )
        cases = {
            "malformed 200": gate.HttpResult(status=200, body="nope"),
            "400": gate.HttpResult(status=400),
            "418": gate.HttpResult(status=418),
            "302": gate.HttpResult(status=302),
            "oversized": gate.HttpResult(
                status=200, error="response exceeds size limit", body=""
            ),
            "bad refs": gate.HttpResult(status=200, body=bad_refs),
        }
        for name, root_res in cases.items():
            with self.subTest(name), tempfile.TemporaryDirectory() as tmp:
                http = ok_http({narinfo_url(0): root_res})
                for _ in (1, 2):
                    runner = Runner([comin_state(), comin_state()])
                    self.assertEqual(run_main(tmp, runner, http), 0)
                    self.assertEqual(runner.confirmed, [])
                    self.assertIsNone(read_state(tmp)["cache_error"])
                self.assertEqual(http.count(narinfo_url(0)), 2)
                self.assertNotIn(narinfo_url(1), http.urls)

    def test_stale_checkpoint_ignored_does_not_approve(self):
        Path(self.dir, "state.json").write_text(
            json.dumps(
                {
                    "uuid": UUID,
                    "pending_paths": [],
                    "done_paths": [OUT],
                    "cache_error": None,
                    "probe": None,
                    "last_success": 1.0,
                }
            )
        )
        runner = Runner([comin_state(), comin_state()])
        http = ok_http({narinfo_url(0): gate.HttpResult(status=404)})
        self.assertEqual(run_main(self.dir, runner, http), 0)
        self.assertEqual(runner.confirmed, [])
        self.assertIn(narinfo_url(0), http.urls)
        st = read_state(self.dir)
        self.assertNotIn("done_paths", st)
        self.assertNotIn("pending_paths", st)
        self.assertNotIn("uuid", st)

    def test_malformed_state_json_survives(self):
        Path(self.dir, "state.json").write_text("{broken")
        runner = Runner([comin_state()])
        self.assertEqual(run_main(self.dir, runner, ok_http()), 1)  # 1 state: waits approve
        self.assertEqual(runner.confirmed, [])  # ...but needs a second state to confirm

    def test_malformed_ci_json_waits(self):
        runner = Runner([comin_state()])
        http = FakeHttp({CI_URL: gate.HttpResult(status=200, body="{nope")})
        self.assertEqual(run_main(self.dir, runner, http), 0)
        self.assertEqual(runner.confirmed, [])

    def test_pending_context_missing_waits(self):
        for state in (
            comin_state(with_generation=False),
            comin_state(gen={"uuid": UUID, "outPath": "", "source": {"git": {
                "selectedCommitId": SHA, "selectedBranchName": "main"}}}),
        ):
            with tempfile.TemporaryDirectory() as t, self.subTest(state):
                runner = Runner([state])
                self.assertEqual(run_main(t, runner, FakeHttp({})), 0)
                self.assertEqual(runner.confirmed, [])

    def test_url_encodes_branch(self):
        runner = Runner([comin_state(gen={
            "uuid": UUID, "outPath": OUT, "source": {"git": {
                "selectedCommitId": SHA, "selectedBranchName": "feat/nix-ci"}}})])
        http = FakeHttp({})
        with tempfile.TemporaryDirectory() as t:
            run_main(t, runner, http)
        self.assertEqual(http.urls, [f"{NIXCI}/feat%2Fnix-ci/{SHA}"])

    def test_no_credentials_in_state_or_metrics(self):
        secret = base64.b64encode(b"ci:pw").decode()
        runner = Runner([comin_state(), comin_state()])
        self.assertEqual(run_main(self.dir, runner, ok_http()), 0)
        self.assertNotIn(secret, read_state(self.dir).__str__() + read_metrics(self.dir))
        self.assertNotIn("ci:pw", json.dumps(read_state(self.dir)))


class RecoveryTests(unittest.TestCase):
    """No-pending ticks probe the recorded failing path, not just health."""

    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.dir = self.tmp.name

    def tearDown(self):
        self.tmp.cleanup()

    def seed(self, probe: str | None) -> None:
        st = gate.default_state()
        st.update(cache_error="unavailable", probe=probe, last_success=1.0)
        Path(self.dir, "state.json").write_text(json.dumps(st))

    def run_nopending(self, http) -> int:
        return run_main(self.dir, Runner([comin_state(submitted="")]), http)

    def test_narinfo_500_persists_and_recovery_200_clears(self):
        self.seed(OUT)
        self.run_nopending(FakeHttp({narinfo_url(0): gate.HttpResult(status=500)}))
        self.assertEqual(read_state(self.dir)["cache_error"], "unavailable")
        self.run_nopending(FakeHttp({narinfo_url(0): gate.HttpResult(status=200, body=narinfo(OUT, None))}))
        self.assertIsNone(read_state(self.dir)["cache_error"])
        self.assertIn('reason="unavailable"} 0', read_metrics(self.dir))

    def test_healthy_cache_info_alone_does_not_clear_narinfo_outage(self):
        self.seed(OUT)
        http = FakeHttp({
            HEALTH_URL: gate.HttpResult(status=200, body=CACHE_INFO),
            narinfo_url(0): gate.HttpResult(status=500),
        })
        self.run_nopending(http)
        self.assertEqual(read_state(self.dir)["cache_error"], "unavailable")
        self.assertIn(narinfo_url(0), http.urls)  # probed the failing path itself

    def test_probe_404_clears_auth_and_keeps_other_errors(self):
        self.seed(OUT)
        self.run_nopending(FakeHttp({narinfo_url(0): gate.HttpResult(status=404)}))
        self.assertIsNone(read_state(self.dir)["cache_error"])

    def test_probe_auth_keeps_auth_error(self):
        self.seed(HEALTH_URL)
        self.run_nopending(FakeHttp({HEALTH_URL: gate.HttpResult(status=401)}))
        self.assertEqual(read_state(self.dir)["cache_error"], "auth")

    def test_no_error_no_probe(self):
        st = gate.default_state()
        Path(self.dir, "state.json").write_text(json.dumps(st))
        http = FakeHttp({})
        self.run_nopending(http)
        self.assertEqual(http.urls, [])


if __name__ == "__main__":
    unittest.main()
