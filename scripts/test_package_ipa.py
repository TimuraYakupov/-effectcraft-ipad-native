"""Packaging checks with a synthetic Mach-O header, never an installable app."""
from pathlib import Path
import plistlib
import struct
import tempfile
import unittest
from unittest.mock import patch
import zipfile

from package_ipa import package


class PackagingTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.binary = self.root / "effectcraft/target/aarch64-apple-ios/release/effectcraft-ios"
        self.binary.parent.mkdir(parents=True)
        (self.root / "effectcraft/Cargo.toml").write_text('[workspace.package]\nversion = "0.18.0"\n')
        self.binary.write_bytes(struct.pack("<8I", 0xFEEDFACF, 0x0100000C, 0, 2, 0, 0, 0, 0))
        icon = self.root / "effectcraft/assets/app-icon"
        icon.mkdir(parents=True)
        for name in ["LICENSE.txt", "effectcraft-1024.png.attribution", "effectcraft-1024.png"]:
            (icon / name).write_bytes(b"test icon")
        for name in ("LICENSE-MIT", "LICENSE-APACHE", "ATTRIBUTION.md"):
            (self.root / "effectcraft" / name).write_text("synthetic test fixture")

    def test_rejects_mislabeled_source(self):
        (self.root / "effectcraft/Cargo.toml").write_text('[workspace.package]\nversion = "0.10.0"\n')
        with self.assertRaisesRegex(ValueError, "0.18.0 source"):
            package(self.root)

    def test_rejects_webassembly(self):
        self.binary.write_bytes(b"\x00asm" + bytes(64))
        with self.assertRaisesRegex(ValueError, "ARM64"):
            package(self.root)

    @patch("package_ipa.subprocess.check_output", return_value="platform IOSSIMULATOR\n")
    def test_rejects_simulator(self, _vtool):
        with self.assertRaisesRegex(ValueError, "iOS device"):
            package(self.root)

    @patch("package_ipa.subprocess.run", side_effect=lambda args, **kwargs: Path(args[-1]).write_bytes(b"resized icon"))
    @patch("package_ipa.subprocess.check_output", return_value="platform IOS\nminos 16.0\n")
    def test_package_layout_and_separate_identity(self, _vtool, _sips):
        ipa = package(self.root)
        with zipfile.ZipFile(ipa) as archive:
            self.assertIsNone(archive.testzip())
            prefix = "Payload/EffectCraftNative.app/"
            info = plistlib.loads(archive.read(prefix + "Info.plist"))
            self.assertEqual(info["CFBundleIdentifier"], "com.effectcraft.ipad.nativepreview")
            self.assertEqual(info["CFBundleVersion"], "26")
            self.assertEqual(info["CFBundleShortVersionString"], "0.18.0")
            self.assertEqual(info["CFBundleDisplayName"], "EffectCraft")
            self.assertEqual(info["CFBundleName"], "EffectCraft")
            self.assertEqual(info["UIDeviceFamily"], [2])
            self.assertIn("CFBundleIcons~ipad", info)
            self.assertEqual(archive.read(prefix + "AppIcon83.5x83.5@2x.png"), b"resized icon")
            self.assertTrue(info["UIStatusBarHidden"])
            declarations = {entry["UTTypeIdentifier"]: entry for entry in info["UTExportedTypeDeclarations"]}
            for name, extension in [("com.effectcraft.project", "ecproj"), ("com.effectcraft.project.xml", "ecprojx")]:
                self.assertIn("public.data", declarations[name]["UTTypeConformsTo"])
                self.assertIn(extension, declarations[name]["UTTypeTagSpecification"]["public.filename-extension"])
                self.assertIn(name, info["CFBundleDocumentTypes"][0]["LSItemContentTypes"])
            self.assertEqual(archive.read(prefix + "EffectCraftNative"), self.binary.read_bytes())
            self.assertEqual(archive.getinfo(prefix + "EffectCraftNative").external_attr >> 16, 0o100755)
        self.assertTrue((self.root / "output/SHA256.json").is_file())


if __name__ == "__main__":
    unittest.main()



