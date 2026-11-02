---
name: lmms-music
description: >
  Music production through LMMS via the lmms-mcp MCP server. Use when the user
  asks to compose, generate, arrange, mix, or render music on this machine, or
  mentions LMMS, .mmpz projects, MIDI notes, a song/beat/track to build, or
  turning a musical idea into audio. The server's tools (mcp__lmms__*) create
  and modify LMMS project files directly; LMMS itself is only needed for
  rendering. If no mcp__lmms__* tools are visible, provision the server first
  (venv + MCP entry, see Setup).
---

# LMMS music production

`lmms-mcp` (github.com/ZipseLu/lmms-mcp — git-only, **not on PyPI**) is an MCP
server that edits LMMS projects as files (`.mmp` XML / `.mmpz` compressed). It
keeps one "current project" in memory per process; everything else is file I/O.
LMMS is invoked headless only for `render_project` (`lmms render <proj> -o out`).

This box: LMMS **1.2.2** at `/usr/bin/lmms`. SlicerT/Xpressive instruments and
the compressor/dispersion/frequencysifter/slewdistortion effects are **1.3+ only
— avoid them here**.

## Setup (once per machine)

1. Venv (Python ≥ 3.10):
   ```sh
   python3 -m venv ~/.venvs/lmms-mcp
   git clone --depth 1 https://github.com/ZipseLu/lmms-mcp /tmp/lmms-mcp
   ~/.venvs/lmms-mcp/bin/pip install /tmp/lmms-mcp
   ```
   (The `uv` mise shim errors on this box; use `python3 -m venv` or the real
   binary under `~/.local/share/mise/installs/uv/…/uv`.)
2. Add the MCP entry to each harness — the env vars are load-bearing:
   - pi: `~/.pi/agent/mcp.json` → `mcpServers.lmms`
   - opencode: `~/.config/opencode/opencode.json` → `mcp.lmms` (seed:
     `configs/opencode/.config/opencode/opencode.seed.json`)
   - claude: `~/.claude.json` → `mcpServers.lmms`

   ```json
   { "command": "/home/olivier/.venvs/lmms-mcp/bin/lmms-mcp",
     "env": { "LMMS_EXECUTABLE": "/usr/bin/lmms",
              "LMMS_PROJECTS_DIR": "/home/olivier/Music/lmms/AI-Projects" } }
   ```
   (opencode uses `environment` instead of `env`; `~` may need expanding.)
   - **`LMMS_EXECUTABLE` is required on Linux**: the server's detection checks
     only that env var and hardcoded Windows paths — it never scans PATH.
     Without it, rendering is disabled and plugin checks silently skip.
   - `LMMS_PROJECTS_DIR` default if unset: `~/Desktop/Media/lmms/AI-Projects`.
   - Optional `LMMS_PRESETS_DIR` for Zyn preset discovery.
3. Verify: `get_lmms_info` returns `found: true, version: "1.2.2"`.

## Tool map (52 tools)

- **Project**: `create_project`, `load_project`, `save_project`, `get_project_info`, `get_project_xml`
- **Tracks**: `add_instrument_track`, `add_sample_track`, `add_automation_track`, `add_pattern_track`, `remove_track`, `list_tracks`, `get_track`, `set_track_volume`, `set_track_panning`, `mute_track`, `solo_track`
- **Notes**: `add_note`, `add_note_by_name`, `add_notes_batch`
- **Mixer**: `add_mixer_channel`, `get_mixer_channels`, `set_mixer_channel_volume`, `set_mixer_channel_name`
- **FX**: `add_effect`, `remove_effect`, `toggle_effect`, `get_effect_chain`
- **Zyn**: `list_zyn_presets`, `load_zyn_preset`, `set_zyn_params`
- **Arrangement**: `place_pattern`, `place_bb_clip`, `place_sample_clip`, `assign_sample_file`, `move_clip`, `delete_clip`, `get_arrangement`, `add_automation`
- **Song**: `set_tempo`, `set_time_signature`, `set_master_volume`, `set_master_pitch`
- **VST**: `list_available_plugins`, `scan_vst_directory`, `add_vst_track`
- **Math**: `note_name_to_key`, `key_to_note_name`, `bars_to_ticks_converter`, `ticks_to_bars_converter`, `generate_scale`
- **Env**: `get_lmms_info`, `render_project`

## Workflow: idea → rendered audio

1. `create_project(bpm=120, time_sig_numerator=4, time_sig_denominator=4)`.
2. One `add_instrument_track(name=…, instrument=…)` per part (see table below).
3. `place_pattern(track_index, pos_bars=0, length_bars=1)` to lay the loop in
   the arrangement; repeat the call for each loop iteration (or longer
   `length_bars`).
4. Notes in ticks — **192 ticks/bar, 16 steps/bar, 12 ticks/step**:
   `add_notes_batch(track_index, notes=[{key, pos, length, volume, panning}])`
   where key is a MIDI number or a name like `"C4"`. `add_note_by_name` adds
   one. Notes beyond a pattern clip's end are **silent in LMMS** — the server
   auto-extends the clip and warns; size patterns to the notes, not vice versa.
5. Mix: `set_mixer_channel_volume`, `add_effect` (eq, delay, chorus, reverb,
   amplifier, …), `set_track_panning`.
6. `save_project(path="song.mmpz")` — required before rendering.
7. `render_project(file_format="wav")` → headless render next to the project
   (wav/flac/ogg/mp3). Check the WAV is plausibly sized: 2 bars @ 120 BPM ≈
   2 s ≈ 1 MB (stereo 16-bit 44.1 kHz ≈ 172 KB/s).

## Instruments (built-in, lowercase names)

| instrument | what |
|---|---|
| `tripleoscillator` | 3-osc subtractive — default, always works |
| `kicker` | kick-drum synth (drum backbone) |
| `lb302` | TB-303 acid bass |
| `monstro` | 3-osc poly synth (leads/pads) |
| `zynaddsubfx` | feature-rich synth; presets via `list_zyn_presets`/`load_zyn_preset` |
| `opulenz` | OPL3 FM (DX100 style) |
| `freeboy`, `nes`, `sid` | chiptune chips |
| `watsyn` | wavetable synth |
| `sf2player` | SoundFont (needs an `.sf2` file) |
| `audiofileprocessor` | audio sampler — pair with `assign_sample_file` + `place_sample_clip` |
| `slicert`, `xpressive` | **LMMS 1.3+ only — not on this machine** |

A typical starter stack: `kicker` (kick), `tripleoscillator` or `lb302` (bass),
`monstro` or `zynaddsubfx` (lead), all through `eq`/`delay` on the mixer.

## Gotchas

- Single current project per server process — `load_project` switches it; do
  not interleave two songs.
- Linux plugin detection globs `*.dll` (Windows-only), so `plugin_count` is 0
  here; trust the built-in list and keep off 1.3-only items.
- `get_project_info` after each stage catches mistakes early; it returns
  tempo, time signature, tracks, and mixer channels.
- The venv's `mcp` SDK is 2.x (protocol `2026-07-28`) — that is what
  pi/opencode/claude negotiate with; don't "fix" it back to 1.x.
- Render output lands next to the saved project; play it with the system
  player (e.g. `pw-play`) to sanity-check before showing the user.
