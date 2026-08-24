#!/usr/bin/env python3
"""Safe calendar document helpers for the Hermes Calendula wrapper."""

from datetime import date, datetime, time, timedelta
import json
import os
import re
import subprocess
import tempfile
from uuid import uuid4
from zoneinfo import ZoneInfo, ZoneInfoNotFoundError

from icalendar import Alarm, Calendar, Event
import recurring_ical_events


CREATE_FIELDS = {
    "alarm_minutes",
    "all_day",
    "count",
    "description",
    "end",
    "location",
    "repeat",
    "start",
    "summary",
    "timezone",
}
UPDATE_FIELDS = {
    "all_day",
    "description",
    "end",
    "location",
    "start",
    "summary",
    "timezone",
}
MAX_ICALENDAR_BYTES = 1024 * 1024
MAX_CALENDULA_OUTPUT_BYTES = 16 * 1024 * 1024
MAX_TOTAL_ICALENDAR_BYTES = 16 * 1024 * 1024
MAX_EVENT_COMPONENTS = 100
MAX_OCCURRENCES = 5000
ALLOWED_RECURRENCE_KEYS = {
    "BYDAY",
    "BYMONTH",
    "BYMONTHDAY",
    "BYSETPOS",
    "BYYEARDAY",
    "BYWEEKNO",
    "COUNT",
    "FREQ",
    "INTERVAL",
    "UNTIL",
    "WKST",
}
ALLOWED_RECURRENCE_FREQUENCIES = {"DAILY", "WEEKLY", "MONTHLY", "YEARLY"}


def _check_fields(args, allowed):
    unknown = sorted(set(args) - allowed)
    if unknown:
        raise ValueError("unsupported event field: %s" % unknown[0])


def _datetime(value, timezone_name=None):
    try:
        parsed = datetime.fromisoformat(value)
    except (TypeError, ValueError):
        raise ValueError("datetime must use ISO 8601 format")

    if timezone_name:
        if parsed.tzinfo is not None:
            raise ValueError("use a local datetime when timezone is set")
        try:
            timezone = ZoneInfo(timezone_name)
        except ZoneInfoNotFoundError:
            raise ValueError("timezone must be a valid IANA name")
        candidates = []
        for fold in (0, 1):
            candidate = parsed.replace(tzinfo=timezone, fold=fold)
            round_trip = (
                candidate.astimezone(ZoneInfo("UTC"))
                .astimezone(timezone)
                .replace(tzinfo=None)
            )
            if round_trip == parsed:
                candidates.append(candidate)
        offsets = {candidate.utcoffset() for candidate in candidates}
        if not candidates:
            raise ValueError("local datetime does not exist in this timezone")
        if len(offsets) > 1:
            raise ValueError("local datetime is ambiguous in this timezone")
        parsed = candidates[0]
    elif parsed.tzinfo is None:
        raise ValueError("datetime needs an offset or a timezone")
    return parsed


def _all_day_dates(args):
    if args.get("timezone"):
        raise ValueError("timezone must not be set for an all-day event")
    try:
        return date.fromisoformat(args.get("start")), date.fromisoformat(args.get("end"))
    except (TypeError, ValueError):
        raise ValueError("all-day dates must use YYYY-MM-DD")


