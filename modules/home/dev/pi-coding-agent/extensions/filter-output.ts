/**
 * Filter Output Extension
 *
 * Redacts sensitive values (API keys, tokens, passwords, age keys,
 * private keys) from bash tool results before the LLM sees them.
 *
 * Operates on the `tool_result` event, mutating the content in-place.
 * Does NOT prevent the command from running — only sanitises the output.
 */

import type { ExtensionAPI } from "@mariozechner/pi-coding-agent";

export default function (pi: ExtensionAPI) {
  // Regex patterns that match common secret formats.
  // Each entry has a pattern and a replacement string.
  const redactions: Array<{ pattern: RegExp; replacement: string }> = [
    // Generic "key = value" or "key: value" patterns
    {
      pattern: /([A-Za-z_]*(?:api[_-]?key|secret|token|password|auth)[A-Za-z_]*)\s*[:=]\s*["']?[A-Za-z0-9_\-./+=]{16,}["']?/gi,
      replacement: "$1: [REDACTED]",
    },
    // Bearer token headers
    {
      pattern: /(Authorization:\s*Bearer\s+)[A-Za-z0-9_\-./+=]+/gi,
      replacement: "$1[REDACTED]",
    },
    // Anthropic / OpenAI / Kimi keys
    {
      pattern: /\b(sk-ant-|sk-proj-|sk-kimi-|sk-)[A-Za-z0-9_\-./+=]{20,}\b/g,
      replacement: "[REDACTED_API_KEY]",
    },
    // Age keys
    {
      pattern: /AGE-SECRET-KEY-1[A-Z0-9]{58}/g,
      replacement: "[REDACTED_AGE_KEY]",
    },
    // SSH private key blocks
    {
      pattern: /-----BEGIN OPENSSH PRIVATE KEY-----[\s\S]*?-----END OPENSSH PRIVATE KEY-----/g,
      replacement: "[REDACTED_SSH_KEY]",
    },
    {
      pattern: /-----BEGIN (RSA |EC |DSA )?PRIVATE KEY-----[\s\S]*?-----END (RSA |EC |DSA )?PRIVATE KEY-----/g,
      replacement: "[REDACTED_PRIVATE_KEY]",
    },
    // Tailscale auth keys
    {
      pattern: /\btskey-[a-z]+-[A-Za-z0-9]+\b/g,
      replacement: "[REDACTED_TAILSCALE_KEY]",
    },
  ];

  pi.on("tool_result", async (event) => {
    // Redact secrets from both bash output and file reads.
    // Without this, `read` on /run/secrets/* or .env files
    // would leak plaintext to the LLM.
    if (event.toolName !== "bash" && event.toolName !== "read") return;

    // Redact each pattern across all text content
    for (const item of event.content) {
      if (item.type === "text" && typeof item.text === "string") {
        for (const { pattern, replacement } of redactions) {
          item.text = item.text.replace(pattern, replacement);
        }
      }
    }

    // Also redact in details.stdout if present
    if (
      event.details &&
typeof event.details === "object" &&
      "stdout" in event.details &&
      typeof event.details.stdout === "string"
    ) {
      for (const { pattern, replacement } of redactions) {
        event.details.stdout = event.details.stdout.replace(pattern, replacement);
      }
    }
  });
}
