#!/usr/bin/env python3
"""Redaction broker between Hermes and Gmail / Paperless-ngx.

Hermes (running as ammar) never holds the Gmail app password or the
Paperless API token and never speaks IMAP or HTTP itself. It sends a
fixed-vocabulary request over a Unix socket; this process performs the
call under its own identity, runs every string of the result through
Presidio, and returns only redacted text.

Surface is read-only except for one fixed write: copy a message to the
Gmail label ``Paperless`` so Paperless-ngx can import it. No other
label, destination, send, delete, move, or flag operation exists.

Fail-closed properties:

* Presidio is loaded and self-tested before the socket is created. If
  the engine or the self-test fails the process exits non-zero and the
  socket never appears, so callers get a connection error rather than
  raw text.
* Redaction happens here, not in a Hermes hook. Hermes hooks fail open;
  an exception in this process yields an error response with no content.
* Any unexpected exception while handling a request is converted to a
  bare error string. Raw upstream payloads are never echoed back.
"""

import argparse
import json
import os
import re
import socket
import socketserver
import subprocess
import sys
import urllib.error
import urllib.parse
import urllib.request

from presidio_analyzer import AnalyzerEngine, Pattern, PatternRecognizer
from presidio_analyzer.nlp_engine import NlpEngineProvider

SOCKET_PATH = os.environ.get("HERMES_BROKER_SOCKET", "/run/hermes-broker/socket")
HIMALAYA_BIN = os.environ.get("HERMES_BROKER_HIMALAYA", "himalaya")
HIMALAYA_CONFIG = os.environ.get("HERMES_BROKER_HIMALAYA_CONFIG", "")
PAPERLESS_URL = os.environ.get("HERMES_BROKER_PAPERLESS_URL", "https://paperless.lan")
PAPERLESS_TOKEN_FILE = os.environ.get(
    "HERMES_BROKER_PAPERLESS_TOKEN_FILE", "/run/secrets/paperless_api_token"
)

MAX_REQUEST_BYTES = 64 * 1024
TIMEOUT_SECONDS = 60

# High-impact identifiers only. Names, emails, phone numbers, addresses,
# dates, and amounts are deliberately absent: they are the context that
# makes a summary useful, and they are not the exfiltration target.
ENTITIES = [
    "US_SSN",
    "CREDIT_CARD",
    "US_BANK_NUMBER",
    "IBAN_CODE",
    "US_PASSPORT",
    "US_DRIVER_LICENSE",
    "CRYPTO",
    "US_ITIN",
    "PRIVATE_KEY_BLOCK",
    "CREDENTIAL",
    "RECOVERY_CODE",
]

# Presidio's "very weak" patterns score as low as 0.01. A low threshold
# over-redacts some ordinary long digit strings; that is the cheap side
# of this trade.
SCORE_THRESHOLD = 0.2

# A secret label, shared by the two CREDENTIAL patterns below.
_SECRET_LABEL = (
    r"(?:pass(?:word|phrase)|passwd|secret|api[_\- ]?key|auth[_\- ]?token"
    r"|access[_\- ]?token|bearer|client[_\- ]?secret|pin"
    r"|(?:recovery|seed)[_\- ]phrase|mnemonic)"
)