def build_event(args, uid=None, now=None):
    _check_fields(args, CREATE_FIELDS)
    summary = args.get("summary")
    if not isinstance(summary, str) or not summary.strip():
        raise ValueError("summary is required")

    if args.get("all_day"):
        start, end = _all_day_dates(args)
    else:
        timezone_name = args.get("timezone")
        start = _datetime(args.get("start"), timezone_name)
        end = _datetime(args.get("end"), timezone_name)
    if end <= start:
        raise ValueError("end must be after start")

    calendar = Calendar()
    calendar.add("prodid", "-//Hermes Calendula Wrapper//EN")
    calendar.add("version", "2.0")

    event = Event()
    event.add("uid", uid or "hermes-%s" % uuid4())
    event.add("dtstamp", now or datetime.now(tz=ZoneInfo("UTC")))
    event.add("summary", summary.strip())
    event.add("dtstart", start)
    event.add("dtend", end)

    for field in ("description", "location"):
        value = args.get(field)
        if value:
            event.add(field, str(value))

    repeat = args.get("repeat")
    if repeat:
        if repeat not in ("daily", "weekly", "monthly", "yearly"):
            raise ValueError("repeat must be daily, weekly, monthly, or yearly")
        count = args.get("count")
        if count is None:
            raise ValueError("count is required for a recurring event")
        count = int(count)
        if count < 1 or count > 1000:
            raise ValueError("count must be between 1 and 1000")
        event.add("rrule", {"freq": [repeat.upper()], "count": [count]})
    elif args.get("count") is not None:
        raise ValueError("repeat is required when count is set")

    alarm_minutes = args.get("alarm_minutes") or []
    if not isinstance(alarm_minutes, list):
        raise ValueError("alarm_minutes must be a list")
    if len(alarm_minutes) > 10:
        raise ValueError("no more than 10 alarms are allowed")
    for raw_minutes in alarm_minutes:
        minutes = int(raw_minutes)
        if minutes < 0 or minutes > 525600:
            raise ValueError("alarm minutes must be between 0 and 525600")
        alarm = Alarm()
        alarm.add("action", "DISPLAY")
        alarm.add("description", summary.strip())
        alarm.add("trigger", -timedelta(minutes=minutes))
        event.add_component(alarm)

    calendar.add_component(event)
    return calendar.to_ical()


def _replace(component, name, value):
    if name.upper() in component:
        del component[name.upper()]
    component.add(name, value)


def patch_event(document, _resource_id, changes, now=None):
    """Change one VEVENT while preserving fields the caller did not name.

    Calendula identifies a stored resource separately from the VEVENT UID.
    The caller already selected the resource and supplied its current contents.
    """
    _check_fields(changes, UPDATE_FIELDS)
    try:
        calendar = Calendar.from_ical(document)
    except (TypeError, ValueError) as exc:
        raise ValueError("event data is not valid iCalendar") from exc

    events = calendar.walk("VEVENT")
    if len(events) != 1:
        raise ValueError("event data must contain exactly one VEVENT")
    event = events[0]

    if "summary" in changes:
        summary = changes["summary"]
        if not isinstance(summary, str) or not summary.strip():
            raise ValueError("summary must not be empty")
        _replace(event, "summary", summary.strip())

    changes_time = (
        "start" in changes
        or "end" in changes
        or "timezone" in changes
        or "all_day" in changes
    )
    if changes_time:
        if "start" not in changes or "end" not in changes:
            raise ValueError("start and end must change together")
        if changes.get("all_day"):
            start, end = _all_day_dates(changes)
        else:
            timezone_name = changes.get("timezone")
            start = _datetime(changes["start"], timezone_name)
            end = _datetime(changes["end"], timezone_name)
        if end <= start:
            raise ValueError("end must be after start")
        _replace(event, "dtstart", start)
        _replace(event, "dtend", end)

    for field in ("description", "location"):
        if field not in changes:
            continue
        if field.upper() in event:
            del event[field.upper()]
        if changes[field]:
            event.add(field, str(changes[field]))

    sequence = int(event.get("SEQUENCE", 0)) + 1
    _replace(event, "sequence", sequence)
    _replace(event, "dtstamp", now or datetime.now(tz=ZoneInfo("UTC")))
    return calendar.to_ical()


class CalendulaError(Exception):
    pass


class EventNotFound(CalendulaError):
    pass


