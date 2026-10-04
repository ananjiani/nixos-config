{
  pkgs,
  ...
}:

{
  home.packages = with pkgs; [
    microsoft-edge
    (pgadmin4-desktopmode.overrideAttrs (old: {
      # Backport the psycopg 3.3.5 encoding fix; remove when pgAdmin includes it.
      # https://github.com/pgadmin-org/pgadmin4/commit/bd7cde585122337b299cfd748ae991081eb6bef8
      postPatch = (old.postPatch or "") + ''
        substituteInPlace web/pgadmin/utils/driver/psycopg3/encoding.py \
          --replace-fail '_py_codecs.get(postgres_encoding,' 'py_codecs.get(postgres_encoding.upper().encode(),' \
          --replace-fail '_py_codecs[key]' 'py_codecs[key.encode()]' \
          --replace-fail $'encodings.update((k.encode(), v\n                      ) for k, v in psycopg._encodings._py_codecs.items())' 'encodings.update(psycopg._encodings.py_codecs)' \
          --replace-fail 'v: k.encode() for k, v in psycopg._encodings._py_codecs.items()' 'v: k for k, v in psycopg._encodings.py_codecs.items()'
      '';
    }))
  ];
}
