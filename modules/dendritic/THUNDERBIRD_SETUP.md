# Thunderbird + Proton Mail Bridge Setup Guide

## Step 1: Set Up Proton Mail Bridge

### 1.1 Stop the systemd service (if running)
```bash
systemctl --user stop protonmail-bridge
```

### 1.2 Run Bridge interactively
```bash
protonmail-bridge
```

You should see:
```
>>> Proton Mail Bridge detected pass as the password manager
```

### 1.3 Log in to your Proton account
In the bridge interface, type:
```
login
```

Follow the prompts:
- Enter your Proton Mail email address
- Enter your password
- Complete 2FA if enabled
- Wait for the account to sync

### 1.4 Get your Bridge credentials
After login, type:
```
info
```

This will show you:
```
Configuration for your-email@proton.me:
IMAP Settings:
  Address:   127.0.0.1
  IMAP port: 1143
  Username:  your-email@proton.me
  Password:  <randomly-generated-password>
  Security:  STARTTLS

SMTP Settings:
  Address:   127.0.0.1
  SMTP port: 1025
  Username:  your-email@proton.me
  Password:  <randomly-generated-password>
  Security:  STARTTLS
```

**IMPORTANT:** Copy the password shown! This is NOT your Proton Mail password - it's a Bridge-specific password.

### 1.5 Exit the bridge
Type:
```
exit
```

### 1.6 Start the systemd service
```bash
systemctl --user start protonmail-bridge
```

The bridge will now run automatically in the background!

---

## Step 2: Add Password to SOPS (Declarative Setup - Recommended)

With this dotfiles setup, Thunderbird is configured **declaratively** via Nix and Home Manager. The account is already defined in `hosts/desktop/home.nix`, you just need to add the password to SOPS.

### 2.1 Get Bridge Password

Run Bridge interactively to get the password:
```bash
systemctl --user stop protonmail-bridge
protonmail-bridge
```

In the Bridge interface:
```bash
info
```

Copy the **Password** field (same for both IMAP and SMTP).

Exit Bridge:
```bash
exit
systemctl --user start protonmail-bridge
```

### 2.2 Add Password to SOPS Secrets

Edit your secrets file:
```bash
cd ~/.dotfiles
sops secrets/secrets.yaml
```

Add this line (replace with your actual password):
```yaml
proton_bridge_password: "YOUR_BRIDGE_PASSWORD_HERE"
```

Save and exit (Ctrl+O, Enter, Ctrl+X). SOPS will automatically encrypt it.

### 2.3 Apply Configuration

```bash
nh home switch
```

Home Manager will automatically configure Thunderbird with the password from SOPS!

### 2.4 Accept the Self-Signed Certificate

When Thunderbird starts for the first time, it will warn about a self-signed certificate. This is normal! The Bridge uses localhost, so this is secure.

1. Click **Confirm Security Exception**
2. Check **Permanently store this exception**
3. Click **Confirm Security Exception**

You'll need to do this for both IMAP and SMTP.

### 2.5 Test Your Setup

1. Try sending a test email to yourself
2. Check if you can receive emails
3. Verify folders are syncing (Inbox, Sent, Drafts, etc.)

**That's it!** Thunderbird will now use the password from SOPS and won't ask for it anymore.

---

## Alternative: Manual Thunderbird Configuration (Non-Declarative)

If you prefer to configure Thunderbird manually instead of using the declarative setup:

### 2.1 Launch Thunderbird
```bash
thunderbird
```

### 2.2 Add Account

**Option A: Manual Configuration**

1. Click **☰ Menu** → **Account Settings** → **Account Actions** → **Add Mail Account**
2. Fill in:
   - Your Name: `Your Name`
   - Email Address: `your-email@proton.me`
   - Password: `<the Bridge password from Step 1.4>`
3. Click **Continue**
4. Click **Manual config** (important!)

**Configure Incoming Server (IMAP):**
- Protocol: `IMAP`
- Hostname: `127.0.0.1`
- Port: `1143`
- Connection security: `STARTTLS`
- Authentication method: `Normal password`
- Username: `your-email@proton.me`

**Configure Outgoing Server (SMTP):**
- Hostname: `127.0.0.1`
- Port: `1025`
- Connection security: `STARTTLS`
- Authentication method: `Normal password`
- Username: `your-email@proton.me`

5. Click **Re-test** to verify settings
6. Click **Done**

### 2.3 Accept the Self-Signed Certificate

Thunderbird will warn about a self-signed certificate. This is normal! The Bridge uses localhost, so this is secure.

1. Click **Confirm Security Exception**
2. Check **Permanently store this exception**
3. Click **Confirm Security Exception**