def _check_recurrence_budget(calendar):
    events = calendar.walk("VEVENT")
    if len(events) > MAX_EVENT_COMPONENTS:
        raise CalendulaError("calendar item has too many VEVENT components")
    explicit_dates = 0
    for event in events:
        for property_name in ("RRULE", "EXRULE"):
            rule = event.get(property_name)
            if not rule:
                continue
            keys = {str(key).upper() for key in rule.keys()}
            unsupported = sorted(keys - ALLOWED_RECURRENCE_KEYS)
            if unsupported:
                raise CalendulaError(
                    "calendar item uses unsupported recurrence key: %s"
                    % unsupported[0]
                )
            frequency = str((rule.get("FREQ") or [""])[0]).upper()
            if frequency not in ALLOWED_RECURRENCE_FREQUENCIES:
                raise CalendulaError("calendar item recurrence frequency is too dense")
            for values in rule.values():
                if not isinstance(values, list):
                    values = [values]
                if len(values) > 366:
                    raise CalendulaError("calendar item recurrence rule is too large")
            counts = rule.get("COUNT") or []
            if counts and int(counts[0]) > MAX_OCCURRENCES:
                raise CalendulaError("calendar item recurrence count is too large")

        rdates = event.get("RDATE")
        if rdates:
            if not isinstance(rdates, list):
                rdates = [rdates]
            for rdate in rdates:
                values = getattr(rdate, "dts", None)
                explicit_dates += len(values) if values is not None else 1
                if explicit_dates > MAX_OCCURRENCES:
                    raise CalendulaError("calendar item has too many explicit dates")


