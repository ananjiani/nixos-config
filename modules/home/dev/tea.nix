{
  config,
  pkgs,
  ...
}:

{
  sops.secrets.codeberg_tea_token = {
    sopsFile = ../../../secrets/secrets.yaml;
    mode = "0400";
  };

  home.activation.teaCodebergAuth =
    config.lib.dag.entryAfter
      [
        "writeBoundary"
        "setupEtc"
      ]
      ''
        token_file="${config.sops.secrets.codeberg_tea_token.path}"
        if [ ! -f "$token_file" ]; then
          echo "tea: codeberg_tea_token secret not found, skipping" >&2
          exit 0
        fi

        token=$(${pkgs.coreutils}/bin/cat "$token_file")
        if [ -z "$token" ]; then
          echo "tea: codeberg_tea_token is empty, skipping" >&2
          exit 0
        fi

        # Skip if Codeberg is unreachable to avoid deleting a working login during an outage
        if ! ${pkgs.curl}/bin/curl -sf --max-time 5 https://codeberg.org/api/v1/version > /dev/null 2>&1; then
          echo "tea: Codeberg appears to be down, skipping login update" >&2
          exit 0
        fi

        # Remove stale/expired codeberg login if present
        if ${pkgs.tea}/bin/tea login list 2>/dev/null | ${pkgs.gnugrep}/bin/grep -q codeberg; then
          ${pkgs.tea}/bin/tea login delete codeberg 2>/dev/null || true
        fi

        ${pkgs.tea}/bin/tea login add \
          --name codeberg \
          --url https://codeberg.org \
          --token "$token" \
          --no-version-check

        ${pkgs.tea}/bin/tea login default codeberg
      '';
}