You'll need to do this for both IMAP and SMTP.

### 2.4 Test Your Setup

1. Try sending a test email to yourself
2. Check if you can receive emails
3. Verify folders are syncing (Inbox, Sent, Drafts, etc.)

---

## Updating the Password (If It Changes)

If you need to update the ProtonMail Bridge password (e.g., after logging out/in to Bridge):

### Method 1: Update SOPS Secret (Declarative)

```bash
# Get new password from Bridge
systemctl --user stop protonmail-bridge
protonmail-bridge
# Type: info
# Copy the new password
# Type: exit

# Update SOPS
cd ~/.dotfiles
sops secrets/secrets.yaml
# Update the proton_bridge_password value
# Save and exit

# Apply changes
nh home switch

# Restart Bridge
systemctl --user start protonmail-bridge
```

### Method 2: Update Thunderbird Password Manager (Manual)

1. Open Thunderbird
2. **☰ Menu** → **Settings** → **Privacy & Security** → **Saved Passwords**
3. Find `127.0.0.1` entries (IMAP and SMTP)
4. Click **Show Passwords**
5. Right-click each entry → **Edit Password**
6. Paste the new Bridge password
7. Click OK

---

## Troubleshooting

### Thunderbird keeps asking for password
**Problem:** Password prompts keep appearing

**Solution:**
This means the password in SOPS doesn't match the current Bridge password, or Thunderbird hasn't loaded it yet.

```bash
# Check SOPS secret exists
ls -la /run/user/1000/secrets/proton_bridge_password

# View the secret value (to verify it's correct)
# Note: This will show your password in plain text!
cat /run/user/1000/secrets/proton_bridge_password

# Check Bridge logs for authentication errors
journalctl --user -u protonmail-bridge -f

# If password is wrong, update it in SOPS (see "Updating the Password" above)
```

### Bridge isn't detecting pass
**Problem:** Bridge shows "no keychain" error

**Solution:**
```bash
# Check pass is initialized
pass ls

# Should show your password store directory
# If empty or errors, reinitialize:
gpg --list-secret-keys  # Get your GPG key ID
pass init YOUR_GPG_KEY_ID
```

### Can't connect to Bridge in Thunderbird
**Problem:** Connection timeout or refused

**Solution:**
```bash
# Check bridge is running
systemctl --user status protonmail-bridge

# Check bridge is listening on ports
ss -tlnp | grep 1143
ss -tlnp | grep 1025

# Restart bridge if needed
systemctl --user restart protonmail-bridge
```

### Certificate warnings keep appearing
**Problem:** Thunderbird keeps asking about certificates

**Solution:** Make sure you checked "Permanently store this exception" when accepting the certificate.

### Emails aren't syncing
**Problem:** Bridge shows errors or emails don't appear

**Solution:**
```bash
# Check bridge logs
journalctl --user -u protonmail-bridge -f

# Try restarting bridge
systemctl --user restart protonmail-bridge
```

---

## Advanced: Multiple Proton Accounts

You can add multiple Proton Mail accounts to the Bridge:

```bash
protonmail-bridge
# In bridge interface:
login
# Enter second account credentials
```

Each account will have different IMAP/SMTP ports. Use `info` to see all accounts.

---

## Security & Privacy Hardening

### Automatic Hardening with thunderbird-user.js

