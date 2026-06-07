# Live USB / Installation ISO configuration
{
  lib,
  modulesPath,
  inputs,
  pkgs,
  ...
}:

let
  # Decrypt wifi secrets at ISO build time using the desktop's age key.
  # In pure mode (CI, deploy-rs checks) the key path isn't visible, so we
  # produce a dummy derivation instead.  For a real ISO, build with `--impure`.
  ageKeyPath = /home/ammar/.config/sops/age/keys.txt;

  wifi-secrets =
    if builtins.pathExists ageKeyPath then
      pkgs.runCommand "iso-wifi-secrets"
        {
          nativeBuildInputs = [ pkgs.sops ];
          SOPS_AGE_KEY = builtins.readFile ageKeyPath;
        }
        ''
          mkdir -p $out
          sops -d --extract '["wifi_ssid"]' ${../../secrets/secrets.yaml} > $out/ssid
          sops -d --extract '["wifi_psk"]' ${../../secrets/secrets.yaml} > $out/psk
        ''
    else
      pkgs.runCommand "iso-wifi-secrets-dummy" { } ''
        mkdir -p $out
        echo "dummy" > $out/ssid
        echo "dummy" > $out/psk
      '';
in
{
  imports = [
    "${modulesPath}/installer/cd-dvd/installation-cd-minimal.nix"
    "${modulesPath}/installer/cd-dvd/channel.nix"
    ../_profiles/base.nix
    ../../modules/nixos/ssh.nix
    inputs.disko.nixosModules.disko
  ];

  nixpkgs.hostPlatform = "x86_64-linux";

  # SSH with permissive settings for installation
  modules.ssh = {
    enable = true;
    passwordAuth = true;
    permitRootLogin = "yes";
  };

  # Override the empty password from installation-cd-minimal.nix
  users.users.root = {
    initialHashedPassword = lib.mkForce null;
    initialPassword = "nixos";
    openssh.authorizedKeys.keys = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIMoo8KQiLBJ6WrWmG0/6O8lww/v6ggPaLfv70/ksMZbD ammar.nanjiani@gmail.com"
    ];
  };

  # Auto-connect to WiFi on boot (decrypted at build time, plaintext in nix store)
  systemd.services.iso-wifi = {
    description = "Connect to WiFi on boot";
    wantedBy = [ "multi-user.target" ];
    after = [ "network.target" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };
    path = with pkgs; [
      wpa_supplicant
      dhcpcd
    ];
    script = ''
      SSID=$(cat ${wifi-secrets}/ssid)
      PSK=$(cat ${wifi-secrets}/psk)
      # Find the wireless interface
      IFACE=$(ls /sys/class/net/ | grep -E '^wl' | head -1)
      if [ -z "$IFACE" ]; then
        echo "iso-wifi: no wireless interface found"
        exit 0
      fi
      wpa_passphrase "$SSID" "$PSK" > /tmp/wpa.conf
      wpa_supplicant -B -i "$IFACE" -c /tmp/wpa.conf
      dhcpcd "$IFACE"
      echo "iso-wifi: connected to $SSID on $IFACE"
    '';
  };

  # Extra tools available via: nix shell nixpkgs#parted nixpkgs#gptfdisk etc.
}
