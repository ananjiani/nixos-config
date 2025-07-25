#!/usr/bin/env bash

PID_FILE="/tmp/whisper_dictation.pid"

# Check if PID file exists and process is running
if [ -f "$PID_FILE" ]; then
    PID=$(cat "$PID_FILE")
    # Check if the process is actually running
    if kill -0 "$PID" 2>/dev/null; then
        # It's running, so stop it
        notify-send "Whisper Dictation" "⏹️ Recording stopped, transcribing..." -t 2000
        whisper-dictation end | wl-copy
        notify-send "Whisper Dictation" "Transcribed to Clipboard" -t 2000
    else
        # PID file exists but process not running, clean up and start new recording
        rm -f "$PID_FILE"
        notify-send "Whisper Dictation" "🎤 Recording started..." -t 2000
        whisper-dictation begin
    fi
else
    # Not running, so start it
    notify-send "Whisper Dictation" "🎤 Recording started..." -t 2000
    whisper-dictation begin
fi