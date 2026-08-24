#!/usr/bin/env python3

import json
import unittest
from unittest import mock
from datetime import datetime, timedelta
from zoneinfo import ZoneInfo

from icalendar import Calendar, Event

import hermes_calendar


class BuildEventTests(unittest.TestCase):
    def test_build_event_keeps_wall_time_recurrence_and_alarm(self):
        document = hermes_calendar.build_event(
            {
                "summary": "Therapy",
                "start": "2026-09-01T14:00:00",
                "end": "2026-09-01T15:00:00",
                "timezone": "America/Chicago",
                "description": "Weekly appointment",
                "location": "Plano",
                "repeat": "weekly",
                "count": 6,
                "alarm_minutes": [30, 10],
            },
            uid="event-test-1",
            now=datetime(2026, 8, 24, 12, 0, tzinfo=ZoneInfo("UTC")),
        )

        calendar = Calendar.from_ical(document)
        event = next(iter(calendar.walk("VEVENT")))
        self.assertEqual(str(event["uid"]), "event-test-1")
        self.assertEqual(str(event["summary"]), "Therapy")
        self.assertEqual(
            event.decoded("dtstart"),
            datetime(2026, 9, 1, 14, 0, tzinfo=ZoneInfo("America/Chicago")),
        )
        self.assertEqual(event["rrule"]["FREQ"], ["WEEKLY"])
        self.assertEqual(event["rrule"]["COUNT"], [6])
        alarms = event.subcomponents
        self.assertEqual([alarm.name for alarm in alarms], ["VALARM", "VALARM"])
        self.assertEqual(
            [alarm.decoded("trigger") for alarm in alarms],
            [-timedelta(minutes=30), -timedelta(minutes=10)],
        )

    def test_build_event_rejects_unbounded_recurrence(self):
        with self.assertRaisesRegex(ValueError, "count"):
            hermes_calendar.build_event(
                {
                    "summary": "Forever",
                    "start": "2026-09-01T14:00:00-05:00",
                    "end": "2026-09-01T15:00:00-05:00",
                    "repeat": "weekly",
                }
            )

    def test_build_event_rejects_dst_gaps_and_folds(self):
        base = {
            "summary": "DST test",
            "timezone": "America/Chicago",
        }
        with self.assertRaisesRegex(ValueError, "does not exist"):
            hermes_calendar.build_event(
                {
                    **base,
                    "start": "2026-03-08T02:30:00",
                    "end": "2026-03-08T03:30:00",
                }
            )
        with self.assertRaisesRegex(ValueError, "ambiguous"):
            hermes_calendar.build_event(
                {
                    **base,
                    "start": "2026-11-01T01:30:00",
                    "end": "2026-11-01T02:30:00",
                }
            )

    def test_build_event_supports_all_day_dates(self):
        document = hermes_calendar.build_event(
            {
                "summary": "Vacation",
                "start": "2026-09-10",
                "end": "2026-09-13",
                "all_day": True,
            },
            uid="event-all-day",
        )
        event = next(iter(Calendar.from_ical(document).walk("VEVENT")))
        self.assertEqual(event.decoded("dtstart").isoformat(), "2026-09-10")
        self.assertEqual(event.decoded("dtend").isoformat(), "2026-09-13")

    def test_build_event_rejects_unknown_fields(self):
        with self.assertRaisesRegex(ValueError, "unsupported"):
            hermes_calendar.build_event(
                {
                    "summary": "Unsafe",
                    "start": "2026-09-01T14:00:00-05:00",
                    "end": "2026-09-01T15:00:00-05:00",
                    "attendee": "mailto:person@example.com",
                }
            )