class CalendulaClient:
    """Constrained JSON client for one Calendula CalDAV account."""

    def __init__(self, binary, config, allowed_calendars, runner=subprocess.run):
        self.binary = binary
        self.config = config
        self.allowed_calendars = frozenset(allowed_calendars)
        self.runner = runner

    @staticmethod
    def _identifier(value, label):
        if not isinstance(value, str) or not value or len(value) > 512:
            raise ValueError("%s identifier is invalid" % label)
        if value.startswith("-"):
            raise ValueError("%s identifier is invalid" % label)
        if re.search(r"[\x00-\x1f\x7f]", value):
            raise ValueError("%s identifier contains control characters" % label)
        return value

    def _calendar(self, value):
        value = self._identifier(value, "calendar")
        if value not in self.allowed_calendars:
            raise ValueError("calendar is not in the allowed set")
        return value

    @staticmethod
    def _date(value, label):
        if not isinstance(value, str) or not re.fullmatch(r"\d{4}-\d{2}-\d{2}", value):
            raise ValueError("%s must use YYYY-MM-DD" % label)
        try:
            date.fromisoformat(value)
        except ValueError:
            raise ValueError("%s must be a real calendar date" % label)
        return value

    def _run(self, *extra, input_data=None):
        argv = [
            self.binary,
            "--config",
            self.config,
            "--account",
            "etesync",
            "--backend",
            "caldav",
            "--json",
            *extra,
        ]
        environment = {
            "HOME": os.environ.get("HOME", "/var/lib/hermes-broker"),
            "PATH": os.environ.get("PATH", "/run/current-system/sw/bin"),
            "SSL_CERT_FILE": os.environ.get("SSL_CERT_FILE", ""),
        }
        try:
            if self.runner is subprocess.run:
                with tempfile.TemporaryFile() as stdout_file, tempfile.TemporaryFile() as stderr_file:
                    proc = self.runner(
                        argv,
                        input=input_data,
                        stdout=stdout_file,
                        stderr=stderr_file,
                        timeout=60,
                        shell=False,
                        env=environment,
                    )
                    stdout_size = stdout_file.tell()
                    stderr_size = stderr_file.tell()
                    if stdout_size > MAX_CALENDULA_OUTPUT_BYTES:
                        raise CalendulaError("Calendula response is too large")
                    if stderr_size > MAX_CALENDULA_OUTPUT_BYTES:
                        raise CalendulaError("Calendula error output is too large")
                    stdout_file.seek(0)
                    stderr_file.seek(0)
                    stdout = stdout_file.read()
                    stderr = stderr_file.read()
            else:
                proc = self.runner(
                    argv,
                    input=input_data,
                    capture_output=True,
                    timeout=60,
                    shell=False,
                    env=environment,
                )
                stdout = proc.stdout
                stderr = getattr(proc, "stderr", b"") or b""
                if len(stdout) > MAX_CALENDULA_OUTPUT_BYTES:
                    raise CalendulaError("Calendula response is too large")
                if len(stderr) > MAX_CALENDULA_OUTPUT_BYTES:
                    raise CalendulaError("Calendula error output is too large")
        except subprocess.TimeoutExpired as exc:
            raise CalendulaError("calendar request timed out") from exc
        except OSError as exc:
            raise CalendulaError("could not run Calendula: %s" % exc.__class__.__name__) from exc
        if proc.returncode != 0:
            raise CalendulaError("calendar request failed (Calendula exit %d)" % proc.returncode)
        try:
            return json.loads(stdout.decode("utf-8"))
        except (AttributeError, UnicodeDecodeError, ValueError) as exc:
            raise CalendulaError("Calendula returned a non-JSON response") from exc

    def list_calendars(self):
        if not self.allowed_calendars:
            raise CalendulaError("calendar allow-list is not configured")
        result = self._run("calendar", "list")
        calendars = result.get("calendars") if isinstance(result, dict) else None
        if isinstance(calendars, list):
            result["calendars"] = [
                item
                for item in calendars
                if str(item.get("id")) in self.allowed_calendars
            ]
        return result

    def list_events(self, calendar, date_from, date_to):
        calendar = self._calendar(calendar)
        date_from = self._date(date_from, "from")
        date_to = self._date(date_to, "to")
        if date_to < date_from:
            raise ValueError("to must not be before from")
        range_days = (
            date.fromisoformat(date_to) - date.fromisoformat(date_from)
        ).days
        if range_days > 366:
            raise ValueError("calendar ranges must not exceed 366 days")
        return self._run(
            "event",
            "list",
            "--calendar",
            calendar,
            "--from",
            date_from,
            "--to",
            date_to,
        )

    def search_events(self, calendar, date_from, date_to, query):
        if not isinstance(query, str) or not query.strip() or len(query) > 256:
            raise ValueError("query must contain 1 to 256 characters")
        result = self.list_events(calendar, date_from, date_to)
        events = result.get("events") if isinstance(result, dict) else None
        if not isinstance(events, list):
            raise CalendulaError("Calendula event list has no events array")
        needle = query.strip().casefold()
        result["events"] = [
            event
            for event in events
            if needle in str(event.get("summary", "")).casefold()
        ]
        return result

    def _list_items(self, calendar):
        calendar = self._calendar(calendar)
        page_size = 100
        found = []
        total_icalendar_bytes = 0
        for page in range(1, 101):
            result = self._run(
                "item",
                "list",
                "--calendar",
                calendar,
                "--page",
                str(page),
                "--page-size",
                str(page_size),
            )
            items = result.get("items") or []
            if not isinstance(items, list):
                raise CalendulaError("Calendula item list has no items array")
            for item in items:
                if not isinstance(item, dict):
                    raise CalendulaError("Calendula item list has an invalid item")
                contents = item.get("contents")
                if not isinstance(contents, str):
                    raise CalendulaError("calendar item has no iCalendar contents")
                item_bytes = len(contents.encode("utf-8"))
                if item_bytes > MAX_ICALENDAR_BYTES:
                    raise CalendulaError("calendar item is too large")
                total_icalendar_bytes += item_bytes
                if total_icalendar_bytes > MAX_TOTAL_ICALENDAR_BYTES:
                    raise CalendulaError("calendar contents exceed the total size limit")
            found.extend(items)
            if len(items) < page_size:
                break
        else:
            result = self._run(
                "item",
                "list",
                "--calendar",
                calendar,
                "--page",
                "101",
                "--page-size",
                "100",
            )
            overflow = result.get("items") or []
            if not isinstance(overflow, list):
                raise CalendulaError("Calendula item list has no items array")
            if overflow:
                raise CalendulaError("calendar has more than 10000 resources")
        return found

    def _find_item(self, calendar, event_id):
        event_id = self._identifier(event_id, "event")
        for item in self._list_items(calendar):
            if str(item.get("id")) == event_id:
                return item
        raise EventNotFound("event was not found")

    def read_event(self, calendar, event_id):
        item = self._find_item(calendar, event_id)
        return {
            "id": str(item.get("id")),
            "etag": item.get("etag"),
            "contents": item.get("contents"),
        }

    def create_event(self, calendar, args):
        calendar = self._calendar(calendar)
        document = build_event(args)
        result = self._run(
            "event",
            "create",
            "--calendar",
            calendar,
            "-",
            input_data=document,
        )
        message = result.get("message") if isinstance(result, dict) else None
        match = (
            re.search(r"Event `([^`]+)` successfully created", message)
            if isinstance(message, str)
            else None
        )
        if not match:
            raise CalendulaError("event was created but its resource id was not returned")
        resource_id = match.group(1)
        result["id"] = resource_id
        result["current"] = self.read_event(calendar, resource_id)
        return result

    def update_event(self, calendar, event_id, changes):
        calendar = self._calendar(calendar)
        event_id = self._identifier(event_id, "event")
        item = self._find_item(calendar, event_id)
        etag = item.get("etag")
        contents = item.get("contents")
        if not isinstance(etag, str) or not etag:
            raise CalendulaError("event has no ETag; update refused")
        if not isinstance(contents, str) or not contents:
            raise CalendulaError("event has no iCalendar contents; update refused")
        document = patch_event(contents, event_id, changes)
        return self._run(
            "event",
            "update",
            "--calendar",
            calendar,
            event_id,
            "--if-match",
            etag,
            "-",
            input_data=document,
        )

    @staticmethod
    def _event_bounds(event, timezone):
        start = event.decoded("DTSTART")
        if "DTEND" in event:
            end = event.decoded("DTEND")
        elif "DURATION" in event:
            end = start + event.decoded("DURATION")
        elif isinstance(start, date) and not isinstance(start, datetime):
            end = start + timedelta(days=1)
        else:
            end = start
        if isinstance(start, datetime):
            if start.tzinfo is None:
                start = start.replace(tzinfo=timezone)
        else:
            start = datetime.combine(start, time.min, tzinfo=timezone)
        if isinstance(end, datetime):
            if end.tzinfo is None:
                end = end.replace(tzinfo=timezone)
        else:
            end = datetime.combine(end, time.min, tzinfo=timezone)
        return start, end

    def conflicts(self, calendar, start, end, timezone_name):
        calendar = self._calendar(calendar)
        if not isinstance(timezone_name, str) or not timezone_name:
            raise ValueError("timezone is required for conflict checks")
        window_start = _datetime(start, timezone_name)
        window_end = _datetime(end, timezone_name)
        if window_end <= window_start:
            raise ValueError("end must be after start")
        if window_end - window_start > timedelta(days=366):
            raise ValueError("conflict windows must not exceed 366 days")
        timezone = ZoneInfo(timezone_name)
        conflicts = []
        expanded_occurrences = 0
        for item in self._list_items(calendar):
            contents = item.get("contents")
            if not isinstance(contents, str) or not contents:
                raise CalendulaError("calendar item has no iCalendar contents")
            if len(contents.encode("utf-8")) > MAX_ICALENDAR_BYTES:
                raise CalendulaError("calendar item is too large for conflict checks")
            try:
                document = Calendar.from_ical(contents)
                _check_recurrence_budget(document)
                occurrences = recurring_ical_events.of(document).between(
                    window_start, window_end
                )
            except CalendulaError:
                raise
            except (TypeError, ValueError) as exc:
                raise CalendulaError("calendar item has invalid recurrence data") from exc
            expanded_occurrences += len(occurrences)
            if len(occurrences) > MAX_OCCURRENCES:
                raise CalendulaError("calendar item expands to too many occurrences")
            if expanded_occurrences > MAX_OCCURRENCES:
                raise CalendulaError("calendar expands to too many occurrences")
            for event in occurrences:
                event_start, event_end = self._event_bounds(event, timezone)
                if event_start < window_end and event_end > window_start:
                    conflicts.append(
                        {
                            "id": str(item.get("id")),
                            "summary": str(event.get("SUMMARY", "")),
                            "start": event_start.isoformat(),
                            "end": event_end.isoformat(),
                        }
                    )
        return {
            "calendar": calendar,
            "start": window_start.isoformat(),
            "end": window_end.isoformat(),
            "conflicts": conflicts,
        }

    def delete_event(self, calendar, event_id):
        calendar = self._calendar(calendar)
        event_id = self._identifier(event_id, "event")
        self._find_item(calendar, event_id)
        result = self._run("event", "delete", "--calendar", calendar, event_id)
        try:
            self._find_item(calendar, event_id)
        except EventNotFound:
            result["verified_absent"] = True
            return result
        raise CalendulaError("calendar resource still exists after delete")
