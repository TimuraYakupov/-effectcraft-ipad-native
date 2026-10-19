"""Run the production responder bridge in a real UIKit iPad Simulator process."""
from pathlib import Path
import json
import os
import platform
import plistlib
import subprocess
import tempfile
import time


def run(*args):
    return subprocess.check_output(args, text=True).strip()


def main():
    root = Path(__file__).resolve().parent.parent
    listing = json.loads(run("xcrun", "simctl", "list", "devices", "available", "--json"))
    candidates = [device for runtime, devices in listing["devices"].items() if "iOS" in runtime
                  for device in devices if device.get("isAvailable") and "iPad" in device["name"]]
    if not candidates:
        raise RuntimeError("No available iPad Simulator runtime")
    candidates.sort(key=lambda d: d["state"] != "Booted")
    device = candidates[0]
    identifier = device["udid"]
    if device["state"] != "Booted":
        run("xcrun", "simctl", "boot", identifier)
    run("xcrun", "simctl", "bootstatus", identifier, "-b")
    with tempfile.TemporaryDirectory(prefix="ec-keyboard-uikit-") as temporary:
        app = Path(temporary) / "KeyboardSmoke.app"
        app.mkdir()
        plist = {"CFBundleIdentifier": "com.effectcraft.keyboard.smoke", "CFBundleExecutable": "Smoke",
                 "CFBundleName": "Keyboard Smoke", "CFBundlePackageType": "APPL", "CFBundleVersion": "10",
                 "CFBundleShortVersionString": "1.0", "MinimumOSVersion": "16.0", "UIDeviceFamily": [2],
                 "CFBundleSupportedPlatforms": ["iPhoneSimulator"], "LSRequiresIPhoneOS": True,
                 "UILaunchScreen": {}, "UISupportedInterfaceOrientations": ["UIInterfaceOrientationLandscapeLeft"]}
        (app / "Info.plist").write_bytes(plistlib.dumps(plist))
        run("xcrun", "--sdk", "iphonesimulator", "clang", "-arch", platform.machine(),
            "-isysroot", run("xcrun", "--sdk", "iphonesimulator", "--show-sdk-path"),
            "-mios-simulator-version-min=16.0", "-fobjc-arc", "-fmodules", "-Wall", "-Wextra",
            str(root / "tests/uikit-keyboard/Smoke.m"), "-framework", "UIKit", "-framework", "Foundation",
            "-o", str(app / "Smoke"))
        run("codesign", "--force", "--sign", "-", str(app))
        run("xcrun", "simctl", "install", identifier, str(app))
        data = Path(run("xcrun", "simctl", "get_app_container", identifier, plist["CFBundleIdentifier"], "data"))
        result_file = data / "Documents/result.json"
        result_file.unlink(missing_ok=True)
        env = os.environ.copy()
        # Avoid the runner's SDKROOT leaking the device SDK into simulator execution.
        env.pop("SDKROOT", None)
        subprocess.check_call(["xcrun", "simctl", "launch", "--terminate-running-process", identifier,
                               plist["CFBundleIdentifier"]], env=env)
        deadline = time.monotonic() + 90
        while not result_file.exists() and time.monotonic() < deadline:
            time.sleep(0.5)
        if not result_file.exists():
            raise RuntimeError("UIKit keyboard smoke test did not report a result within 90 seconds")
        result = json.loads(result_file.read_text())
        print(json.dumps({"simulator": device["name"], **result}, indent=2))
        if not result.get("ok"):
            raise RuntimeError(result.get("error", "UIKit keyboard test failed"))


if __name__ == "__main__":
    main()
