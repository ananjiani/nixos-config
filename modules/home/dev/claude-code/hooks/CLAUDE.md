# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This is a Claude Code hooks system written in Go that provides security, analytics, and notification features. The hooks intercept and monitor Claude Code tool usage to prevent dangerous operations and provide useful notifications.

## Build and Development Commands

### Build Commands
- **Build all hooks**: `nix build`
- **Build individual hooks**:
  ```bash
  go build -o pre_tool_use ./src/pre_tool_use.go
  go build -o post_tool_use ./src/post_tool_use.go
  go build -o notification ./src/notification.go
  go build -o stop ./src/stop.go
  ```

### Development Commands
- **Enter development shell**: `nix develop` (provides Go tooling)
- **Format code**: `gofumpt -w .`
- **Run linter**: `golangci-lint run`

## Architecture

### Hook System
The system consists of four hooks that integrate with Claude Code:

1. **pre_tool_use**: Validates commands before execution
   - Blocks dangerous `rm` commands (recursive deletion of system/home directories)
   - Prevents fork bombs, direct device writes, filesystem formatting
   - Blocks access to sensitive files like `.env` and `credentials.json`

2. **post_tool_use**: Logs tool usage for analytics
   - Tracks command patterns and usage statistics
   - Writes to `~/.claude/hooks/logs/post_tool_use.json`

3. **notification**: Sends desktop notifications
   - Integrates with Hyprland window manager and Zellij terminal
   - Notifies when terminal is not in focus

4. **stop**: Handles session cleanup
   - Shows session summary
   - Checks for incomplete todos
   - Displays git status reminders

### Shared Components
- **shared/types.go**: Common structures (`HookInput`, `LogEntry`) and helper functions
- All hooks log to JSON files in `~/.claude/hooks/logs/`
- Hooks exit silently on errors to avoid disrupting Claude's operation

### Build System
- Uses Nix Flakes for reproducible builds
- No external Go dependencies (pure Go implementation)
- Development shell includes golangci-lint and gofumpt for code quality

## Key Design Principles
- **Security-first**: All dangerous operations are blocked proactively
- **Non-intrusive**: Errors don't interrupt Claude's workflow
- **Privacy-conscious**: Analytics track patterns without storing sensitive data
- **Platform-specific**: Optimized for Linux with Hyprland/Zellij integration
