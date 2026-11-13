import importlib.machinery
import importlib.util
import pathlib
import sys
import tempfile
import unittest
import zipfile


def load(name, path):
    loader = importlib.machinery.SourceFileLoader(name, path)
    spec = importlib.util.spec_from_loader(name, loader)
    module = importlib.util.module_from_spec(spec)
    loader.exec_module(module)
    return module


sys.dont_write_bytecode = True
latest = load("latest", sys.argv.pop(1))
unpacker = load("unpacker", sys.argv.pop(1))


class AddonTests(unittest.TestCase):
    def test_latest_forever(self):
        files = [
            dict(id=1001, name="old.zip", versions=["1.60.1"], uploaded_at="2026-01-01"),
            dict(id=2002, name="new build+.zip", versions=["1.60.2"], uploaded_at="2026-02-01"),
            dict(id=3003, name="retail.zip", versions=["12.1.5"], uploaded_at="2026-03-01"),
            dict(id=4004, name="era.zip", versions=["1.15.9"], uploaded_at="2026-04-01"),
        ]
        self.assertEqual(latest.latest_path(files), "2/2/new%20build%2B.zip")
        with self.assertRaises(ValueError):
            latest.latest_path(files[-1:])

    def archive(self, entries):
        temp = tempfile.TemporaryDirectory()
        self.addCleanup(temp.cleanup)
        root = pathlib.Path(temp.name)
        src = root / "test.zip"
        with zipfile.ZipFile(src, "w") as archive:
            for name, data in entries.items():
                archive.writestr(name, data)
        return src, root / "out"

    def test_windows_paths_and_bom(self):
        src, out = self.archive({"Addon\\Addon.toc": "\ufeff## Interface: 16001\n"})
        unpacker.unpack(src, out)
        self.assertTrue((out / "Addon/Addon.toc").exists())

    def test_unsafe_and_wrong_interface(self):
        for name, content in [("../escape", ""), ("/absolute", ""), ("Addon/Addon.toc", "## Interface: 120105")]:
            with self.subTest(name=name):
                src, out = self.archive({name: content})
                with self.assertRaises(ValueError):
                    unpacker.unpack(src, out)

    def test_patches(self):
        for folder, file, anchor, patch in [
            ("OpenMap", "Map/Dungeons.lua", unpacker.OPENMAP_ANCHOR, unpacker.OPENMAP_PATCH),
            ("ForeverQuestLog", "Actions.lua", unpacker.QUESTLOG_ANCHOR, unpacker.QUESTLOG_PATCH),
        ]:
            for text, succeeds in [(anchor, True), ("changed", False), (anchor * 2, False), (anchor + patch, False)]:
                with self.subTest(folder=folder, text=text):
                    src, out = self.archive({f"{folder}/{folder}.toc": "## Interface: 16001", f"{folder}/{file}": text})
                    if succeeds:
                        unpacker.unpack(src, out)
                        self.assertEqual((out / folder / file).read_text(), anchor + patch)
                    else:
                        with self.assertRaises(ValueError):
                            unpacker.unpack(src, out)


unittest.main()
