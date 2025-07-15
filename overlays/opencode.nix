final: prev: {
  opencode = prev.opencode.overrideAttrs (oldAttrs: rec {
    version = "0.3.5";
    src = prev.fetchFromGitHub {
      owner = "sst";
      repo = "opencode";
      rev = "v${version}";
      hash = "sha256-0jqinrisc62dbfblbyfwyw2jmxfri02wqqf6p59s1c446fa1szhm";
    };
  });
}