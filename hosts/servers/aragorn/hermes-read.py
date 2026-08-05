#!/usr/bin/env python3
"""Gmail and Paperless access for Hermes, via the local broker.

This is the only path Hermes has to either system. It holds no
credentials and knows no URLs: it serialises one of a fixed set of
operations onto the broker's Unix socket and prints the redacted JSON
reply. Every text field has already been through Presidio by the time it
is printed here.

Surface is read-only except ``mail queue-paperless``, which asks the
broker to copy one message onto the fixed Gmail label ``Paperless``.
"""

import argparse
import json
import os
import socket
import sys

SOCKET_PATH = os.environ.get("HERMES_BROKER_SOCKET", "/run/hermes-broker/socket")


def call(op, args):
    try:
        sock = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        sock.settimeout(90)
        sock.connect(SOCKET_PATH)
    except FileNotFoundError:
        sys.exit(
            "hermes-read: the redaction broker is not running (%s missing).\n"
            "hermes-read: check 'systemctl status hermes-broker'." % SOCKET_PATH
        )
    except PermissionError:
        sys.exit(
            "hermes-read: not permitted to reach the broker socket as %s.\n"
            "hermes-read: the account must be in the 'hermes' group."
            % os.environ.get("USER", "this user")
        )
    except OSError as exc:
        sys.exit("hermes-read: cannot reach the broker: %s" % exc.__class__.__name__)

    with sock:
        sock.sendall((json.dumps({"op": op, "args": args}) + "\n").encode("utf-8"))
        chunks = []
        while True:
            chunk = sock.recv(65536)
            if not chunk:
                break
            chunks.append(chunk)

    try:
        response = json.loads(b"".join(chunks).decode("utf-8"))
    except ValueError:
        sys.exit("hermes-read: broker returned an unreadable response")

    if not response.get("ok"):
        sys.exit("hermes-read: %s" % response.get("error", "unknown broker error"))
    json.dump(response.get("result"), sys.stdout, indent=2, ensure_ascii=False)
    sys.stdout.write("\n")


def main():
    parser = argparse.ArgumentParser(
        prog="hermes-read",
        description="Redacted Gmail and Paperless-ngx access (one fixed mail write).",
    )
    sub = parser.add_subparsers(dest="domain", required=True)

    mail = sub.add_parser("mail", help="Gmail (read + queue-paperless)").add_subparsers(
        dest="action", required=True
    )
    mail.add_parser("folders", help="list mail folders")

    mail_list = mail.add_parser("list", help="list or search message envelopes")
    mail_list.add_argument("query", nargs="*", help="himalaya search terms")
    mail_list.add_argument("--folder", default="inbox")
    mail_list.add_argument("--page", type=int, default=1)
    mail_list.add_argument("--page-size", type=int, default=20)

    mail_read = mail.add_parser("read", help="read one message by id")
    mail_read.add_argument("id")
    mail_read.add_argument("--folder", default="inbox")

    mail_queue = mail.add_parser(
        "queue-paperless",
        help="copy one message to the fixed Gmail label Paperless",
    )
    mail_queue.add_argument("id")
    mail_queue.add_argument("--folder", default="inbox")

    docs = sub.add_parser("docs", help="Paperless-ngx (read-only)").add_subparsers(
        dest="action", required=True
    )
    docs_search = docs.add_parser("search", help="full-text search documents")
    docs_search.add_argument("query")
    docs_search.add_argument("--page", type=int, default=1)
    docs_search.add_argument("--page-size", type=int, default=10)

    docs_show = docs.add_parser("show", help="read one document's OCR text by id")
    docs_show.add_argument("id")

    opts = parser.parse_args()

    # CLI uses hyphens; broker ops use underscores.
    op = "%s.%s" % (opts.domain, opts.action.replace("-", "_"))
    args = {
        k: v
        for k, v in vars(opts).items()
        if k not in ("domain", "action") and v is not None
    }
    call(op, args)


if __name__ == "__main__":
    sys.exit(main())