class PatchEventTests(unittest.TestCase):
    def test_patch_event_preserves_metadata_and_changes_requested_fields(self):
        original = hermes_calendar.build_event(
            {
                "summary": "Therapy",
                "start": "2026-09-01T14:00:00",
                "end": "2026-09-01T15:00:00",
                "timezone": "America/Chicago",
                "repeat": "weekly",
                "count": 6,
                "alarm_minutes": [30],
            },
            uid="event-test-2",
            now=datetime(2026, 8, 24, 12, 0, tzinfo=ZoneInfo("UTC")),
        )
        original_calendar = Calendar.from_ical(original)
        original_event = next(iter(original_calendar.walk("VEVENT")))
        original_event.add("attendee", "mailto:person@example.com", parameters={"CN": "Person"})

        updated = hermes_calendar.patch_event(
            original_calendar.to_ical(),
            "event-test-2",
            {
                "summary": "Therapy appointment",
                "start": "2026-09-01T15:00:00",
                "end": "2026-09-01T16:00:00",
                "timezone": "America/Chicago",
            },
            now=datetime(2026, 8, 24, 13, 0, tzinfo=ZoneInfo("UTC")),
        )

        calendar = Calendar.from_ical(updated)
        event = next(iter(calendar.walk("VEVENT")))
        self.assertEqual(str(event["uid"]), "event-test-2")
        self.assertEqual(str(event["summary"]), "Therapy appointment")
        self.assertEqual(event.decoded("dtstart").hour, 15)
        self.assertEqual(event["rrule"]["FREQ"], ["WEEKLY"])
        self.assertEqual(len(event.subcomponents), 1)
        self.assertEqual(str(event["attendee"]), "mailto:person@example.com")
        self.assertEqual(int(event["sequence"]), 1)

    def test_patch_event_preserves_uid_when_resource_id_differs(self):
        original = hermes_calendar.build_event(
            {
                "summary": "Therapy",
                "start": "2026-09-01T14:00:00-05:00",
                "end": "2026-09-01T15:00:00-05:00",
            },
            uid="event-test-3",
        )
        updated = hermes_calendar.patch_event(
            original, "caldav-resource-3", {"summary": "Changed"}
        )
        calendar = Calendar.from_ical(updated)
        event = next(iter(calendar.walk("VEVENT")))
        self.assertEqual(str(event["uid"]), "event-test-3")
        self.assertEqual(str(event["summary"]), "Changed")