# Deterministic backstops. These do not depend on Presidio's context
# enhancer or on scoring, so the self-test below is a real invariant.
EXTRA_RECOGNIZERS = [
    (
        "PRIVATE_KEY_BLOCK",
        "private_key_block",
        [
            # Covers OPENSSH/RSA/EC/DSA/ENCRYPTED and the bare form; the
            # label between BEGIN and PRIVATE KEY is always upper-case.
            Pattern(
                "pem private key",
                r"-----BEGIN [A-Z ]*PRIVATE KEY-----[\s\S]*?-----END [A-Z ]*PRIVATE KEY-----",
                1.0,
            ),
            # OCR and previews truncate. An unterminated header is still a
            # key: swallow the base64 body that follows it.
            Pattern(
                "truncated private key",
                r"-----BEGIN [A-Z ]*PRIVATE KEY-----(?:\s*[A-Za-z0-9+/=]{16,}\s*)+",
                1.0,
            ),
        ],
    ),
    (
        "CREDENTIAL",
        "credential_assignment",
        [
            # With an explicit separator the value runs to end of line, so a
            # secret containing spaces ("correct horse battery staple") is
            # covered as well as a single opaque token.
            Pattern(
                "labelled secret",
                r"(?i)\b" + _SECRET_LABEL + r"\b[ \t]*(?:is|:|=)[ \t]*\S[^\n]{3,}",
                0.9,
            ),
            # No punctuation at all ("password hunter2hunter2"). Ending the
            # value at whitespace and demanding a mixed letter/digit token
            # keeps ordinary prose ("password was changed") unredacted.
            Pattern(
                "labelled secret, unpunctuated",
                r"(?i)\b" + _SECRET_LABEL + r"\b[ \t]+(?=\S*[A-Za-z])(?=\S*[0-9])[^\s]{6,}",
                0.9,
            ),
            # JWTs are self-identifying: the header always base64s to eyJ.
            Pattern(
                "jwt",
                r"\beyJ[A-Za-z0-9_-]{8,}\.[A-Za-z0-9_-]{8,}\.[A-Za-z0-9_-]{8,}",
                1.0,
            ),
            Pattern("aws access key", r"\b(?:AKIA|ASIA)[0-9A-Z]{16}\b", 0.9),
            Pattern("github token", r"\bgh[pousr]_[A-Za-z0-9]{20,}\b", 0.9),
            Pattern("slack token", r"\bxox[abposr]-[A-Za-z0-9-]{10,}\b", 0.9),
        ],
    ),
    (
        "RECOVERY_CODE",
        "recovery_codes",
        [
            # `[\s,;]` spans newlines, so a label followed by one code per
            # line is a single hit. Codes may be hyphenated (ABCD-EFGH).
            Pattern(
                "labelled recovery codes",
                r"(?i)\b(?:recovery|backup|one[\- ]?time|2fa|two[\- ]?factor)[\- ]?codes?\b"
                r"[ \t]*(?:are|:|=)?[\s]*(?:[A-Za-z0-9]{4,12}(?:-[A-Za-z0-9]{4,12})?[\s,;]*){2,}",
                0.9,
            ),
            Pattern("hyphenated code pair", r"\b[a-z0-9]{5}-[a-z0-9]{5}\b", 0.6),
            # Two or more adjacent ABCD-EFGH pairs, across lines. Requiring
            # a run keeps lone identifiers like ORDER-1234 alone.
            Pattern(
                "upper-case code run",
                r"\b[A-Z0-9]{4,6}-[A-Z0-9]{4,6}(?:[\s,;]+[A-Z0-9]{4,6}-[A-Z0-9]{4,6})+",
                0.8,
            ),
        ],
    ),
    # Presidio scores a dashed SSN via context words; make it
    # unconditional so redaction never depends on surrounding prose.
    (
        "US_SSN",
        "ssn_dashed",
        [Pattern("dashed ssn", r"\b\d{3}-\d{2}-\d{4}\b", 0.9)],
    ),
    # Presidio's US_BANK_NUMBER catches account numbers but not a bare
    # 9-digit ABA routing number. Anchor on the label to stay precise.
    (
        "US_BANK_NUMBER",
        "aba_routing",
        [
            Pattern(
                "labelled routing number",
                r"(?i)\b(?:routing|aba|rtn)\b[\s:#=]*(?:number|no\.?|transit)?[\s:#=]*\d{9}\b",
                0.9,
            )
        ],
    ),
]

ANALYZER = None


def build_analyzer():
    """Construct the Presidio engine. Raises if anything is missing."""
    provider = NlpEngineProvider(
        nlp_configuration={
            "nlp_engine_name": "spacy",
            "models": [{"lang_code": "en", "model_name": "en_core_web_sm"}],
        }
    )
    engine = AnalyzerEngine(nlp_engine=provider.create_engine(), supported_languages=["en"])
    for entity, name, patterns in EXTRA_RECOGNIZERS:
        engine.registry.add_recognizer(
            PatternRecognizer(supported_entity=entity, name=name, patterns=patterns)
        )
    return engine


