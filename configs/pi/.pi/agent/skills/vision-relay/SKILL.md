---
name: vision-relay
description: >
  Relayed image reading for non-vision models. Use when the active model
  cannot see images (check $PI_MODEL — e.g. GLM-4.7-Flash) and the user
  pasted an image, attached one, or asks about a screenshot/image the model
  cannot view. Spawns a qwen3.8 subagent (planner) that reads the image and
  returns a structured description. Do NOT use when $PI_MODEL is a
  vision-capable model (qwen3.8) — just use the read tool directly then.
---

# Vision relay

The active model here may be text-only (`GLM-4.7-Flash-UD-Q4_K_XL` on the
light router). It receives pasted images as a placeholder (typically
"Read image file [image/png]") with **no file path and no pixels**. This
skill gets the image to a vision model (`qwen3.8`) and brings the
description back.

## When to use

1. Check `$PI_MODEL`.
   - Vision-capable (`qwen3.8`, or any model with `"image"` in `input` in
     `~/.pi/agent/models.json`) → **stop, don't use this skill**; use the
     `read` tool on the image file directly.
   - Text-only (GLM tier, …) and the user pasted/attached an image or asks
     about one → continue.
2. Never route this to `gemma-4-E2B` or other light-tier vision models:
   they are cold and 16k-context. `qwen3.8` is resident, 393k-context, and
   far stronger. The `planner` agent already targets it
   (`llamacpp/qwen3.8`).

## Step 1 — locate the image bytes

- **Explicit path in the user's message** → use it. Skip to step 2.
- **Pasted image (no path visible)** → the image bytes are base64 in the
  current session file. Extract the newest one:

```bash
python3 - <<'EOF'
import base64, glob, json, os, sys, time
path = os.environ.get('PI_SESSION_FILE', '')
if not path:
    cands = glob.glob(os.path.expanduser('~/.pi/agent/sessions/*/*.jsonl'))
    if not cands:
        sys.exit('no session file found')
    path = max(cands, key=os.path.getmtime)  # current session is being written
last_user, last_any = None, None
with open(path) as f:
    for line in f:
        if '"type":"image"' not in line:
            continue
        try:
            obj = json.loads(line)
        except Exception:
            continue
        m = obj.get('message') or {}
        c = m.get('content')
        if not isinstance(c, list) or not any(
            isinstance(x, dict) and x.get('type') == 'image' for x in c
        ):
            continue
        rec = (m.get('role'), c, [x.get('text', '')[:120] for x in c
                                 if isinstance(x, dict) and x.get('type') == 'text'])
        if m.get('role') == 'user':
            last_user = rec
        last_any = rec
rec = last_user or last_any
if rec is None:
    sys.exit('no image found in session file')
role, c, texts = rec
ext = {'image/png': 'png', 'image/jpeg': 'jpg', 'image/webp': 'webp',
       'image/gif': 'gif', 'image/bmp': 'bmp'}.get(
    next(x.get('mimeType') for x in c
         if isinstance(x, dict) and x.get('type') == 'image'), 'bin')
stamp = int(time.time())
for i, x in enumerate(
    x for x in c if isinstance(x, dict) and x.get('type') == 'image'
):
    out = f'/tmp/vision-relay-{stamp}-{i + 1}.{ext}'
    with open(out, 'wb') as fh:
        fh.write(base64.b64decode(x['data']))
    print(out)
print(f'FROM: {role} message, sibling text: {texts}', file=sys.stderr)
EOF
```

The script prints the temp file path(s) to stdout and the source context to
stderr — sanity-check the stderr line: the image should come from the
user's most recent paste (or a `read` tool result of a path the user gave).

- **No image found and no path** → ask the user to save the image to a file
  and share the path. Don't guess.

## Step 2 — spawn the qwen3.8 subagent

The subagent is a fresh process that has NOT seen this conversation. Its
task must be self-contained: exact absolute path, the user's intent
verbatim, and the output contract. Use the `planner` agent (qwen3.8):

```
agent: planner
task:
  You are describing an image for another model that cannot see.
  1. Use the read tool on: <ABSOLUTE_TEMP_PATH>
     (it is an image file; it will be attached to your context).
  2. What the user is looking for: "<their question or intent, verbatim>"

  Return ONLY a description, in this structure:
  - Overview: what the image shows (1–3 sentences)
  - Visible text: ALL text in the image, transcribed verbatim, in order
    (UI labels, code, error messages, filenames, numbers)
  - Relevant details: the specifics that answer the question above
    (values, states, positions, what changed, what is highlighted)
  - Uncertainties: anything blurry, cut off, or ambiguous

  Use the read tool only; do no other work.
```

For multiple images, pass all paths in step 1 and describe each.

## Step 3 — verify and relay

- The subagent's reply must be a real description (concrete content
  matching the image kind). If it reports an error or returns nothing
  usable: `ls -la` + `file <path>` the temp file, re-send once, then tell
  the user the relay failed. Trust the output, not the report.
- Relay the description to the user, noting it is a relayed reading (the
  model cannot see the image itself), then continue the original task
  using it.
- Clean up: `rm /tmp/vision-relay-*.{png,jpg,webp,gif,bmp}` when done.
