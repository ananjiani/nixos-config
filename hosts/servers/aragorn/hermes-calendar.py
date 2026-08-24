#!/usr/bin/env python3
"""Credential-free calendar client for the local Hermes broker."""

import argparse
import json
import os
import socket
import sys

SOCKET_PATH = os.environ.get("HERMES_BROKER_SOCKET", "/run/hermes-broker/socket")


def call(action, args):
    try:
        sock = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        sock.settimeout(90)
        sock.connect(SOCKET_PATH)
    except FileNotFoundError:
        sys.exit(
            "hermes-calendar: the broker is not running (%s missing).\n"
            "hermes-calendar: check 'systemctl status hermes-broker'." % SOCKET_PATH
        )
    except PermissionError:
        sys.exit("hermes-calendar: not permitted to reach the broker socket")
    except OSError as exc:
        sys.exit("hermes-calendar: cannot reach the broker: %s" % exc.__class__.__name__)

    with sock:
        sock.sendall(
            (json.dumps({"op": "calendar.%s" % action, "args": args}) + "\n").encode("utf-8")
        )
        chunks = []
        while True:
            chunk = sock.recv(65536)
            if not chunk:
                break
            chunks.append(chunk)

    try:
        response = json.loads(b"".join(chunks).decode("utf-8"))
    except ValueError:
        sys.exit("hermes-calendar: broker returned an unreadable response")
    if not response.get("ok"):
        sys.exit("hermes-calendar: %s" % response.get("error", "unknown broker error"))
    json.dump(response.get("result"), sys.stdout, indent=2, ensure_ascii=False)
    sys.stdout.write("\n")


def add_calendar(parser):
    parser.add_argument(
        "--calendar", help="allowed calendar id; omit to use the configured default"
    )


def add_event_fields(parser, required):
    parser.add_argument("--summary", required=required)
    parser.add_argument("--start", required=required, help="ISO 8601 datetime")
    parser.add_argument("--end", required=required, help="ISO 8601 datetime")
    parser.add_argument("--timezone", help="IANA timezone for local start and end")
    parser.add_argument(
        "--all-day",
        action="store_true",
        default=None,
        help="use YYYY-MM-DD start and end",
    )
    parser.add_argument("--description")
    parser.add_argument("--location")


def main():
    parser = argparse.ArgumentParser(
        prog="hermes-calendar",
        description="Manage EteSync calendars through the constrained local broker.",
    )
    actions = parser.add_subparsers(dest="action", required=True)
    actions.add_parser("calendars", help="list calendars")

    list_parser = actions.add_parser("list", help="list events in a date window")
    add_calendar(list_parser)
    list_parser.add_argument("--from", dest="date_from", required=True, help="YYYY-MM-DD")
    list_parser.add_argument("--to", dest="date_to", required=True, help="YYYY-MM-DD")

    search_parser = actions.add_parser("search", help="search event titles in a date window")
    add_calendar(search_parser)
    search_parser.add_argument("--from", dest="date_from", required=True, help="YYYY-MM-DD")
    search_parser.add_argument("--to", dest="date_to", required=True, help="YYYY-MM-DD")
    search_parser.add_argument("query")

    conflict_parser = actions.add_parser("conflicts", help="check an interval for conflicts")
    add_calendar(conflict_parser)
    conflict_parser.add_argument("--start", required=True, help="ISO 8601 local datetime")
    conflict_parser.add_argument("--end", required=True, help="ISO 8601 local datetime")
    conflict_parser.add_argument("--timezone", required=True, help="IANA timezone")

    read_parser = actions.add_parser("read", help="read one event")
    add_calendar(read_parser)
    read_parser.add_argument("id")

    create_parser = actions.add_parser("create", help="create one event")
    add_calendar(create_parser)
    add_event_fields(create_parser, required=True)
    create_parser.add_argument(
        "--repeat", choices=("daily", "weekly", "monthly", "yearly")
    )
    create_parser.add_argument("--count", type=int)
    create_parser.add_argument(
        "--alarm-minutes", action="append", type=int, default=[], metavar="MINUTES"
    )

    update_parser = actions.add_parser("update", help="change one event")
    add_calendar(update_parser)
    update_parser.add_argument("id")
    add_event_fields(update_parser, required=False)

    delete_parser = actions.add_parser("delete", help="delete one event")
    add_calendar(delete_parser)
    delete_parser.add_argument("id")

    opts = parser.parse_args()
    args = {
        key: value
        for key, value in vars(opts).items()
        if key != "action" and value is not None
    }
    call(opts.action, args)


if __name__ == "__main__":
    sys.exit(main())
