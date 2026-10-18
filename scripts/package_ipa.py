"""Package only an actual ARM64 iOS Mach-O built by Cargo; never reuse a web IPA."""
from pathlib import Path
import hashlib
import json
import plistlib
import struct
import subprocess
import zipfile


def package(root: Path) -> Path:
    binary = root / "effectcraft/target/aarch64-apple-ios/release/effectcraft-ios"
    payload = binary.read_bytes()
    if len(payload) < 32 or struct.unpack_from("<III", payload) != (0xFEEDFACF, 0x0100000C, 0):
        raise ValueError("Expected a thin ARM64 Mach-O executable")
    if struct.unpack_from("<I", payload, 12)[0] != 2:
        raise ValueError("Mach-O is not an executable")
    load_commands = subprocess.check_output(["xcrun", "vtool", "-show-build", str(binary)], text=True)
    platforms = [line.split()[1:] for line in load_commands.splitlines() if line.strip().startswith("platform ")]
    if platforms != [["IOS"]]:
        raise ValueError("Binary is not built for an iOS device")
    plist = {
        "CFBundleDisplayName": "EC Native Preview 5",
        "CFBundleName": "EffectCraft Native Preview",
        "CFBundleIdentifier": "com.effectcraft.ipad.nativepreview",
        "CFBundleExecutable": "EffectCraftNative",
        "CFBundlePackageType": "APPL",
        "CFBundleShortVersionString": "0.10.0",
        "CFBundleVersion": "5",
        "MinimumOSVersion": "16.0",
        "UIDeviceFamily": [2],
        "CFBundleSupportedPlatforms": ["iPhoneOS"],
        "LSRequiresIPhoneOS": True,
        "UIFileSharingEnabled": True,
        "LSSupportsOpeningDocumentsInPlace": True,
        "UIStatusBarHidden": True,
        "UIViewControllerBasedStatusBarAppearance": True,
        "UIRequiresFullScreen": True,
        "UILaunchScreen": {},
        "UISupportedInterfaceOrientations": [
            "UIInterfaceOrientationLandscapeLeft", "UIInterfaceOrientationLandscapeRight",
            "UIInterfaceOrientationPortrait", "UIInterfaceOrientationPortraitUpsideDown",
        ],
    }
    out = root / "output"
    out.mkdir(exist_ok=True)
    ipa = out / "EffectCraft-Native-Preview-5.ipa"
    prefix = "Payload/EffectCraftNative.app/"
    with zipfile.ZipFile(ipa, "w", zipfile.ZIP_DEFLATED) as archive:
        executable = zipfile.ZipInfo(prefix + "EffectCraftNative")
        executable.create_system = 3
        executable.external_attr = 0o100755 << 16
        executable.compress_type = zipfile.ZIP_DEFLATED
        archive.writestr(executable, payload)
        archive.writestr(prefix + "Info.plist", plistlib.dumps(plist))
        for name in ("LICENSE-MIT", "LICENSE-APACHE", "ATTRIBUTION.md"):
            source = root / "effectcraft" / name
            if not source.is_file():
                raise FileNotFoundError(source)
            archive.write(source, prefix + name)
        fonts = root / "effectcraft/assets/fonts"
        for license_file in sorted(fonts.rglob("*")):
            if license_file.is_file() and ("license" in license_file.name.lower() or "ofl" in license_file.name.lower() or license_file.suffix == ".attribution"):
                archive.write(license_file, prefix + "Licenses/fonts/" + license_file.relative_to(fonts).as_posix())
    with zipfile.ZipFile(ipa) as archive:
        bad = archive.testzip()
        if bad:
            raise ValueError(f"Corrupt IPA entry: {bad}")
    (out / "BUILD.txt").write_text(load_commands, encoding="utf-8")
    (out / "SHA256.json").write_text(json.dumps({ipa.name: hashlib.sha256(ipa.read_bytes()).hexdigest()}, indent=2) + "\n", encoding="utf-8")
    return ipa


if __name__ == "__main__":
    print(package(Path(__file__).resolve().parent.parent))
