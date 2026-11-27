#!/usr/bin/env python3
"""Prepare an offline startup pack for the game using existing local 523 resources."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import subprocess
import sys

GIRAN = [33441, 32813]  # Same source-village position as the game.
STAGE = "FULLSTARTUP_RESULT "


def sha(path):
    with path.open("rb") as source:
        return hashlib.file_digest(source, "sha256").hexdigest()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    for option in ("game", "original", "game-pack", "godot", "output"):
        parser.add_argument("--" + option, type=Path, required=True)
    parser.add_argument("--game-pack-sha256", required=True)
    parser.add_argument("--timeout", default=900, type=int)
    args = parser.parse_args()
    game, original, packed_game, godot, output = (
        x.resolve() for x in (args.game, args.original, args.game_pack, args.godot, args.output)
    )
    if output.is_relative_to(Path(__file__).resolve().parents[1]) or output.is_relative_to(game) or output.is_relative_to(original):
        parser.error("use a new output directory outside both repositories and the original pack")
    if sha(packed_game) != args.game_pack_sha256.lower():
        parser.error("exported game pack SHA-256 mismatch")
    desc = json.loads((original / "source523_pack.json").read_bytes())
    addons = json.loads((original / "source523_addons.json").read_bytes())
    verified = {}
    for name in ("bank", "images", "maps", "tiles", "ui", "world_links"):
        section = desc.get(name, addons.get(name))
        if not isinstance(section, dict):
            parser.error("required startup input is missing: " + name)
        manifest = (original / section["manifest"]).resolve()
        if not manifest.is_relative_to(original) or sha(manifest) != section["manifest_sha256"]:
            parser.error("original manifest SHA-256 mismatch: " + name)
        verified[name] = section["manifest_sha256"]
    tables = (original / desc["tables"]["path"]).resolve()
    if not tables.is_relative_to(original) or sha(tables) != desc["tables"]["sha256"]:
        parser.error("original tables ZIP SHA-256 mismatch")
    options = {"enabled": True, "native_land_id": 4, "source_position": GIRAN,
               "navigation_profile": "CURRENT523_GENERIC_S32_OWN_ALLOWLIST_V1",
               "portal_landing_policy": "OWN_FIRST_CLEAR_IN_DECLARED_REGION_V1",
               "raw_root": str(original / desc["maps"]["root"]), "tile_root": str(original / desc["tiles"]["root"]),
               "source_manifest_sha256": verified["maps"], "tile_manifest_sha256": verified["tiles"]}
    output.mkdir(mode=0o700, parents=True)
    (output / "options.json").write_text(json.dumps(options))
    environment = {k: v for k, v in os.environ.items() if not k.startswith("TWILIGHT_")}
    environment.update(TWILIGHT_ENTRY_OPTIONS=str(output / "options.json"),
                       TWILIGHT_ENTRY_RESULT=str(output / "startup.json"), TWILIGHT_FULLSTARTUP_CONDITION="first",
                       TWILIGHT_BAKE_DISK_REQUIRED="1", TWILIGHT_FULLSTARTUP_BAG_PROBE="1",
                       GODOT_SILENCE_ROOT_WARNING="1", MALLOC_ARENA_MAX="2", MALLOC_TRIM_THRESHOLD_="16384")
    for k in ("data", "cache", "config"):
        environment["XDG_" + k.upper() + "_HOME"] = str(output / ("profile-" + k))
    harness = game / "tools/boot/benchmark_full_startup.gd"
    command = [str(godot), "--headless", "--main-pack", str(packed_game), "--script", str(harness),
               "--", "--source523-pack=" + str(original)]
    stdout = output / "startup.log"
    with stdout.open("w") as log:
        result = subprocess.run(command, cwd=output, env=environment, stdout=log, stderr=subprocess.STDOUT,
                                timeout=args.timeout, check=False)
    lines = stdout.read_text(errors="replace").splitlines()
    if result.returncode or not any(line.startswith(STAGE) for line in lines) or any(
            line.startswith(("ERROR:", "SCRIPT ERROR:")) for line in lines):
        parser.error("original startup failed, see startup.log")
    measured = json.loads((output / "startup.json").read_bytes())
    if measured.get("ok") is not True or measured.get("failures") or not measured.get("phases_us", {}).get("main_ready_us"):
        parser.error("original map and character did not reach playable readiness")
    caches = list((output / "profile-data").rglob("current523_bake"))
    if len(caches) != 1:
        parser.error("expected exactly one generated bake directory")
    subprocess.run([sys.executable, str(game / "tools/boot/build_startup_bakes.py"),
                    "--cache", str(caches[0]), "--output", str(output / "private-pack")], check=True)
    (output / "inputs.json").write_text(json.dumps({"preparation_game_sha256": args.game_pack_sha256,
        "source_pack": desc["pack_id"], "manifests": verified, "tables_sha256": desc["tables"]["sha256"]},
        sort_keys=True, indent=2) + "\n")


if __name__ == "__main__":
    main()
