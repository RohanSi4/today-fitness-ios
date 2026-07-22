#!/usr/bin/env python3
"""
Generate the Today stretch illustrations and install them into the app's
asset catalog as `stretch-<id>` imagesets.

Two ways to use it:

  1. With an image API key (fully automatic):
       export OPENAI_API_KEY=sk-...
       python3 generate.py --install

  2. No key: you generated the PNGs yourself (ChatGPT/Midjourney/etc.):
       save each as out/stretch-<id>.png  (ids are printed by --list)
       python3 generate.py --install-local out

The consistent house style keeps all 18 looking like one set. Regenerate a
single one with:  python3 generate.py --only butterfly --force
"""
import argparse
import base64
import json
import os
import subprocess
import sys
import tempfile
import urllib.request
from pathlib import Path

HERE = Path(__file__).resolve().parent
# tools/stretch-art -> repo root -> asset catalog
CATALOG = HERE.parent.parent / "Health Tracker" / "Assets.xcassets"
OUT = HERE / "out"

STYLE = (
    "Minimal flat vector illustration of a single athletic figure, {pose}. "
    "Solid deep-green figure (#29704F) on a fully transparent background, "
    "thick rounded strokes, clean simple fitness-diagram style, centered, "
    "shown from the angle that reads clearest, no text, no background "
    "elements, square composition."
)

# id -> pose clause. ids must match Stretch.id in Stretches.swift.
POSES = {
    # dynamic warm-up
    "butt-kickers": "jogging forward while flicking one heel up toward the glute",
    "frankensteins": "walking and kicking one straight leg up high in front to meet the opposite hand",
    "scoop-toe-touches": "bending forward at the hips, both arms scooping down past the toes",
    "open-close-gate": "standing on one leg, the other knee lifted and rotating outward to open the hip",
    "carioca": "moving sideways with one foot crossing over in front of the other, hips rotated",
    "walking-lunge-twist": "in a deep forward lunge with the torso rotated over the front knee",
    "lateral-leg-swings": "one hand on a vertical pole, swinging one leg out to the side across the body",
    "front-back-leg-swings": "one hand on a vertical pole, swinging one leg straight forward and back",
    # static cool-down
    "wall-calf": "both hands pressed on a wall, one leg stepped back straight with the heel down, stretching the calf",
    "crossed-toe-touch": "standing with ankles crossed, folding forward to reach the toes",
    "wide-toe-touch": "standing in a wide stance, bending to reach toward one foot",
    "crossed-side-bend": "legs crossed at the ankles, one arm reaching up and over to the side",
    "standing-quad": "standing on one leg, holding the opposite foot behind the glute",
    "seated-hamstring": "seated on the floor, one leg extended, reaching toward the foot",
    "butterfly": "seated on the floor, soles of the feet together, knees dropped out to the sides",
    "seated-twist": "seated on the floor, one leg crossed over the other, torso twisted",
    "pigeon": "in pigeon pose, one shin folded forward on the floor, torso lowered over it",
    "downward-calf": "in a downward-dog pike position, one heel pressing toward the floor to stretch the calf",
}


def prompt_for(stretch_id: str) -> str:
    return STYLE.format(pose=POSES[stretch_id])


def api_generate(stretch_id: str) -> bytes:
    key = os.environ.get("OPENAI_API_KEY")
    if not key:
        sys.exit("OPENAI_API_KEY is not set. Use --install-local, or export a key.")
    body = json.dumps({
        "model": "gpt-image-1",
        "prompt": prompt_for(stretch_id),
        "size": "1024x1024",
        "background": "transparent",
        "n": 1,
    }).encode()
    req = urllib.request.Request(
        "https://api.openai.com/v1/images/generations",
        data=body,
        headers={"Authorization": f"Bearer {key}", "Content-Type": "application/json"},
        method="POST",
    )
    with urllib.request.urlopen(req) as resp:
        payload = json.load(resp)
    return base64.b64decode(payload["data"][0]["b64_json"])


def install(stretch_id: str, png: bytes) -> None:
    imageset = CATALOG / f"stretch-{stretch_id}.imageset"
    imageset.mkdir(parents=True, exist_ok=True)
    (imageset / f"stretch-{stretch_id}.png").write_bytes(resize_for_app(png))
    contents = {
        "images": [{"filename": f"stretch-{stretch_id}.png", "idiom": "universal"}],
        "info": {"author": "xcode", "version": 1},
    }
    (imageset / "Contents.json").write_text(json.dumps(contents, indent=2))


def resize_for_app(png: bytes) -> bytes:
    """Keep source generation flexible while capping shipped art at 512 px."""
    sips = Path("/usr/bin/sips")
    if not sips.exists():
        return png

    with tempfile.TemporaryDirectory() as directory:
        source = Path(directory) / "source.png"
        output = Path(directory) / "output.png"
        source.write_bytes(png)
        subprocess.run(
            [str(sips), "-Z", "512", str(source), "--out", str(output)],
            check=True,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
        )
        return output.read_bytes()


def main() -> None:
    ap = argparse.ArgumentParser(description="Generate/install Today stretch art.")
    ap.add_argument("--install", action="store_true", help="Generate via API and install into the asset catalog.")
    ap.add_argument("--install-local", metavar="DIR", help="Install existing stretch-<id>.png files from DIR (no API).")
    ap.add_argument("--only", metavar="ID", help="Limit to a single stretch id.")
    ap.add_argument("--force", action="store_true", help="Overwrite outputs that already exist.")
    ap.add_argument("--list", action="store_true", help="Print every stretch id and exit.")
    args = ap.parse_args()

    if args.list:
        for sid in POSES:
            print(sid)
        return

    ids = [args.only] if args.only else list(POSES)
    for sid in ids:
        if sid not in POSES:
            sys.exit(f"Unknown stretch id: {sid}")

    if args.install_local:
        src = Path(args.install_local)
        for sid in ids:
            png = src / f"stretch-{sid}.png"
            if not png.exists():
                print(f"skip {sid}: {png} not found")
                continue
            install(sid, png.read_bytes())
            print(f"installed {sid}")
        return

    OUT.mkdir(exist_ok=True)
    for sid in ids:
        dest = OUT / f"stretch-{sid}.png"
        if dest.exists() and not args.force:
            print(f"skip {sid}: already generated (use --force)")
        else:
            print(f"generating {sid} ...")
            dest.write_bytes(api_generate(sid))
        if args.install:
            install(sid, dest.read_bytes())
            print(f"installed {sid}")


if __name__ == "__main__":
    main()
