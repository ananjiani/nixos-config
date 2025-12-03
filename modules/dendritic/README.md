# Dendritic Pattern & Dendrix Guide

## Table of Contents

- [What is the Dendritic Pattern?](#what-is-the-dendritic-pattern)
- [Core Concepts](#core-concepts)
- [How Dendrix Works with Flake-Parts](#how-dendrix-works-with-flake-parts)
- [The Problem: Multiple Aspects in One File](#the-problem-multiple-aspects-in-one-file)
- [Solutions](#solutions)
- [Best Practices](#best-practices)
- [Advanced Patterns](#advanced-patterns)
- [Real-World Examples](#real-world-examples)

---

## What is the Dendritic Pattern?

**Dendritic** is a configuration _pattern_ (not a library or framework) for organizing Nix configurations based on [flake-parts](https://flake.parts) modules. The name comes from the tree-like (dendritic) structure where configuration "branches" spread across different system types.

### The Core Idea

In Dendritic setups, configurations are **aspect-oriented** rather than **host-oriented**. Instead of organizing code by hostname or system type, you organize by **features** or **cross-cutting concerns**.

**Traditional Approach (Host-Centric):**
```
hosts/
  laptop/
    nixos.nix
    home.nix
  desktop/
    nixos.nix
    home.nix
```

**Dendritic Approach (Aspect-Centric):**
```
modules/
  ssh.nix          # SSH config for ALL classes (nixos, darwin, homeManager)
  vim.nix          # Vim config for ALL classes
  gaming.nix       # Gaming setup for ALL classes
  crypto.nix       # Crypto tools for ALL classes
```

Each file defines one **aspect** (feature) across multiple **classes** (configuration types).

---

## Core Concepts

### Classes

A **class** is a type of configuration system:
- `nixos` - NixOS system configuration
- `darwin` - macOS (nix-darwin) system configuration
- `homeManager` - User-level configuration (Home Manager)
- `nixvim` - Neovim configuration
- `terranix` - Terraform/IaC configuration
- `hjem` - Alternative Home Manager
- Any other flake-parts module type

### Aspects

An **aspect** is a cross-cutting concern or feature that can span multiple classes:
- `ssh` - SSH configuration (may need nixos service, darwin service, and homeManager config)
- `vim` - Editor setup (may need packages in homeManager, config in nixvim)
- `gaming` - Gaming setup (may need nixos drivers, homeManager configs, packages)
- `crypto` - Cryptocurrency tools (may need system packages and user configs)

### Flake-Parts Integration

Dendritic uses flake-parts' `flake.modules` option:

```nix
flake.modules.<class>.<aspect>
```

For example:
- `flake.modules.nixos.ssh` - NixOS SSH configuration
- `flake.modules.homeManager.ssh` - Home Manager SSH configuration
- `flake.modules.darwin.vim` - macOS vim setup

---

## How Dendrix Works with Flake-Parts

### Basic Structure

Every file in a Dendritic setup is a **flake-parts module**:

```nix
# modules/ssh.nix - A complete flake-parts module
{ inputs, ... }:
let
  sshPort = 2222;  # Shared values via let-bindings
in
{
  # NixOS configuration for this aspect
  flake.modules.nixos.ssh = {
    services.openssh.enable = true;
    services.openssh.port = sshPort;
  };

  # macOS configuration for this aspect
  flake.modules.darwin.ssh = {
    services.sshd.enable = true;
  };

  # Home Manager configuration for this aspect
  flake.modules.homeManager.ssh = {
    programs.ssh.enable = true;
    programs.ssh.matchBlocks = { /* ... */ };
  };

  # Per-system packages (optional)
  perSystem = { pkgs, ... }: {
    packages.ssh-tools = /* ... */;
  };
}
```

### Automatic Loading with import-tree

All dendritic files are loaded automatically using `import-tree`:

```nix
# flake.nix - Minimal flake.nix
{
  inputs = {
    flake-parts.url = "github:hercules-ci/flake-parts";
    import-tree.url = "github:vic/import-tree";
  };

  outputs = inputs:
    inputs.flake-parts.lib.mkFlake { inherit inputs; }
      (inputs.import-tree ./modules);
}
```

This loads **all** `.nix` files in `./modules/` recursively. Files with `/_` in their path are ignored.

---

## The Problem: Multiple Aspects in One File

### The Error

```
error: The option `flake.modules.homeManager' has conflicting definition values
```

This happens when you try to define the same `flake.modules.<class>` path multiple times in the same file.

### Why It Happens

In the `crypto.nix` example, we tried to define TWO aspects in ONE file:

```nix
{
  # First aspect: crypto
  flake.modules.homeManager.crypto = { /* ... */ };

  # Second aspect: email
  flake.modules.homeManager.email = { /* ... */ };  # ❌ This works!
}
```

**Wait, this actually WORKS!** The real problem occurs if you accidentally define:

```nix
{
  flake.modules.homeManager = {
    crypto = { /* ... */ };
  };

  flake.modules.homeManager = {  # ❌ ERROR: Defining flake.modules.homeManager twice!
    email = { /* ... */ };
  };
}
```

The Nix module system sees two separate definitions of `flake.modules.homeManager` and can't merge them.

---

## Solutions

### Solution 1: One File Per Aspect (Recommended)

**Best practice:** Create separate files for each aspect.

```nix
# modules/crypto.nix
{
  flake.modules.homeManager.crypto = { /* ... */ };
  flake.modules.nixos.crypto = { /* ... */ };
}
```

```nix
# modules/email.nix
{
  flake.modules.homeManager.email = { /* ... */ };
  flake.modules.nixos.email = { /* ... */ };
}
```

**Advantages:**
- Clear separation of concerns
- Easy to enable/disable features (rename with `_` prefix)
- Better git history and collaboration
- Follows the "feature-centric" philosophy

### Solution 2: Multiple Aspects in One File (Advanced)

If aspects are tightly related, you CAN define multiple aspects in one file:

```nix
# modules/communication.nix - Multiple related aspects
{
  # Email aspect
  flake.modules.homeManager.email = { /* ... */ };
  flake.modules.nixos.email = { /* ... */ };

  # Chat aspect
  flake.modules.homeManager.chat = { /* ... */ };
  flake.modules.nixos.chat = { /* ... */ };

  # Video conferencing aspect
  flake.modules.homeManager.video-calls = { /* ... */ };
}
```

**Important:** Each aspect must be defined as a separate attribute:
```nix
# ✅ CORRECT
flake.modules.homeManager.aspect1 = { };
flake.modules.homeManager.aspect2 = { };

# ❌ WRONG - This defines flake.modules.homeManager twice!
flake.modules.homeManager = { aspect1 = { }; };
flake.modules.homeManager = { aspect2 = { }; };
```

### Solution 3: Using flake-aspects (Advanced)

For complex setups with aspect dependencies, use [`flake-aspects`](https://github.com/vic/flake-aspects):

```nix
# modules/workspace.nix
{ inputs, ... }:
{
  imports = [ inputs.flake-aspects.flakeModule ];

  flake.aspects = { aspects, ... }: {
    # Define aspect with the transposed structure
    workspace = {
      nixos = { /* ... */ };
      darwin = { /* ... */ };
      homeManager = { /* ... */ };

      # This aspect includes other aspects
      includes = with aspects; [ vim ssh git ];
    };
  };
}
```

`flake-aspects` transposes `flake.aspects.<aspect>.<class>` to `flake.modules.<class>.<aspect>`, which some find more intuitive.

---

## Best Practices

### 1. Name Files After Aspects (Features)

```
✅ GOOD:
modules/
  scrolling-desktop.nix    # Feature: scrolling tiling desktop
  ai-integration.nix       # Feature: AI coding assistants
  macos-like-keys.nix      # Feature: macOS-like keybindings
  crypto-wallets.nix       # Feature: cryptocurrency wallets

❌ BAD:
modules/
  packages.nix             # Too generic
  system.nix               # Too generic
  laptop1.nix              # Host-centric, not aspect-centric
```

### 2. Use Let-Bindings for Shared Values

Don't use `specialArgs` - use let-bindings instead:

```nix
# modules/user-vic.nix
let
  userName = "vic";
  userEmail = "vic@example.com";
in
{
  flake.modules.nixos.${userName} = {
    users.users.${userName}.isNormalUser = true;
  };

  flake.modules.homeManager.${userName} = {
    home.username = userName;
    programs.git.userEmail = userEmail;
  };
}
```

### 3. Keep flake.nix Minimal

The `flake.nix` should only:
- Declare inputs
- Load modules via `import-tree`
- Define the flake entrypoint

All logic goes in `./modules/`.

### 4. Use Options for Configurability

Create options at the module level:

```nix
# modules/crypto.nix
{
  flake.modules.homeManager.crypto = { pkgs, lib, config, ... }: {
    options.crypto = {
      enable = lib.mkEnableOption "crypto applications";
      cakewallet.enable = lib.mkEnableOption "Cake Wallet";
    };

    config = lib.mkIf config.crypto.enable {
      home.packages = lib.optionals config.crypto.cakewallet.enable [ /* ... */ ];
    };
  };
}
```

### 5. Organize Related Aspects in Directories

```
modules/
  crypto/
    wallets.nix
    nodes.nix
    trading.nix
  dev/
    languages.nix
    editors.nix
    tools.nix
```

### 6. Use `_` Prefix to Disable Files

To temporarily disable a module, prefix it with `_`:

```
modules/
  crypto.nix      # Active
  _crypto.nix     # Ignored by import-tree
```

### 7. Create Incremental Features

Split large aspects into incremental pieces:

```
modules/
  vim/
    basic.nix      # Basic vim setup
    lsp.nix        # LSP configuration
    ai.nix         # AI completion
```

All contribute to the same `flake.modules.<class>.vim` aspect, but each file focuses on specific capabilities.

---

## Advanced Patterns

### Pattern 1: Cross-Aspect Dependencies with flake-aspects

```nix
# modules/dev-server.nix
{
  flake.aspects = { aspects, ... }: {
    dev-server = {
      # This aspect depends on other aspects
      includes = with aspects; [ docker git vim ssh ];

      nixos = {
        # Dev server specific NixOS config
      };

      homeManager = {
        # Dev environment for users
      };
    };
  };
}
```

### Pattern 2: Parameterized Aspects with Providers

```nix
# modules/user-management.nix
{
  flake.aspects = { aspects, ... }: {
    system = {
      nixos.system.stateVersion = "24.05";

      # Provider: Create user aspect with parameter
      _.user = userName: {
        nixos.users.users.${userName}.isNormalUser = true;
        homeManager.home.username = userName;
      };
    };

    # Use the parameterized provider
    my-host.includes = [
      aspects.system
      (aspects.system._.user "alice")
      (aspects.system._.user "bob")
    ];
  };
}
```

### Pattern 3: Conditional Class Configuration

```nix
# modules/scrolling-desktop.nix
let
  scrollSpeed = 0.8;
in
{
  # Linux: use niri
  flake.modules.nixos.scrolling-desktop = {
    programs.niri.enable = true;
    programs.niri.config.scrollSpeed = scrollSpeed;
  };

  # macOS: use paneru
  flake.modules.darwin.scrolling-desktop = {
    services.paneru.enable = true;
    services.paneru.scrollSpeed = scrollSpeed;
  };
}
```

### Pattern 4: Shared Package Definitions

```nix
# modules/custom-tools.nix
let
  myTool = pkgs: pkgs.stdenv.mkDerivation {
    pname = "my-tool";
    version = "1.0";
    # ...
  };
in
{
  # Use in Home Manager
  flake.modules.homeManager.custom-tools = { pkgs, ... }: {
    home.packages = [ (myTool pkgs) ];
  };

  # Also expose as flake package
  perSystem = { pkgs, ... }: {
    packages.my-tool = myTool pkgs;
  };
}
```

---

## Real-World Examples

### Example 1: SSH Configuration Across All Systems

```nix
# modules/ssh.nix
{ inputs, ... }:
let
  sshPort = 2222;
  authorizedKeys = [
    "ssh-ed25519 AAAA..."
  ];
in
{
  # NixOS: Enable OpenSSH server
  flake.modules.nixos.ssh = {
    services.openssh = {
      enable = true;
      settings.Port = sshPort;
      settings.PasswordAuthentication = false;
    };

    users.users.root.openssh.authorizedKeys.keys = authorizedKeys;
  };

  # macOS: Enable SSH server
  flake.modules.darwin.ssh = {
    services.sshd.enable = true;
  };

  # Home Manager: Client configuration
  flake.modules.homeManager.ssh = { config, ... }: {
    programs.ssh = {
      enable = true;
      matchBlocks = {
        "github.com" = {
          user = "git";
          identityFile = "${config.home.homeDirectory}/.ssh/id_ed25519";
        };
      };
    };
  };
}
```

### Example 2: Gaming Setup

```nix
# modules/gaming.nix
{ inputs, ... }:
{
  # NixOS: Enable Steam, gamemode, etc.
  flake.modules.nixos.gaming = { pkgs, ... }: {
    programs.steam.enable = true;
    programs.gamemode.enable = true;

    hardware.opengl = {
      enable = true;
      driSupport = true;
      driSupport32Bit = true;
    };
  };

  # Home Manager: Gaming tools and configs
  flake.modules.homeManager.gaming = { pkgs, ... }: {
    home.packages = with pkgs; [
      mangohud
      goverlay
      lutris
    ];
  };
}
```

### Example 3: Cryptocurrency Wallets (Fixed)

```nix
# modules/crypto.nix
{ inputs, ... }:
let
  mkCakewallet = pkgs: pkgs.stdenv.mkDerivation {
    # ... package definition
  };
in
{
  # Home Manager: Crypto applications
  flake.modules.homeManager.crypto = { pkgs, lib, config, ... }: {
    options.crypto = {
      enable = lib.mkEnableOption "crypto applications";
      cakewallet.enable = lib.mkEnableOption "Cake Wallet";
    };

    config = lib.mkIf config.crypto.enable {
      home.packages = lib.optionals config.crypto.cakewallet.enable [
        (mkCakewallet pkgs)
      ];
    };
  };

  # NixOS: System-level crypto services (future)
  # flake.modules.nixos.crypto = { /* ... */ };
}
```

### Example 4: Separate Email Module

```nix
# modules/email.nix
{ inputs, ... }:
{
  flake.modules.homeManager.email = { pkgs, lib, config, ... }: {
    options.email = {
      enable = lib.mkEnableOption "email applications and services";
      thunderbird.enable = lib.mkEnableOption "Thunderbird";
      protonBridge.enable = lib.mkEnableOption "Proton Mail Bridge";
    };

    config = lib.mkIf config.email.enable (lib.mkMerge [
      (lib.mkIf config.email.thunderbird.enable {
        home.packages = [ pkgs.thunderbird ];
      })

      (lib.mkIf config.email.protonBridge.enable {
        home.packages = [ pkgs.protonmail-bridge ];

        systemd.user.services.protonmail-bridge = {
          Unit.Description = "Proton Mail Bridge";
          Service = {
            ExecStart = "${pkgs.protonmail-bridge}/bin/protonmail-bridge --noninteractive";
            Restart = "on-failure";
          };
          Install.WantedBy = [ "graphical-session.target" ];
        };
      })
    ]);
  };
}
```

### Example 5: Using Aspects in Host Configuration

```nix
# modules/hosts.nix
{ inputs, ... }:
{
  flake.nixosConfigurations.my-laptop = inputs.nixpkgs.lib.nixosSystem {
    system = "x86_64-linux";
    modules = with inputs.self.modules.nixos; [
      # Include the aspects you want
      ssh
      vim
      gaming
      crypto
    ];
  };

  flake.darwinConfigurations.my-macbook = inputs.nix-darwin.lib.darwinSystem {
    system = "aarch64-darwin";
    modules = with inputs.self.modules.darwin; [
      ssh
      vim
      # gaming not available on macOS
      crypto
    ];
  };
}
```

---

## Common Pitfalls

### ❌ Pitfall 1: Defining the Same Path Twice

```nix
# WRONG!
{
  flake.modules.homeManager = {
    crypto = { /* ... */ };
  };

  flake.modules.homeManager = {  # ❌ Redefinition!
    email = { /* ... */ };
  };
}
```

### ✅ Fix: Use Separate Attributes

```nix
# CORRECT!
{
  flake.modules.homeManager.crypto = { /* ... */ };
  flake.modules.homeManager.email = { /* ... */ };
}
```

### ❌ Pitfall 2: Using specialArgs

```nix
# WRONG - Don't use specialArgs in dendritic setups
{
  flake.nixosConfigurations.host = nixpkgs.lib.nixosSystem {
    specialArgs = { inherit myValue; };  # ❌ Anti-pattern!
  };
}
```

### ✅ Fix: Use Let-Bindings

```nix
# CORRECT - Share values via let-bindings
let
  myValue = "shared";
in
{
  flake.modules.nixos.myAspect = { /* use myValue */ };
  flake.modules.homeManager.myAspect = { /* use myValue */ };
}
```

### ❌ Pitfall 3: Host-Centric File Names

```nix
# WRONG - Don't name files after hosts
modules/
  laptop.nix
  desktop.nix
  server.nix
```

### ✅ Fix: Aspect-Centric File Names

```nix
# CORRECT - Name files after features
modules/
  portable-setup.nix
  gaming-rig.nix
  server-stack.nix
```

---

## Key Takeaways

1. **One Aspect Per File (Usually)**: Keep it simple - one `.nix` file per aspect/feature
2. **All Files Are Flake-Parts Modules**: Every file has the same semantic meaning
3. **No Manual Imports**: Use `import-tree` to load all files automatically
4. **Feature-Centric, Not Host-Centric**: Organize by what features do, not where they run
5. **Share Values with Let-Bindings**: Don't use `specialArgs` - use let-bindings
6. **Multiple Aspects Per File Are OK**: If tightly related, you can define multiple aspects in one file
7. **Use Options for Flexibility**: Create `mkEnableOption` for each feature
8. **Incremental Features**: Split large aspects into multiple files that contribute to the same aspect

---

## Additional Resources

- [Dendritic Pattern Discussion](https://discourse.nixos.org/t/pattern-every-file-is-a-flake-parts-module/61271)
- [Dendrix Documentation](https://vic.github.io/dendrix)
- [flake-aspects](https://github.com/vic/flake-aspects) - Aspect transposition and dependencies
- [import-tree](https://github.com/vic/import-tree) - Automatic module loading
- [vic/den](https://github.com/vic/den) - Advanced dendritic setup with aspect dependencies
- [Flipping the Configuration Matrix](https://not-a-number.io/2025/refactoring-my-infrastructure-as-code-configurations/) - Excellent article by Pol Dellaiera

---

## Contributing to This Guide

This guide is a living document. If you discover new patterns or better practices, please contribute!

**Repository:** This guide lives in `modules/dendritic/README.md`

**Maintainer:** This codebase

**License:** Same as the parent repository