def redact_text(text):
    """Replace high-impact spans with typed placeholders."""
    if not text or not text.strip():
        return text
    results = ANALYZER.analyze(
        text=text,
        language="en",
        entities=ENTITIES,
        score_threshold=SCORE_THRESHOLD,
    )
    if not results:
        return text
    # Merge overlaps so nested hits do not corrupt offsets.
    spans = []
    for r in sorted(results, key=lambda r: (r.start, -r.end)):
        if spans and r.start <= spans[-1][1]:
            prev = spans[-1]
            spans[-1] = (prev[0], max(prev[1], r.end), prev[2])
        else:
            spans.append((r.start, r.end, r.entity_type))
    out = []
    cursor = 0
    for start, end, entity in spans:
        out.append(text[cursor:start])
        out.append("[REDACTED:%s]" % entity)
        cursor = end
    out.append(text[cursor:])
    return "".join(out)


def redact(value):
    """Recursively redact every string in a JSON-shaped value."""
    if isinstance(value, str):
        return redact_text(value)
    if isinstance(value, list):
        return [redact(v) for v in value]
    if isinstance(value, dict):
        return {k: redact(v) for k, v in value.items()}
    return value


# Every entity in ENTITIES appears here in a realistic shape. The private
# key is a genuine multi-line PEM body rather than a one-token stand-in,
# so the block pattern is exercised the way OCR would present it.
SELF_TEST_TEXT = (
    "Invoice from Jane Doe <jane@example.com>, phone 415-555-0134, "
    "dated 2026-03-04, total $1,204.55, shipped to 22 Elm Street.\n"
    "SSN 123-45-6789. Card 4111 1111 1111 1111. IBAN GB33BUKB20201555555555.\n"
    "Routing number 021000021. Bank account number 12345678901.\n"
    "US passport number 912803456, driver's license number D1234567.\n"
    "ITIN 912-78-1234 on file.\n"
    "Refund to bitcoin wallet 1BvBMSEYstWetqTFn5Au4m4GFg7xJaNVN2.\n"
    "password: hunter2hunter2\n"
    "portal password hunter7hunter7\n"
    "Wi-Fi password: correct horse battery staple\n"
    "AKIAIOSFODNN7EXAMPLE\n"
    "Authorization: Bearer "
    "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9"
    ".eyJzdWIiOiIxMjM0NTY3ODkwIiwibmFtZSI6IkpvaG4gRG9lIn0"
    ".dBjftJeZ4CVPmB92K27uhbUJU1p1r_wW1gFWFOEjXkw\n"
    "-----BEGIN RSA PRIVATE KEY-----\n"
    "MIIBOwIBAAJBAK7bTLnrVXBQMhBQTn3Wh3zBRHRfPvKcRPnrEXAMPLEkeyBODYxx\n"
    "c2hvdWxkbmV2ZXJsZWFrdGhyb3VnaHRoZWJyb2tlcmF0YWxsAgMBAAECQQCEXAMP\n"
    "LEdGhpc2lzbm90YXJlYWxrZXlidXRpdGlzc2hhcGVkbGlrZW9uZQIhAP7EXAMPLE\n"
    "-----END RSA PRIVATE KEY-----\n"
    "Recovery codes: a1b2c3d4 e5f6g7h8 i9j0k1l2\n"
    "Backup codes:\nABCD-EFGH\nJKLM-NPQR\nSTUV-WXYZ\n"
)

MUST_VANISH = [
    "123-45-6789",
    "021000021",
    "12345678901",
    "4111 1111 1111 1111",
    "GB33BUKB20201555555555",
    "912803456",
    "D1234567",
    "912-78-1234",
    "1BvBMSEYstWetqTFn5Au4m4GFg7xJaNVN2",
    "hunter2hunter2",
    "hunter7hunter7",
    "correct horse battery staple",
    "AKIAIOSFODNN7EXAMPLE",
    "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9",
    "dBjftJeZ4CVPmB92K27uhbUJU1p1r_wW1gFWFOEjXkw",
    "MIIBOwIBAAJBAK7bTLnrVXBQMhBQTn3Wh3zBRHRfPvKcRPnrEXAMPLEkeyBODYxx",
    "c2hvdWxkbmV2ZXJsZWFrdGhyb3VnaHRoZWJyb2tlcmF0YWxs",
    "a1b2c3d4",
    "ABCD-EFGH",
    "STUV-WXYZ",
]

