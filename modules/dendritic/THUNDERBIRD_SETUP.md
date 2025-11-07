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

## Step 2: Configure Thunderbird

### 2.1 Launch Thunderbird
```bash
thunderbird
```

### 2.2 Add Account

**Option A: Manual Configuration** (Recommended)

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

## Troubleshooting

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
