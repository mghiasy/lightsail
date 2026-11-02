# -*- mode: python ; coding: utf-8 -*-
"""PyInstaller spec for the standalone Lightsail macOS app."""

from pathlib import Path

from PyInstaller.utils.hooks import collect_all

ROOT = Path(SPECPATH).resolve().parent

datas = [
    (str(ROOT / "web"), "web"),
    (str(ROOT / "backend"), "backend"),
]

hiddenimports = [
    "server",
    "create_instance",
    "cleanup_instance",
    "app_paths",
]

# Bundle awscli so the app works without a system `aws` binary.
for pkg in ("awscli", "botocore", "s3transfer", "colorama", "docutils", "rsa", "yaml"):
    try:
        pkg_datas, pkg_binaries, pkg_hidden = collect_all(pkg)
        datas += pkg_datas
        hiddenimports += pkg_hidden
    except Exception:
        pass

a = Analysis(
    [str(ROOT / "macos" / "app_main.py")],
    pathex=[str(ROOT / "backend")],
    binaries=[],
    datas=datas,
    hiddenimports=hiddenimports,
    hookspath=[],
    hooksconfig={},
    runtime_hooks=[],
    excludes=[],
    noarchive=False,
)

pyz = PYZ(a.pure)

exe = EXE(
    pyz,
    a.scripts,
    [],
    exclude_binaries=True,
    name="Lightsail",
    debug=False,
    bootloader_ignore_signals=False,
    strip=False,
    upx=False,
    console=False,  # double-clickable GUI app (opens browser)
    disable_windowed_traceback=False,
    argv_emulation=True,  # macOS: forward args to frozen binary
)

coll = COLLECT(
    exe,
    a.binaries,
    a.datas,
    strip=False,
    upx=False,
    name="Lightsail",
)

app = BUNDLE(
    coll,
    name="Lightsail.app",
    icon=None,
    bundle_identifier="local.lightsail.app",
    info_plist={
        "CFBundleName": "Lightsail",
        "CFBundleDisplayName": "Lightsail",
        "CFBundleShortVersionString": "1.0.0",
        "CFBundleVersion": "1.0.0",
        "LSMinimumSystemVersion": "12.0",
        "NSHighResolutionCapable": True,
        "NSAppleEventsUsageDescription": (
            "Lightsail automates Outline Manager to paste server credentials "
            "and copy the access key."
        ),
    },
)
