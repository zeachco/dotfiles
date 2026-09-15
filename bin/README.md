# bin/

Standalone helper scripts. They are not on PATH — profiles and setup scripts invoke them by
absolute path (`$HOME/dotfiles/bin/…`), and a few are exposed as shell aliases
(`say`, `listen`, `converse`, `gpu-cap`, `llamacpp-sync`, `llamacpp-audit`, `theme`,
`btfix`). Each script's header is its manual (knobs, install steps, why it exists).

| Script                 | What it does                                                                                                             | Platform        |
| ---------------------- | ------------------------------------------------------------------------------------------------------------------------ | --------------- |
| `theme-switch`         | Copies `themes/<name>` → `themes/current` and patches per-app settings (nvim, alacritty, herdr, btop, claude, codex, VS Code). `bin/theme-switch` or `theme <name>` | Cross-platform |
| `herdr-config`         | Patches single keys in `~/.config/herdr/config.toml` in place (`ensure-keys`, `sync-theme`, `set`, …) — Herdr's server rewrites the file, so the whole file is never templated | Mostly macOS   |
| `llamacpp-sync`        | Rebuilds pi's / opencode's `llamacpp*` provider model defs from the live routers (`/v1/models`), preserving per-model tuning. The `sync-models` action in `los` | Cross-platform |
| `llamacpp-audit`       | Read-only cross-check of `~/models` vs the INI presets vs the client configs; `--remote` also parses every GGUF and compares it to HF sizes | Cross-platform |
| `listen`               | Streaming speech-to-text to stdout (faster-whisper in a venv; `mock` provider for tests)                                   | Linux (pulse) / macOS |
| `say`                  | Local text-to-speech via Kokoro TTS in a venv (`KOKORO_VOICE` knob)                                                        | Linux / macOS   |
| `converse`             | Push-to-talk voice loop: `listen` → opencode → `say` in one terminal                                                       | Linux / macOS   |
| `gpu-cap`              | Pin/release the iGPU shader clock (amdgpu DPM masking) via pkexec — global to the GPU, used to throttle llama.cpp         | Strix Halo only |
| `bt-controller-refresh`| Power-cycles the MT7925 Bluetooth controller on earbud disconnect (watch mode, systemd service; `--now` = alias `btfix`) | Linux (the Framework) |
| `phone`                | Uses an Android phone over USB adb as a webcam and/or second display (wlr-randr for the Hyprland gotchas)                  | Linux (Omarchy) |

Voice pipeline install (one-time, per script header):

```sh
# listen
python3.11 -m venv ~/.local/share/listen-stt && ~/.local/share/listen-stt/bin/pip install faster-whisper numpy
# say
python3.11 -m venv ~/.local/share/kokoro-tts && ~/.local/share/kokoro-tts/bin/pip install 'torch==2.5.1+cpu' --index-url https://download.pytorch.org/whl/cpu && ~/.local/share/kokoro-tts/bin/pip install kokoro soundfile
```