MUST_REMAIN = [
    "Jane Doe",
    "jane@example.com",
    "415-555-0134",
    "2026-03-04",
    "$1,204.55",
    "22 Elm Street",
]


def self_test():
    """Prove the engine redacts the dangerous set and keeps context.

    Returns a list of failure strings; empty means healthy.
    """
    redacted = redact_text(SELF_TEST_TEXT)
    failures = []
    for needle in MUST_VANISH:
        if needle in redacted:
            failures.append("leaked: %s" % needle)
    for needle in MUST_REMAIN:
        if needle not in redacted:
            failures.append("over-redacted: %s" % needle)
    # Enabling an entity without a sample would silently ship an
    # unexercised recognizer, so coverage is part of the invariant.
    found = {
        r.entity_type
        for r in ANALYZER.analyze(
            text=SELF_TEST_TEXT,
            language="en",
            entities=ENTITIES,
            score_threshold=SCORE_THRESHOLD,
        )
    }
    for entity in ENTITIES:
        if entity not in found:
            failures.append("no self-test sample matched: %s" % entity)
    return failures, redacted


def queue_paperless_self_check():
    """Stub-test the only mail write: fixed destination, empty stdout OK.

    Returns a list of failure strings; empty means healthy. Does not
    touch the network or himalaya binary.
    """
    failures = []
    captured = []

    def fake_himalaya(*extra, parse_json=True):
        captured.append({"extra": list(extra), "parse_json": parse_json})
        if not parse_json:
            return None
        return {}

    real = globals()["himalaya"]
    globals()["himalaya"] = fake_himalaya
    try:
        result = op_mail_queue_paperless(
            {
                "id": "42",
                "folder": "inbox",
                # Caller-supplied destinations must be ignored.
                "label": "Evil",
                "destination": "Evil",
                "folder_dest": "Spam",
            }
        )
        expected_extra = [
            "message",
            "copy",
            "--folder",
            "inbox",
            PAPERLESS_QUEUE_LABEL,
            "42",
        ]
        if not captured:
            failures.append("queue_paperless: himalaya was not invoked")
        else:
            call = captured[0]
            if call["extra"] != expected_extra:
                failures.append(
                    "queue_paperless: argv %r != %r" % (call["extra"], expected_extra)
                )
            if call["parse_json"] is not False:
                failures.append("queue_paperless: must not require JSON stdout")
            if "Evil" in call["extra"] or "Spam" in call["extra"]:
                failures.append("queue_paperless: caller destination leaked into argv")
        if result != {
            "id": "42",
            "folder": "inbox",
            "label": PAPERLESS_QUEUE_LABEL,
        }:
            failures.append("queue_paperless: unexpected result %r" % (result,))

        # Nonzero exit → generic BrokerError, no content.
        def boom(*extra, parse_json=True):
            raise BrokerError("gmail request failed (himalaya exit 7)")

        globals()["himalaya"] = boom
        try:
            op_mail_queue_paperless({"id": "99", "folder": "inbox"})
            failures.append("queue_paperless: nonzero exit did not raise")
        except BrokerError as exc:
            msg = str(exc)
            if "exit 7" not in msg:
                failures.append("queue_paperless: error missing exit status: %r" % msg)
            if "body" in msg.lower() or "subject" in msg.lower():
                failures.append("queue_paperless: error looks contentful: %r" % msg)
    finally:
        globals()["himalaya"] = real

    # himalaya() itself: empty stdout + parse_json=False is success.
    class _Proc:
        def __init__(self, code, stdout=b"", stderr=b""):
            self.returncode = code
            self.stdout = stdout
            self.stderr = stderr

    real_run = subprocess.run
    real_config = globals().get("HIMALAYA_CONFIG")
    globals()["HIMALAYA_CONFIG"] = "/tmp/fake-himalaya.toml"
    try:
        subprocess.run = lambda *a, **k: _Proc(0, b"")
        if himalaya("message", "copy", parse_json=False) is not None:
            failures.append("himalaya: empty stdout should return None")

        subprocess.run = lambda *a, **k: _Proc(3, b"secret body", b"err body")
        try:
            himalaya("message", "copy", parse_json=False)
            failures.append("himalaya: nonzero exit did not raise")
        except BrokerError as exc:
            msg = str(exc)
            if "exit 3" not in msg:
                failures.append("himalaya: missing exit status: %r" % msg)
            if "secret" in msg or "err body" in msg:
                failures.append("himalaya: leaked stdout/stderr: %r" % msg)
    finally:
        subprocess.run = real_run
        globals()["HIMALAYA_CONFIG"] = real_config

    return failures


