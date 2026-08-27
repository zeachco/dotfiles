# sniff-llms

Passive llama.cpp HTTP/SSE inspector using `ngrep` and ratatui. The server does
not need to be restarted. Packet capture alone is elevated through `pkexec`.
The dotfiles setup installs `ngrep` and provides a `sniff_llms` shell alias, so
the inspector can be launched from any directory:

```bash
sniff_llms --interface any
```

The alias runs `cargo run --release --` against this project's manifest and
passes through all additional arguments.

Capture listens on **all local TCP ports**, not a single one. Every packet is
then classified by its HTTP framing (status line vs request line) or, for bare
SSE data, by its JSON shape (`choices`/`completion` ⇒ response, `messages`/
`prompt` ⇒ request). A cheap pre-filter (`/completions` path or LLM JSON keys)
drops non-LLM traffic before any flow is created, and a chat is only opened
when a response object carries both an `id` and a body (`choices`/`completion`/
`prompt`). The LLM server endpoint for each flow is learned from the first
framed packet, so requests and responses on any port pair up correctly.

Keys: `Left/Right` switch chats, `Up/Down` scroll, `End` resumes following,
`x` closes and forgets a chat, `d` writes `~/chat-id-{id}.log`, `a` cycles the
auto-clean rule, `r` renames the current chat (`Enter` saves, `Esc` cancels,
blank clears), `R` asks a local model for a short name, and `q` quits.

The sticky statistics panel shows the name (when set), model, completion
state, packet count, flow, token usage, tool-call count, and llama.cpp timing
data when those fields are present in the streamed JSON. Conversation tabs use
the custom name when set, otherwise middle-elided IDs, and color their state:
green while streaming, gray when waiting on tool calls, and red when stopped by
length or a content filter. The selected tab is underlined. When the tabs are
wider than the terminal, the bar windows around the selected one and shows a
`+N` count on either side for the hidden tabs.

New chats never steal the selection; they are appended and shown in the tab
bar, and the status line records their captured ID.

Auto-clean (key `a`) closes a chat as soon as it finishes with a matching
reason. It cycles: off → tool_calls → stop → length → content_filter → off. The
current rule is always shown in the bottom bar.

The `R` key sends the first 100 characters of the user's request and the last
1000 characters of the assistant output to `ollama run` (model `gemma4:e2b`,
override with `SNIFF_NAMER`) and applies the returned short name to the chat.
Tool calls are parsed from `delta.tool_calls` and rendered as an orange
`=== TOOL CALLS ===` section in the chat log and in `d` dumps.

Only plain HTTP can be decoded. Start capture before the request if you want its
system prompt and full message list included.