class CalendulaBoundaryTests(unittest.TestCase):
    def test_create_sends_event_data_on_stdin_with_fixed_argv(self):
        calls = []

        def runner(argv, **kwargs):
            calls.append((argv, kwargs))
            if "item" in argv and "list" in argv:
                payload = {
                    "items": [
                        {
                            "id": "caldav-resource-1",
                            "etag": "etag-created",
                            "contents": "BEGIN:VCALENDAR\r\nEND:VCALENDAR\r\n",
                        }
                    ]
                }
                return type(
                    "Result",
                    (),
                    {"returncode": 0, "stdout": __import__("json").dumps(payload).encode()},
                )()
            return type(
                "Result",
                (),
                {"returncode": 0, "stdout": b'{"message":"Event `caldav-resource-1` successfully created"}'},
            )()

        client = hermes_calendar.CalendulaClient(
            binary="/nix/store/calendula/bin/calendula",
            config="/run/hermes-broker/calendula.toml",
            allowed_calendars={"personal"},
            runner=runner,
        )
        result = client.create_event(
            "personal",
            {
                "summary": "--log-level trace; private text",
                "start": "2026-09-01T14:00:00-05:00",
                "end": "2026-09-01T15:00:00-05:00",
            },
        )

        self.assertEqual(
            result,
            {
                "message": "Event `caldav-resource-1` successfully created",
                "id": "caldav-resource-1",
                "current": {
                    "id": "caldav-resource-1",
                    "etag": "etag-created",
                    "contents": "BEGIN:VCALENDAR\r\nEND:VCALENDAR\r\n",
                },
            },
        )
        argv, options = calls[0]
        self.assertEqual(
            argv,
            [
                "/nix/store/calendula/bin/calendula",
                "--config",
                "/run/hermes-broker/calendula.toml",
                "--account",
                "etesync",
                "--backend",
                "caldav",
                "--json",
                "event",
                "create",
                "--calendar",
                "personal",
                "-",
            ],
        )
        self.assertNotIn("private text", " ".join(argv))
        self.assertIn(b"private text", options["input"])
        self.assertFalse(options["shell"])

    def test_update_uses_current_etag_and_preserves_uid(self):
        original = hermes_calendar.build_event(
            {
                "summary": "Old",
                "start": "2026-09-01T14:00:00-05:00",
                "end": "2026-09-01T15:00:00-05:00",
            },
            uid="event-test-4",
        ).decode()
        calls = []

        def runner(argv, **kwargs):
            calls.append((argv, kwargs))
            if "item" in argv and "list" in argv:
                payload = {"items": [{"id": "caldav-resource-4", "etag": "etag-1", "contents": original}]}
            else:
                payload = {"message": "updated"}
            return type(
                "Result",
                (),
                {"returncode": 0, "stdout": __import__("json").dumps(payload).encode()},
            )()

        client = hermes_calendar.CalendulaClient(
            "calendula", "/run/config", {"personal"}, runner=runner
        )
        result = client.update_event("personal", "caldav-resource-4", {"summary": "New"})

        self.assertEqual(result, {"message": "updated"})
        update_argv, update_options = calls[-1]
        self.assertEqual(
            update_argv[-7:],
            ["update", "--calendar", "personal", "caldav-resource-4", "--if-match", "etag-1", "-"],
        )
        updated = Calendar.from_ical(update_options["input"])
        event = next(iter(updated.walk("VEVENT")))
        self.assertEqual(str(event["uid"]), "event-test-4")
        self.assertEqual(str(event["summary"]), "New")

    def test_calendar_identifier_rejects_control_characters(self):
        client = hermes_calendar.CalendulaClient(
            "calendula", "/run/config", {"personal"}
        )
        with self.assertRaisesRegex(ValueError, "calendar"):
            client.create_event(
                "personal\nother",
                {
                    "summary": "Test",
                    "start": "2026-09-01T14:00:00-05:00",
                    "end": "2026-09-01T15:00:00-05:00",
                },
            )

    def test_calendar_discovery_fails_closed_without_allowlist(self):
        def runner(argv, **kwargs):
            self.fail("Calendula must not run before the allow-list exists")

        client = hermes_calendar.CalendulaClient(
            "calendula", "/run/config", set(), runner=runner
        )
        with self.assertRaisesRegex(
            hermes_calendar.CalendulaError, "allow-list is not configured"
        ):
            client.list_calendars()

    def test_calendula_output_size_is_bounded_before_json_decode(self):
        def runner(argv, **kwargs):
            return type(
                "Result",
                (),
                {"returncode": 0, "stdout": b'{"calendars": []}'},
            )()

        client = hermes_calendar.CalendulaClient(
            "calendula", "/run/config", {"personal"}, runner=runner
        )
        with mock.patch.object(hermes_calendar, "MAX_CALENDULA_OUTPUT_BYTES", 8):
            with self.assertRaisesRegex(hermes_calendar.CalendulaError, "too large"):
                client.list_calendars()

    def test_item_contents_are_bounded_for_reads_and_writes(self):
        def runner(argv, **kwargs):
            payload = {
                "items": [
                    {
                        "id": "large",
                        "etag": "etag-large",
                        "contents": "BEGIN:VCALENDAR\r\nEND:VCALENDAR\r\n",
                    }
                ]
            }
            return type(
                "Result",
                (),
                {"returncode": 0, "stdout": json.dumps(payload).encode()},
            )()

        client = hermes_calendar.CalendulaClient(
            "calendula", "/run/config", {"personal"}, runner=runner
        )
        with mock.patch.object(hermes_calendar, "MAX_ICALENDAR_BYTES", 8):
            with self.assertRaisesRegex(hermes_calendar.CalendulaError, "too large"):
                client.read_event("personal", "large")

    def test_calendar_allowlist_rejects_other_calendars_and_option_ids(self):
        client = hermes_calendar.CalendulaClient(
            "calendula", "/run/config", {"personal"}
        )
        with self.assertRaisesRegex(ValueError, "allowed"):
            client.list_events("work", "2026-09-01", "2026-09-02")
        with self.assertRaisesRegex(ValueError, "identifier"):
            client.read_event("personal", "--account")

    def test_list_rejects_ranges_longer_than_one_year(self):
        client = hermes_calendar.CalendulaClient(
            "calendula", "/run/config", {"personal"}
        )
        with self.assertRaisesRegex(ValueError, "366 days"):
            client.list_events("personal", "2026-01-01", "2027-01-03")

    def test_search_filters_the_bounded_event_list(self):
        def runner(argv, **kwargs):
            payload = {
                "events": [
                    {"id": "one", "summary": "Dentist appointment"},
                    {"id": "two", "summary": "Team meeting"},
                ]
            }
            return type(
                "Result",
                (),
                {"returncode": 0, "stdout": __import__("json").dumps(payload).encode()},
            )()

        client = hermes_calendar.CalendulaClient(
            "calendula", "/run/config", {"personal"}, runner=runner
        )
        result = client.search_events(
            "personal", "2026-09-01", "2026-09-30", "dentist"
        )
        self.assertEqual([event["id"] for event in result["events"]], ["one"])

    def test_conflicts_reject_high_frequency_recurrence_before_expansion(self):
        rules = (
            "RRULE:FREQ=SECONDLY\r\n",
            "RRULE:FREQ=DAILY\r\nEXRULE:FREQ=SECONDLY\r\n",
        )
        for rules_text in rules:
            with self.subTest(rules=rules_text):
                document = (
                    "BEGIN:VCALENDAR\r\n"
                    "VERSION:2.0\r\n"
                    "BEGIN:VEVENT\r\n"
                    "UID:fast\r\n"
                    "DTSTART;TZID=America/Chicago:20260901T090000\r\n"
                    "DTEND;TZID=America/Chicago:20260901T090001\r\n"
                    + rules_text
                    + "SUMMARY:Too fast\r\n"
                    "END:VEVENT\r\n"
                    "END:VCALENDAR\r\n"
                )

                def runner(argv, **kwargs):
                    payload = {
                        "items": [
                            {
                                "id": "fast-resource",
                                "etag": "etag-fast",
                                "contents": document,
                            }
                        ]
                    }
                    return type(
                        "Result",
                        (),
                        {"returncode": 0, "stdout": json.dumps(payload).encode()},
                    )()

                client = hermes_calendar.CalendulaClient(
                    "calendula", "/run/config", {"personal"}, runner=runner
                )
                with self.assertRaisesRegex(
                    hermes_calendar.CalendulaError, "too dense"
                ):
                    client.conflicts(
                        "personal",
                        "2026-09-01T09:00:00",
                        "2026-09-01T10:00:00",
                        "America/Chicago",
                    )

    def test_conflicts_expand_duration_events(self):
        event = Event()
        event.add("dtstart", datetime(2026, 9, 1, 9, 0, tzinfo=ZoneInfo("America/Chicago")))
        event.add("duration", timedelta(hours=2))
        start, end = hermes_calendar.CalendulaClient._event_bounds(
            event, ZoneInfo("America/Chicago")
        )
        self.assertEqual(timedelta(hours=2), end - start)

    def test_conflicts_expands_a_recurring_event(self):
        document = hermes_calendar.build_event(
            {
                "summary": "Weekly appointment",
                "start": "2026-09-01T14:00:00",
                "end": "2026-09-01T15:00:00",
                "timezone": "America/Chicago",
                "repeat": "weekly",
                "count": 3,
            },
            uid="recurring-event",
        ).decode()

        def runner(argv, **kwargs):
            payload = {
                "items": [
                    {
                        "id": "resource-recurring",
                        "etag": "etag-recurring",
                        "contents": document,
                    }
                ]
            }
            return type(
                "Result",
                (),
                {"returncode": 0, "stdout": __import__("json").dumps(payload).encode()},
            )()

        client = hermes_calendar.CalendulaClient(
            "calendula", "/run/config", {"personal"}, runner=runner
        )
        result = client.conflicts(
            "personal",
            "2026-09-08T14:30:00",
            "2026-09-08T14:45:00",
            "America/Chicago",
        )
        self.assertEqual(len(result["conflicts"]), 1)
        self.assertEqual(result["conflicts"][0]["id"], "resource-recurring")

    def test_delete_checks_that_the_resource_is_absent(self):
        calls = []

        def runner(argv, **kwargs):
            calls.append(argv)
            item_calls = sum(1 for call in calls if "item" in call and "list" in call)
            if "item" in argv and "list" in argv:
                items = (
                    [{"id": "resource-delete", "etag": "etag-delete", "contents": "data"}]
                    if item_calls == 1
                    else []
                )
                payload = {"items": items}
            else:
                payload = {"message": "deleted"}
            return type(
                "Result",
                (),
                {"returncode": 0, "stdout": __import__("json").dumps(payload).encode()},
            )()

        client = hermes_calendar.CalendulaClient(
            "calendula", "/run/config", {"personal"}, runner=runner
        )
        result = client.delete_event("personal", "resource-delete")
        self.assertEqual(result, {"message": "deleted", "verified_absent": True})


if __name__ == "__main__":
    unittest.main()
