# Stretch artwork kit

Generates the 18 stretch illustrations and drops them into
`Health Tracker/Assets.xcassets` as `stretch-<id>` imagesets. The app
(`StretchCard`) automatically shows the image once it exists and falls back to
the SF Symbol figure until then, so this can be run any time.

The ids come from `Stretch.id` in `Health Tracker/Stretches.swift`
(`python3 generate.py --list` prints them).

## Option A — automatic (image API key)

```bash
cd tools/stretch-art
export OPENAI_API_KEY=sk-...
python3 generate.py --install        # generates all 18 and installs them
```

Uses `gpt-image-1` at 1024×1024 with a transparent background. Rough cost is a
few cents per image. Redo one with `--only <id> --force`.

## Option B — no key (you generate the images)

1. `python3 generate.py --list` to see the ids.
2. Paste each prompt from `prompts.md` into your image tool.
3. Save each result as `out/stretch-<id>.png`.
4. Install them all:

```bash
python3 generate.py --install-local out
```

## After installing

Rebuild and run the app. Because the asset catalog lives in a file-system
synchronized group, new imagesets are picked up automatically — no project edit
needed. If Xcode is open, it may need a fresh build to see them.
