# sniff-llms

Passive llama.cpp HTTP/SSE inspector using `ngrep` and ratatui. The server does
not need to be restarted. Packet capture alone is elevated through `pkexec`.
The dotfiles setup installs `ngrep` and provides a `sniff_llms` shell alias, so
the inspector can be launched from any directory:

```bash
sniff_llms --port 8080 --interface any
```

The alias runs `cargo run --release --` against this project's manifest and
passes through all additional arguments.

Keys: `Left/Right` switch chats, `Up/Down` scroll, `End` resumes following,
`x` closes and forgets a chat, `d` writes `~/chat-id-{id}.log`, and `q` quits.

The sticky statistics panel shows the model, completion state, packet count,
flow, token usage, and llama.cpp timing data when those fields are present in
the streamed JSON. Conversation tabs use middle-elided IDs and color their
state: green while streaming and gray when waiting on tool calls.

Only plain HTTP can be decoded. Start capture before the request if you want its
system prompt and full message list included.
