# Parser for Thunderbird user.js preferences file
# Converts user_pref("key", value); format to Nix attrset
{ lib, userJsContent }:

let
  # Split content into lines
  lines = lib.splitString "\n" userJsContent;

  # Extract preference lines (user_pref("key", value);)
  prefLines = builtins.filter (line: builtins.match "^user_pref\\(.*\\);.*" line != null) lines;

  # Parse a single preference line
  parsePrefLine =
    line:
    let
      # Match: user_pref("key", value);
      # Group 1: key, Group 2: value
      match = builtins.match ''user_pref\("([^"]+)", *(.+)\);.*'' line;
    in
    if match != null then
      let
        key = builtins.elemAt match 0;
        valueStr = builtins.elemAt match 1;

        # Parse the value (true, false, number, or string)
        value =
          if valueStr == "true" then
            true
          else if valueStr == "false" then
            false
          else if builtins.match ''".*"'' valueStr != null then
            # It's a string - remove quotes
            let
              stripped = builtins.substring 1 (builtins.stringLength valueStr - 2) valueStr;
            in
            stripped
          else
            # Try to parse as number
            let
              num = lib.toInt valueStr;
            in
            num;
      in
      {
        name = key;
        inherit value;
      }
    else
      null;

  # Parse all preference lines
  parsedPrefs = builtins.filter (x: x != null) (map parsePrefLine prefLines);

  # Convert list to attrset
  prefsAttrset = builtins.listToAttrs parsedPrefs;

in
prefsAttrset