class BrokerError(Exception):
    pass


def read_token():
    try:
        with open(PAPERLESS_TOKEN_FILE, "r") as fh:
            token = fh.read().strip()
    except OSError:
        raise BrokerError(
            "paperless API token is unavailable (%s); check "
            "'systemctl status vault-agent-default'" % PAPERLESS_TOKEN_FILE
        )
    if not token:
        raise BrokerError(
            "paperless API token is empty; the secret is missing in OpenBao at "
            "secret/nixos/hermes-paperless"
        )
    return token


class NoRedirect(urllib.request.HTTPRedirectHandler):
    """Refuse every redirect.

    urllib's default handler replays the original headers on the new
    request, so a 302 from a compromised or misconfigured Paperless would
    hand the API token to whatever host the Location names. Returning
    None makes urllib raise the 3xx as an HTTPError instead, and the
    token is never sent a second time.
    """

    def redirect_request(self, req, fp, code, msg, headers, newurl):
        return None


# build_opener replaces the default handler of the same class, so this
# opener follows nothing. Never use urllib.request.urlopen directly.
PAPERLESS_OPENER = urllib.request.build_opener(NoRedirect)


def paperless_get(path, params):
    """GET a fixed Paperless API path. Callers never supply a URL."""
    url = "%s%s?%s" % (PAPERLESS_URL, path, urllib.parse.urlencode(params))
    req = urllib.request.Request(
        url,
        headers={
            "Authorization": "Token %s" % read_token(),
            "Accept": "application/json",
        },
        method="GET",
    )
    try:
        with PAPERLESS_OPENER.open(req, timeout=TIMEOUT_SECONDS) as resp:
            return json.loads(resp.read().decode("utf-8"))
    except urllib.error.HTTPError as exc:
        if exc.code in (301, 302, 303, 307, 308):
            # Deliberately no Location: the caller learns that the request
            # was refused, not where it was being sent.
            raise BrokerError(
                "paperless answered with a redirect for %s; refused" % path
            )
        raise BrokerError("paperless returned HTTP %s for %s" % (exc.code, path))
    except (urllib.error.URLError, OSError) as exc:
        raise BrokerError("paperless is unreachable: %s" % exc.__class__.__name__)
    except ValueError:
        raise BrokerError("paperless returned a non-JSON response")


# Text and metadata only. No archive/original/preview/thumbnail/download
# field ever leaves this allowlist.
DOC_FIELDS = (
    "id",
    "title",
    "created",
    "added",
    "correspondent",
    "document_type",
    "storage_path",
    "tags",
    "archive_serial_number",
    "page_count",
    "owner",
    "notes",
)


def pick_document(doc, content_limit=None):
    out = {k: doc.get(k) for k in DOC_FIELDS if k in doc}
    content = doc.get("content") or ""
    if content_limit is not None and len(content) > content_limit:
        content = content[:content_limit] + "…"
    out["content"] = content
    return out


def clamp(value, default, low, high):
    try:
        n = int(value)
    except (TypeError, ValueError):
        return default
    return max(low, min(high, n))


