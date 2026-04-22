/**
 * Protected Paths Extension
 *
 * Blocks write and edit operations to sensitive paths.
 * Tailored for this NixOS/dotfiles repo: secrets, encrypted files,
 * terraform state, and vault-agent runtime secrets.
 */

import type { ExtensionAPI } from "@mariozechner/pi-coding-agent";

export default function (pi: ExtensionAPI) {
  // Paths that should never be written or edited by the agent.
  // Patterns are matched with .includes() against the target path.
  const protectedPaths: Array<{ pattern: string; reason: string }> = [
    { pattern: "secrets/", reason: "SOPS-encrypted secrets directory" },
    { pattern: ".sops.yaml", reason: "SOPS configuration" },
    { pattern: ".sops.yml", reason: "SOPS configuration" },
    { pattern: "terraform.tfstate", reason: "Terraform state" },
    { pattern: ".terraform/", reason: "Terraform working directory" },
    { pattern: "/run/secrets/", reason: "vault-agent runtime secrets" },
    { pattern: ".env", reason: "environment file" },
    { pattern: ".age-key", reason: "age encryption key" },
    { pattern: "id_ed25519", reason: "SSH private key" },
    { pattern: "id_rsa", reason: "SSH private key" },
  ];

  pi.on("tool_call", async (event, ctx) => {
    if (event.toolName !== "write" && event.toolName !== "edit") {
      return;
    }

    const path = event.input.path as string;
    const match = protectedPaths.find((p) => path.includes(p.pattern));

    if (match) {
      if (ctx.hasUI) {
        ctx.ui.notify(
          `Blocked ${event.toolName} to protected path: ${path} (${match.reason})`,
          "warning",
        );
      }
      return {
        block: true,
        reason: `Path "${path}" is protected (${match.reason}). Use manual editing.`,
      };
    }
  });
}