This module automatically fetches and applies ALL ~260 hardening settings from the [thunderbird-user.js](https://github.com/HorlogeSkynet/thunderbird-user.js) project.

#### Enable Full Hardening

In your `home.nix`:

```nix
email.thunderbird = {
  enable = true;

  # Apply ALL hardened settings from thunderbird-user.js
  useHardenedUserJs = true;

  # Override specific settings as needed
  userPrefs = {
    # ProtonMail Bridge requires this
    "security.cert_pinning.enforcement_level" = 1;
  };
};
```

**What this does:**
- ✅ Automatically fetches latest thunderbird-user.js from GitHub (pinned in flake.lock)
- ✅ Parses all ~260 privacy and security settings
- ✅ Applies them to your Thunderbird profile
- ✅ Your `userPrefs` override any hardened settings

**To update hardening settings:**
```bash
nix flake update thunderbird-user-js
nh home switch
```

### Manual/Selective Hardening

If you don't want ALL settings, you can manually add specific ones via `userPrefs`:

```nix
email = {
  enable = true;
  thunderbird = {
    enable = true;
    userPrefs = {
      # Required for ProtonMail Bridge (relaxes cert pinning for local MITM)
      "security.cert_pinning.enforcement_level" = 1;

      # Privacy hardening examples:
      "mailnews.message_display.disable_remote_image" = true;  # Block remote content
      "privacy.donottrackheader.enabled" = true;               # Send Do Not Track header
      "mailnews.headers.showOrganization" = false;             # Hide organization header
      "mailnews.headers.showUserAgent" = false;                # Hide user agent
      "mail.collect_email_address_outgoing" = false;           # Don't collect addresses
    };
  };
};
```

**Common Hardening Settings:**

| Setting | Description | Trade-off |
|---------|-------------|-----------|
| `mailnews.message_display.disable_remote_image = true` | Block remote content in emails | May break HTML emails |
| `mailnews.start_page.enabled = false` | Disable start page | No start page tips |
| `javascript.enabled = false` | Disable JavaScript | Breaks OAuth2 login |
| `network.cookie.cookieBehavior = 1` | Block 3rd party cookies | May affect web features |

**⚠️ Important Notes:**
- Don't disable JavaScript if you need OAuth2 (Gmail, Office 365)
- For ProtonMail Bridge, you MUST set `security.cert_pinning.enforcement_level = 1`
- Test settings incrementally - some may break functionality

**Full List:** See [thunderbird-user.js wiki](https://github.com/HorlogeSkynet/thunderbird-user.js/wiki) for all available settings.

---

## System Tray Integration (Linux)

### Birdtray - Minimize to Tray

By default, Thunderbird on Linux doesn't support system tray functionality. When you close the window, Thunderbird exits completely.

**Birdtray** adds proper system tray support:
- ✅ System tray icon with unread email count
- ✅ Minimize to tray instead of closing
- ✅ New email notifications
- ✅ Click tray icon to restore Thunderbird window
- ✅ Works with Waybar, i3bar, and other tray implementations

#### Enable Birdtray

In your `home.nix`:

```nix
email = {
  enable = true;
  thunderbird = {
    enable = true;

    # Enable system tray integration
    birdtray.enable = true;

    # This automatically enables autostart since Birdtray requires Thunderbird to run
  };
};
```

#### How It Works

1. **Thunderbird** starts automatically via systemd on login
2. **Birdtray** starts after Thunderbird and adds tray icon
3. Closing Thunderbird window → minimizes to tray (doesn't exit)
4. Click tray icon → restores Thunderbird window
5. Tray icon shows unread email count

#### First Run Configuration

On first run, Birdtray will ask which Thunderbird profile to monitor:
1. Birdtray settings window will appear
2. Select your Thunderbird profile (usually "default")
3. Configure notification preferences if desired
4. Close settings - Birdtray will remember your choices

#### Troubleshooting

**Birdtray not showing in tray:**
```bash
# Check if Birdtray is running
systemctl --user status birdtray

# Check Birdtray logs
journalctl --user -u birdtray -f

# Restart Birdtray
systemctl --user restart birdtray
```

**Thunderbird still exits when closing window:**
- Make sure Birdtray is running before closing Thunderbird
- Check that your window manager/desktop environment supports system tray
- For Wayland: Ensure your bar (Waybar, etc.) has tray configured

**To disable Birdtray:**
```nix
email.thunderbird.birdtray.enable = false;
```

---

## Security Notes

✅ **What's encrypted:**
- All traffic between Bridge and Proton servers (HTTPS)
- Emails at rest on Proton servers (E2EE)
- Bridge credentials in pass (GPG-encrypted)

⚠️ **What's NOT encrypted:**
- Traffic between Thunderbird and Bridge (localhost only - safe)
- Thunderbird's local email cache

💡 **Tip:** Use full disk encryption to protect Thunderbird's local cache!

---

## Useful Commands

```bash
# Check bridge status
systemctl --user status protonmail-bridge

# View bridge logs
journalctl --user -u protonmail-bridge -f

# Restart bridge
systemctl --user restart protonmail-bridge

# Stop bridge
systemctl --user stop protonmail-bridge

# Start bridge
systemctl --user start protonmail-bridge

# Run bridge interactively (for debugging)
systemctl --user stop protonmail-bridge
protonmail-bridge

# List passwords in pass
pass ls

# Show a specific password
pass show protonmail-bridge/your-email@proton.me
```

---

## Configuration Files

- **Bridge config:** `~/.config/protonmail/bridge-v3/`
- **Pass store:** `~/.password-store/`
- **Thunderbird profile:** `~/.thunderbird/`

---

## Need Help?

- Bridge documentation: https://proton.me/mail/bridge
- Thunderbird help: https://support.mozilla.org/en-US/products/thunderbird
- Check logs: `journalctl --user -u protonmail-bridge -f`
