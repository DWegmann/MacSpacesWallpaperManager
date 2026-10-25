#!/usr/bin/env python3
"""Exercise the real Sparkle updater using disposable keys, bundles and a loopback server."""
import functools
import http.server
import os
from pathlib import Path
import plistlib
import subprocess
import tempfile
import threading
import uuid
import xml.etree.ElementTree as xml

PROJECT = Path(__file__).resolve().parent.parent
BUILD = Path(os.environ.get("WALLPAPER_BUILD_ROOT", os.environ.get("SPACEPAPER_BUILD_ROOT", PROJECT / ".build")))
FRAMEWORK = BUILD / "spm/artifacts/sparkle/Sparkle/Sparkle.xcframework/macos-arm64_x86_64/Sparkle.framework"
SIGN = PROJECT / "Scripts/sparkle-tool.sh"


def run(*args, **kwargs):
    return subprocess.run([str(arg) for arg in args], check=True, **kwargs)


class QuietHandler(http.server.SimpleHTTPRequestHandler):
    def log_message(self, *args):
        pass


def main():
    if not FRAMEWORK.is_dir():
        raise SystemExit("Run ./Scripts/build-app.sh first, using the same WALLPAPER_BUILD_ROOT.")
    env = os.environ.copy()
    env.setdefault("DEVELOPER_DIR", "/Applications/Xcode.app/Contents/Developer")
    sdk = subprocess.check_output([str(PROJECT / "Scripts/macos-sdk.sh")], env=env, text=True).strip()
    with tempfile.TemporaryDirectory(prefix="WallpaperUpdaterTests-") as directory:
        root = Path(directory)
        app = root / "UpdaterTests.app"
        contents = app / "Contents"
        (contents / "MacOS").mkdir(parents=True)
        (contents / "Frameworks").mkdir()
        # Copy the real, signed framework. The fixture contains no wallpaper configuration.
        run("/usr/bin/ditto", FRAMEWORK, contents / "Frameworks/Sparkle.framework")
        executable = contents / "MacOS/UpdaterTests"
        run("/usr/bin/xcrun", "swiftc", "-parse-as-library", "-sdk", sdk,
            "-module-cache-path", BUILD / "module-cache", "-F", FRAMEWORK.parent,
            "-framework", "Sparkle", "-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks",
            PROJECT / "Sources/MacSpacesWallpaperManager/UpdateController.swift",
            PROJECT / "Tools/TestUpdater.swift", "-o", executable, env=env)
        key = root / "private-test-key"
        public_key = subprocess.check_output([str(executable), "key", str(key)], text=True).strip()
        with (PROJECT / "Resources/Info.plist").open("rb") as source:
            info = plistlib.load(source)
        info.update(CFBundleIdentifier="app.spacepaper.mac.updater-tests." + uuid.uuid4().hex,
                    CFBundleExecutable="UpdaterTests", CFBundleVersion="6", SUPublicEDKey=public_key,
                    NSAppTransportSecurity={"NSAllowsLocalNetworking": True})
        with (contents / "Info.plist").open("wb") as target:
            plistlib.dump(info, target)
        run("/usr/bin/codesign", "--force", "--sign", "-", app)
        web = root / "web"
        web.mkdir()
        archive = web / "update.zip"
        run("/usr/bin/ditto", "-c", "-k", "--sequesterRsrc", "--keepParent", app, archive)
        (web / "update.md").write_text("# Test update\n\nDisposable release notes.\n", encoding="utf-8")
        run(SIGN, "generate_appcast", "--ed-key-file", key,
            "--download-url-prefix", "https://example.invalid/", "--embed-release-notes",
            "--maximum-deltas", "0", "--maximum-versions", "1", "-o", web / "appcast.xml", web)
        feed = web / "appcast.xml"
        run(SIGN, "sign_update", "--ed-key-file", key, "--verify", feed)
        enclosure = xml.parse(feed).find("./channel/item/enclosure")
        signature = enclosure.attrib["{http://www.andymatuschak.org/xml-namespaces/sparkle}edSignature"]
        run(SIGN, "sign_update", "--ed-key-file", key, "--verify", archive, signature)
        archive.write_bytes(archive.read_bytes() + b"tampered")
        rejected = subprocess.run([str(SIGN), "sign_update", "--ed-key-file", str(key), "--verify", str(archive), signature],
                                  stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
        if rejected.returncode == 0:
            raise AssertionError("Tampered archive was accepted")
        print("PASS: archive signature accepts original and rejects tampering", flush=True)
        tampered = web / "tampered.xml"
        tampered.write_bytes(feed.read_bytes().replace(b"Test update", b"Fake update"))
        # Run the installed-version fixture against the newly generated version 6 feed.
        info["CFBundleVersion"] = "5"
        with (contents / "Info.plist").open("wb") as target:
            plistlib.dump(info, target)
        run("/usr/bin/codesign", "--force", "--sign", "-", app)
        server = http.server.ThreadingHTTPServer(("127.0.0.1", 0), functools.partial(QuietHandler, directory=str(web)))
        thread = threading.Thread(target=server.serve_forever, daemon=True)
        thread.start()
        try:
            run(executable, "preferences")
            run(executable, "persisted-preferences")
            base = f"http://127.0.0.1:{server.server_port}"
            for mode, name in [("valid-feed", "appcast.xml"), ("tampered-feed", "tampered.xml")]:
                run(executable, mode, f"{base}/{name}", "-SUEnableAutomaticChecks", "NO", "-SUAutomaticallyUpdate", "YES")
        finally:
            server.shutdown()
            server.server_close()
            run(executable, "cleanup")


if __name__ == "__main__":
    main()
