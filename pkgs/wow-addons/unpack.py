"""Unpack addon ZIPs with Windows paths, then check their Forever TOCs."""

import pathlib
import re
import shutil
import stat
import sys
import zipfile

OPENMAP_ANCHOR = '\tmap:HookScript("OnShow", function()\n\t\tC_Timer.After(0.1, function()\n'
OPENMAP_PATCH = '\t\t\tdo return end -- local patch: keep Blizzard live dungeon map\n'


def unpack(src, out):
    out = pathlib.Path(out)
    out.mkdir(parents=True)
    with zipfile.ZipFile(src) as archive:
        for entry in archive.infolist():
            path = pathlib.PurePosixPath(entry.filename.replace("\\", "/"))
            if path.is_absolute() or ".." in path.parts or stat.S_ISLNK(entry.external_attr >> 16):
                raise ValueError(f"unsafe ZIP path: {entry.filename}")
            target = out / path
            if entry.is_dir() or entry.filename.endswith("\\"):
                target.mkdir(parents=True, exist_ok=True)
            else:
                target.parent.mkdir(parents=True, exist_ok=True)
                with archive.open(entry) as source, target.open("wb") as dest:
                    shutil.copyfileobj(source, dest)

    dungeons = out / "OpenMap/Map/Dungeons.lua"
    if dungeons.exists():
        text = dungeons.read_text(encoding="utf-8")
        if text.count(OPENMAP_ANCHOR) != 1 or OPENMAP_PATCH in text:
            raise ValueError("OpenMap live dungeon map anchor changed; review the patch")
        dungeons.write_text(text.replace(OPENMAP_ANCHOR, OPENMAP_ANCHOR + OPENMAP_PATCH), encoding="utf-8")

    folders = sorted(out.iterdir())
    if not folders:
        raise ValueError("empty addon archive")
    for folder in folders:
        tocs = list(folder.glob("*.toc")) if folder.is_dir() else []
        if not any(re.search(r"^##\s*Interface\s*:.*\b16001\b", t.read_text(encoding="utf-8-sig"), re.M) for t in tocs):
            raise ValueError(f"no Forever (16001) TOC in {folder.name}")
        print(folder.name)


if __name__ == "__main__":
    unpack(sys.argv[1], sys.argv[2])