def require_id(args):
    raw = args.get("id")
    if not isinstance(raw, (int, str)) or not re.fullmatch(r"[0-9]{1,12}", str(raw)):
        raise BrokerError("id must be a positive integer")
    return str(raw)


FOLDERS = {"inbox", "sent", "drafts", "trash", "archive"}

# Fixed Gmail label watched by Paperless. Never taken from the caller.
PAPERLESS_QUEUE_LABEL = "Paperless"


def require_folder(args):
    folder = args.get("folder") or "inbox"
    if folder.lower() not in FOLDERS:
        raise BrokerError("folder must be one of: %s" % ", ".join(sorted(FOLDERS)))
    return folder.lower()


def himalaya(*extra, parse_json=True):
    if not HIMALAYA_CONFIG:
        raise BrokerError("himalaya config is not configured in the broker unit")
    # --output is global, so it goes before the subcommand: `envelope
    # list` takes free-form positional query words after it.
    cmd = [HIMALAYA_BIN, "--config", HIMALAYA_CONFIG, "--output", "json", *extra]
    try:
        proc = subprocess.run(
            cmd,
            capture_output=True,
            timeout=TIMEOUT_SECONDS,
            env={
                "HOME": os.environ.get("HOME", "/var/lib/hermes-broker"),
                "PATH": os.environ.get("PATH", "/run/current-system/sw/bin"),
                "SSL_CERT_FILE": os.environ.get("SSL_CERT_FILE", ""),
            },
        )
    except subprocess.TimeoutExpired:
        raise BrokerError("gmail request timed out")
    except OSError as exc:
        raise BrokerError("could not run himalaya: %s" % exc.__class__.__name__)
    if proc.returncode != 0:
        # stderr may quote message content; report status only.
        raise BrokerError("gmail request failed (himalaya exit %d)" % proc.returncode)
    if not parse_json:
        # Write ops (copy-to-label) may print nothing or non-JSON; success
        # is the exit status alone. Never return raw stdout/stderr.
        return None
    try:
        return json.loads(proc.stdout.decode("utf-8"))
    except ValueError:
        raise BrokerError("himalaya returned a non-JSON response")


def op_mail_folders(args):
    return {"folders": himalaya("folder", "list")}


def op_mail_list(args):
    folder = require_folder(args)
    query = args.get("query") or []
    if not isinstance(query, list):
        raise BrokerError("query must be a list of words")
    tokens = []
    for token in query:
        token = str(token)
        # No caller-supplied flags; the wrapper's argv is fixed otherwise.
        if token.startswith("-") or len(token) > 128:
            raise BrokerError("invalid search term")
        tokens.append(token)
    page = clamp(args.get("page"), 1, 1, 1000)
    page_size = clamp(args.get("page_size"), 20, 1, 100)
    extra = ["envelope", "list", "--folder", folder, "--page", str(page), "--page-size", str(page_size)]
    return {"folder": folder, "envelopes": himalaya(*extra, *tokens)}


def op_mail_read(args):
    folder = require_folder(args)
    message_id = require_id(args)
    return {
        "folder": folder,
        "id": message_id,
        "message": himalaya("message", "read", "--folder", folder, "--preview", message_id),
    }


def op_mail_queue_paperless(args):
    """Copy one message to the fixed Paperless label. Destination is not caller-supplied."""
    folder = require_folder(args)
    message_id = require_id(args)
    # Himalaya: message copy --folder <source> <destination> <id>
    # Destination is the constant PAPERLESS_QUEUE_LABEL only.
    himalaya(
        "message",
        "copy",
        "--folder",
        folder,
        PAPERLESS_QUEUE_LABEL,
        message_id,
        parse_json=False,
    )
    return {
        "id": message_id,
        "folder": folder,
        "label": PAPERLESS_QUEUE_LABEL,
    }


def op_docs_search(args):
    query = args.get("query")
    if not isinstance(query, str) or not query.strip():
        raise BrokerError("query is required")
    if len(query) > 512:
        raise BrokerError("query is too long")
    page = clamp(args.get("page"), 1, 1, 1000)
    page_size = clamp(args.get("page_size"), 10, 1, 50)
    data = paperless_get(
        "/api/documents/",
        {"query": query, "page": page, "page_size": page_size, "ordering": "-created"},
    )
    return {
        "count": data.get("count"),
        "page": page,
        "results": [pick_document(d, content_limit=600) for d in data.get("results", [])],
    }


