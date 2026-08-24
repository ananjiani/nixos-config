# EteSync calendar bootstrap on Aragorn

This integration starts in the `declared` state. Do not mark it authenticated or operational until the checks below pass.

## 1. Create placeholder OpenBao fields

Before the first deployment, create `secret/nixos/etesync-dav` in the OpenBao UI. Add these fields:

- `username`: `[NOT_CONFIGURED]`
- `dav-password`: `[NOT_CONFIGURED]`
- `calendar-ids`: `[NOT_CONFIGURED]`
- `default-calendar`: `[NOT_CONFIGURED]`

The placeholders let Vault Agent render every declared file. Calendar operations fail closed until real values replace them.

Do not put EteSync or DAV credentials in Git, chat, shell command arguments, or terminal logs.

## 2. Deploy the NixOS configuration

Deploy the reviewed configuration through the normal Aragorn GitOps path. The deployment starts EteSync-DAV on `127.0.0.2:37358` and persists its state in `/var/lib/etesync-dav`.

The dedicated loopback address supports an enforced service boundary. `hermes-agent.service` denies `127.0.0.2`, while the broker can reach it.

Check the live boundary:

```bash
systemctl status etesync-dav hermes-broker --no-pager
ss -ltnp 'sport = :37358'
```

The listening address must be `127.0.0.2:37358`. Do not continue if the bridge listens on another address.

## 3. Add the EteSync account through a tunnel

The normal service disables the management UI. Enable it only for this bootstrap:

```bash
sudo systemctl edit --runtime etesync-dav
```

Add this exact drop-in in the editor:

```ini
[Service]
Environment=ETESYNC_NO_WEBUI=
```

Save the file. Restart the bridge:

```bash
sudo systemctl restart etesync-dav
```

From a trusted workstation, start this tunnel:

```bash
ssh -L 37358:127.0.0.2:37358 aragorn
```

Open this local page:

```text
http://localhost:37358/.web/login/
```

Add the EteSync account in the management UI. Enter account and encryption credentials only in that local page.

The UI generates a DAV password. Copy the EteSync username and generated DAV password directly into the OpenBao UI. Replace the `username` and `dav-password` placeholders. Do not paste either value into chat.

Remove the temporary web UI override immediately:

```bash
sudo rm /run/systemd/system/etesync-dav.service.d/override.conf
sudo systemctl daemon-reload
sudo systemctl restart etesync-dav
```

Close the SSH tunnel. The normal service now serves CalDAV without the management UI.

Wait for Vault Agent to render the changed files. Do not read the secret files to check them. Check only their metadata:

```bash
stat /run/secrets/etesync_dav_password \
  /run/secrets/etesync_dav_username_config \
  /run/secrets/etesync_dav_calendars \
  /run/secrets/etesync_dav_default_calendar
```

## 4. Select the allowed calendars

Run operator-only discovery on Aragorn:

```bash
sudo -u hermes-broker /run/current-system/sw/bin/hermes-calendar-admin calendars
```

Do not use `hermes-calendar calendars` before the allow-list exists. The broker fails closed while `calendar-ids` remains `[NOT_CONFIGURED]`.

Copy only the approved calendar IDs into the OpenBao `calendar-ids` field. Use commas or one ID per line. Put one approved ID in `default-calendar`.

After Vault Agent refreshes both fields, `hermes-calendar calendars` returns only allowed calendars. Commands that omit `--calendar` use the configured default. Every operation rejects other calendar IDs.

## 5. Check reads before writes

Use a bounded range that contains a known event:

```bash
hermes-calendar list --calendar <id> --from YYYY-MM-DD --to YYYY-MM-DD
hermes-calendar search --calendar <id> --from YYYY-MM-DD --to YYYY-MM-DD "known title"
```

Check one timed event, one all-day event, and one recurring event. Check a daylight-saving boundary when available.

## 6. Complete an approved disposable write test

Use a designated test calendar. Get explicit approval before this step.

1. Create one test event.
2. Read the returned resource ID.
3. Update its title or time.
4. Read it again.
5. Explicitly delete the test event.
6. Check that the resource is absent.

The wrapper reads creates and updates back from Calendula. It checks ETags before updates. It checks absence after deletes.

## Final access-state labels

- `declared`: the source and build exist.
- `installed`: the active Aragorn generation contains the integration.
- `running`: the loopback bridge and broker run.
- `authenticated`: allowed calendars appear through discovery.
- `operational`: known timed, all-day, recurring, and timezone-sensitive events pass read checks.
- `write-tested`: the approved disposable create, read, update, read, and delete flow passes.