def op_docs_show(args):
    doc_id = require_id(args)
    data = paperless_get("/api/documents/%s/" % doc_id, {})
    return {"document": pick_document(data)}


OPERATIONS = {
    "mail.folders": op_mail_folders,
    "mail.list": op_mail_list,
    "mail.read": op_mail_read,
    "mail.queue_paperless": op_mail_queue_paperless,
    "docs.search": op_docs_search,
    "docs.show": op_docs_show,
}


def audit(op, args):
    """Log the operation and identifiers only — never content."""
    detail = ""
    if "id" in args:
        detail = " id=%s" % str(args.get("id"))[:16]
    print("broker: op=%s%s" % (op, detail), file=sys.stderr, flush=True)


def handle(payload):
    try:
        request = json.loads(payload.decode("utf-8"))
    except (ValueError, UnicodeDecodeError):
        return {"ok": False, "error": "request was not valid JSON"}
    op = request.get("op")
    args = request.get("args") or {}
    if not isinstance(args, dict):
        return {"ok": False, "error": "args must be an object"}
    if op not in OPERATIONS:
        return {
            "ok": False,
            "error": "unknown operation; allowed: %s" % ", ".join(sorted(OPERATIONS)),
        }
    audit(op, args)
    try:
        result = OPERATIONS[op](args)
    except BrokerError as exc:
        return {"ok": False, "error": str(exc)}
    except Exception:
        # Deliberately opaque: an unexpected failure must not leak the
        # payload that caused it.
        return {"ok": False, "error": "broker failed to complete the request"}
    try:
        return {"ok": True, "op": op, "result": redact(result)}
    except Exception:
        return {"ok": False, "error": "redaction failed; no content returned"}


class Handler(socketserver.StreamRequestHandler):
    timeout = TIMEOUT_SECONDS

    def handle(self):
        line = self.rfile.readline(MAX_REQUEST_BYTES)
        if not line:
            return
        response = handle(line)
        self.wfile.write((json.dumps(response) + "\n").encode("utf-8"))


class Server(socketserver.UnixStreamServer):
    # Deliberately serial: the Presidio analyzer is shared mutable state
    # and the caller is a single local agent, so concurrency buys nothing
    # and costs a thread-safety argument.
    allow_reuse_address = True


def serve():
    if os.path.exists(SOCKET_PATH):
        os.unlink(SOCKET_PATH)
    old_umask = os.umask(0o007)
    try:
        server = Server(SOCKET_PATH, Handler)
    finally:
        os.umask(old_umask)
    print("broker: listening on %s" % SOCKET_PATH, file=sys.stderr, flush=True)
    server.serve_forever()


def main():
    global ANALYZER
    parser = argparse.ArgumentParser(description="Hermes redaction broker")
    parser.add_argument(
        "--self-check",
        action="store_true",
        help="run the redaction self-test and exit",
    )
    parser.add_argument(
        "--show",
        action="store_true",
        help="with --self-check, print the redacted sample",
    )
    opts = parser.parse_args()

    try:
        ANALYZER = build_analyzer()
    except Exception as exc:
        print("broker: redaction engine failed to load: %r" % (exc,), file=sys.stderr)
        return 1

    failures, redacted = self_test()
    if failures:
        print("broker: redaction self-test FAILED", file=sys.stderr)
        for failure in failures:
            print("  - %s" % failure, file=sys.stderr)
        return 1

    write_failures = queue_paperless_self_check()
    if write_failures:
        print("broker: queue-paperless self-check FAILED", file=sys.stderr)
        for failure in write_failures:
            print("  - %s" % failure, file=sys.stderr)
        return 1

    if opts.self_check:
        print("broker: redaction self-test passed")
        print("broker: queue-paperless self-check passed")
        if opts.show:
            print(redacted)
        return 0

    serve()
    return 0


if __name__ == "__main__":
    sys.exit(main())
