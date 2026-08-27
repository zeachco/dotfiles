use crossterm::{
    event::{self, Event, KeyCode, KeyEventKind},
    execute,
    terminal::{EnterAlternateScreen, LeaveAlternateScreen, disable_raw_mode, enable_raw_mode},
};
use ratatui::{
    Terminal,
    backend::CrosstermBackend,
    layout::{Constraint, Direction, Layout},
    style::{Color, Modifier, Style},
    text::{Line, Span, Text},
    widgets::{Block, Borders, Paragraph, Wrap},
};
use serde_json::Value;
use std::{
    collections::{HashMap, HashSet},
    env,
    fs::File,
    io::{self, BufRead, BufReader, Write},
    path::PathBuf,
    process::{Child, Command, Stdio},
    sync::mpsc::{self, Receiver},
    thread,
    time::Duration,
};

const MAX_FLOWS: usize = 2000;

#[derive(Default)]
struct Flow {
    request_buf: String,
    response_buf: String,
    requests: Vec<Value>,
    server: Option<String>,
}
struct Packet {
    header: String,
    payload: String,
}
#[derive(Default)]
struct ToolCall {
    id: String,
    name: String,
    arguments: String,
}
struct Chat {
    id: String,
    name: Option<String>,
    model: String,
    backend: Option<String>,
    flow: String,
    request: Option<Value>,
    reasoning: String,
    answer: String,
    tool_calls: Vec<ToolCall>,
    finish: Option<String>,
    scroll: u16,
    follow: bool,
    chunks: usize,
    usage: Option<Value>,
    timings: Option<Value>,
}
#[derive(Clone, Copy, PartialEq, Eq)]
enum AutoClean {
    Never,
    ToolCalls,
    Stop,
    Length,
    ContentFilter,
}
impl AutoClean {
    fn next(self) -> AutoClean {
        match self {
            AutoClean::Never => AutoClean::ToolCalls,
            AutoClean::ToolCalls => AutoClean::Stop,
            AutoClean::Stop => AutoClean::Length,
            AutoClean::Length => AutoClean::ContentFilter,
            AutoClean::ContentFilter => AutoClean::Never,
        }
    }
    fn label(self) -> &'static str {
        match self {
            AutoClean::Never => "off",
            AutoClean::ToolCalls => "tool_calls",
            AutoClean::Stop => "stop",
            AutoClean::Length => "length",
            AutoClean::ContentFilter => "content_filter",
        }
    }
    fn action_for(self, finish: &str) -> Option<String> {
        let target = match self {
            AutoClean::Never => return None,
            AutoClean::ToolCalls => "tool_calls",
            AutoClean::Stop => "stop",
            AutoClean::Length => "length",
            AutoClean::ContentFilter => "content_filter",
        };
        (finish == target).then(|| target.to_string())
    }
}
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
enum Dir {
    Request,
    Response,
}
struct App {
    flows: HashMap<String, Flow>,
    chats: Vec<Chat>,
    selected: usize,
    ignored: HashSet<String>,
    status: String,
    auto_clean: AutoClean,
    rename: Option<String>,
}

impl App {
    fn new() -> Self {
        Self {
            flows: HashMap::new(),
            chats: vec![],
            selected: 0,
            ignored: HashSet::new(),
            status: "waiting for traffic".into(),
            auto_clean: AutoClean::Never,
            rename: None,
        }
    }
    fn packet(&mut self, packet: Packet) {
        let Some((src, dst)) = parse_header(&packet.header) else {
            return;
        };
        if !looks_like_llm(&packet.payload) {
            return;
        }
        let Some(direction) = classify(&packet.payload) else {
            return;
        };
        let response = direction == Dir::Response;
        let mut endpoints = [src.to_owned(), dst.to_owned()];
        endpoints.sort();
        let key = endpoints.join(" <-> ");
        if !self.flows.contains_key(&key) && self.flows.len() >= MAX_FLOWS {
            return;
        }
        let objects = {
            let flow = self.flows.entry(key.clone()).or_default();
            if flow.server.is_none() {
                flow.server = Some(if response { src.to_owned() } else { dst.to_owned() });
            }
            let buf = if response {
                &mut flow.response_buf
            } else {
                &mut flow.request_buf
            };
            buf.push_str(&packet.payload);
            buf.push('\n');
            extract_objects(buf)
        };
        for object in objects {
            if !response && is_request(&object) {
                let flow = self.flows.get_mut(&key).expect("flow was just inserted");
                flow.requests.push(object);
                if flow.requests.len() > 20 {
                    flow.requests.remove(0);
                }
            } else if response {
                self.response(&key, object);
            }
        }
    }
    fn response(&mut self, flow_key: &str, value: Value) {
        if !is_llm_response(&value) {
            return;
        }
        let Some(id) = value.get("id").and_then(Value::as_str) else {
            return;
        };
        if self.ignored.contains(id) {
            return;
        }
        let index = self
            .chats
            .iter()
            .position(|c| c.id == id)
            .unwrap_or_else(|| {
                let request = self
                    .flows
                    .get(flow_key)
                    .and_then(|f| f.requests.last())
                    .cloned();
                let model = value
                    .get("model")
                    .and_then(Value::as_str)
                    .or_else(|| request.as_ref()?.get("model")?.as_str())
                    .unwrap_or("unknown")
                    .into();
                self.chats.push(Chat {
                    id: id.into(),
                    name: None,
                    model,
                    backend: detect_backend(&value).map(str::to_string),
                    flow: flow_key.into(),
                    request,
                    reasoning: String::new(),
                    answer: String::new(),
                    tool_calls: Vec::new(),
                    finish: None,
                    scroll: 0,
                    follow: true,
                    chunks: 0,
                    usage: None,
                    timings: None,
                });
                self.status = format!("captured {id}");
                self.chats.len() - 1
            });
        let chat = &mut self.chats[index];
        if let Some(model) = value.get("model").and_then(Value::as_str) {
            chat.model = model.into();
        }
        if let Some(backend) = detect_backend(&value) {
            chat.backend = Some(backend.to_string());
        }
        if let Some(usage) = value.get("usage") {
            chat.usage = Some(usage.clone());
        }
        if let Some(timings) = value.get("timings") {
            chat.timings = Some(timings.clone());
        }
        chat.chunks += 1;
        let Some(choice) = value.pointer("/choices/0") else {
            return;
        };
        let delta = choice.get("delta").or_else(|| choice.get("message"));
        if let Some(s) = delta
            .and_then(|v| v.get("reasoning_content"))
            .and_then(Value::as_str)
        {
            chat.reasoning.push_str(s);
        }
        if let Some(s) = delta.and_then(|v| v.get("content")).and_then(Value::as_str) {
            chat.answer.push_str(s);
        }
        if let Some(calls) = delta.and_then(|v| v.get("tool_calls")).and_then(Value::as_array) {
            for (pos, call) in calls.iter().enumerate() {
                // Tool-call arguments stream as many small deltas; concatenate them
                // per call (keyed by the delta `index`) instead of one line each.
                let idx = call
                    .get("index")
                    .and_then(Value::as_u64)
                    .map(|i| i as usize)
                    .unwrap_or(pos);
                while chat.tool_calls.len() <= idx {
                    chat.tool_calls.push(ToolCall::default());
                }
                let tc = &mut chat.tool_calls[idx];
                if tc.id.is_empty() {
                    tc.id = call
                        .get("id")
                        .and_then(Value::as_str)
                        .map(str::to_owned)
                        .unwrap_or_default();
                }
                if tc.name.is_empty() {
                    tc.name = call
                        .pointer("/function/name")
                        .and_then(Value::as_str)
                        .map(str::to_owned)
                        .unwrap_or_default();
                }
                if let Some(args) = call.pointer("/function/arguments") {
                    let frag = match args {
                        Value::String(s) => s.clone(),
                        other => serde_json::to_string(other).unwrap_or_default(),
                    };
                    tc.arguments.push_str(&frag);
                }
            }
        }
        if let Some(s) = choice.get("finish_reason").and_then(Value::as_str) {
            chat.finish = Some(s.into());
        }
        let auto = {
            let chat = &self.chats[index];
            chat
                .finish
                .as_deref()
                .and_then(|f| self.auto_clean.action_for(f))
        };
        if let Some(reason) = auto {
            let id = self.chats[index].id.clone();
            self.close_at(index);
            self.status = format!("auto-cleaned {id} ({reason})");
        }
    }
    fn close(&mut self) {
        self.close_at(self.selected)
    }
    fn close_at(&mut self, index: usize) {
        if index >= self.chats.len() {
            return;
        }
        let chat = self.chats.remove(index);
        self.ignored.insert(chat.id.clone());
        if let Some(flow) = self.flows.get_mut(&chat.flow) {
            flow.requests.clear();
            flow.request_buf.clear();
            flow.response_buf.clear();
        }
        if self.chats.is_empty() {
            self.selected = 0;
        } else {
            if index < self.selected {
                self.selected -= 1;
            }
            self.selected = self.selected.min(self.chats.len() - 1);
        }
        self.status = format!("closed and forgot {}", chat.id);
    }
    fn dump(&mut self) {
        let Some(chat) = self.chats.get(self.selected) else {
            return;
        };
        let path = env::var_os("HOME")
            .map(PathBuf::from)
            .unwrap_or_else(|| ".".into())
            .join(format!("chat-id-{}.log", safe_name(&chat.id)));
        self.status =
            match File::create(&path).and_then(|mut f| f.write_all(render_chat(chat).as_bytes())) {
                Ok(()) => format!("dumped {}", path.display()),
                Err(e) => format!("dump failed: {e}"),
            };
    }
    fn rename_commit(&mut self) {
        let buf = self.rename.take().unwrap_or_default();
        let name = buf.trim().to_string();
        if name.is_empty() {
            if let Some(c) = self.chats.get_mut(self.selected) {
                c.name = None;
                self.status = "name cleared".into();
            } else {
                self.status = "no chat to rename".into();
            }
            return;
        }
        if let Some(c) = self.chats.get_mut(self.selected) {
            c.name = Some(name.clone());
            self.status = format!("renamed → {name}");
        } else {
            self.status = "no chat to rename".into();
        }
    }
}

fn parse_header(s: &str) -> Option<(&str, &str)> {
    let mut p = s.split_whitespace();
    (p.next()? == "T").then_some(())?;
    let a = p.next()?;
    (p.next()? == "->").then_some(())?;
    Some((a, p.next()?))
}
fn is_request(v: &Value) -> bool {
    v.get("messages").is_some_and(Value::is_array) || v.get("prompt").is_some_and(Value::is_string)
}
fn is_llm_response(v: &Value) -> bool {
    v.get("id").is_some_and(|v| v.is_string())
        && (v.get("choices").is_some_and(Value::is_array)
            || v.get("completion").is_some()
            || v.get("prompt").is_some_and(Value::is_array))
}
/// Guess the serving backend from response-only signals. `None` means
/// "plain OpenAI-compatible, no distinguishing marker".
fn detect_backend(v: &Value) -> Option<&'static str> {
    if v.get("timings").is_some() {
        return Some("llama.cpp");
    }
    if v.get("prompt_eval_count").is_some()
        || v.get("eval_count").is_some()
        || v.get("done_reason").is_some()
    {
        return Some("ollama");
    }
    if v.get("provider_name").is_some() {
        return Some("openrouter");
    }
    if let Some(id) = v.get("id").and_then(Value::as_str) {
        if id.starts_with("gen-") {
            return Some("openrouter");
        }
        if id.starts_with("msg_") {
            return Some("anthropic");
        }
    }
    None
}

/// Cheap pre-filter so all-port capture does not spin up flows for non-LLM HTTP.
fn looks_like_llm(payload: &str) -> bool {
    let p = payload.to_ascii_lowercase();
    p.contains("/completions")
        || p.contains("\"choices\"")
        || p.contains("\"messages\"")
        || p.contains("\"completion\"")
        || p.contains("\"tool_calls\"")
}
/// First balanced JSON object in `s`, scanning past SSE `data:` prefixes.
fn first_json(s: &str) -> Option<Value> {
    let start = s.find('{')?;
    let bytes = s.as_bytes();
    let mut depth = 0usize;
    let mut quoted = false;
    let mut escaped = false;
    for i in start..bytes.len() {
        let b = bytes[i];
        if quoted {
            if escaped {
                escaped = false
            } else if b == b'\\' {
                escaped = true
            } else if b == b'"' {
                quoted = false
            }
        } else {
            match b {
                b'"' => quoted = true,
                b'{' => depth += 1,
                b'}' => {
                    depth -= 1;
                    if depth == 0 {
                        return serde_json::from_str(&s[start..=i]).ok();
                    }
                }
                _ => {}
            }
        }
    }
    None
}
/// Decide the direction of a packet from its HTTP framing or JSON shape.
fn classify(payload: &str) -> Option<Dir> {
    for line in payload.lines() {
        let t = line.trim();
        if t.is_empty() {
            continue;
        }
        if t.starts_with("HTTP/") {
            return Some(Dir::Response); // status line
        }
        let method = t.split_whitespace().next().unwrap_or("");
        if ["GET", "POST", "PUT", "DELETE", "PATCH", "HEAD", "OPTIONS"].contains(&method) {
            return Some(Dir::Request); // request line
        }
        break; // first non-empty line is data, not a header
    }
    let v = first_json(payload)?;
    if v.get("choices").is_some() || v.get("completion").is_some() {
        Some(Dir::Response)
    } else if v.get("messages").is_some() || v.get("prompt").is_some() {
        Some(Dir::Request)
    } else {
        None
    }
}
fn safe_name(s: &str) -> String {
    s.chars()
        .map(|c| {
            if c.is_ascii_alphanumeric() || ".-_".contains(c) {
                c
            } else {
                '_'
            }
        })
        .collect()
}

fn middle_elide(s: &str, max_chars: usize) -> String {
    let chars = s.chars().collect::<Vec<_>>();
    if chars.len() <= max_chars || max_chars < 5 {
        return s.into();
    }
    let kept = max_chars - 3;
    let left = kept.div_ceil(2);
    let right = kept / 2;
    chars[..left]
        .iter()
        .chain(['.', '.', '.'].iter())
        .chain(chars[chars.len() - right..].iter())
        .collect()
}

/// Re-serialize tool-call arguments as compact single-line JSON so the log does
/// not fragment across many lines. Falls back to the raw text (with internal
/// newlines collapsed to spaces) when it is not valid JSON.
fn compact_arguments(raw: &str) -> String {
    match serde_json::from_str::<Value>(raw) {
        Ok(parsed) => serde_json::to_string(&parsed).unwrap_or_else(|_| raw.to_string()),
        Err(_) => raw.split_whitespace().collect::<Vec<_>>().join(" "),
    }
}

fn number_at<'a>(value: Option<&'a Value>, keys: &[&str]) -> Option<&'a Value> {
    let value = value?;
    keys.iter()
        .find_map(|key| value.get(*key))
        .filter(|v| v.is_number())
}

fn stats_text(c: &Chat) -> String {
    let mut stats = vec![
        format!("ID: {}", c.id),
    ];
    if let Some(name) = c.name.as_ref() {
        stats.push(format!("Name: {name}"));
    }
    stats.push(format!("Model: {}", c.model));
    if let Some(backend) = c.backend.as_deref() {
        stats.push(format!("Backend: {backend}"));
    }
    stats.extend([
        format!("Finish: {}", c.finish.as_deref().unwrap_or("streaming")),
        format!("Chunks: {}", c.chunks),
        format!("Flow: {}", c.flow),
    ]);
    let tool_count = c
        .tool_calls
        .iter()
        .filter(|tc| !tc.id.is_empty() || !tc.name.is_empty() || !tc.arguments.is_empty())
        .count();
    if tool_count > 0 {
        stats.push(format!("Tool calls: {tool_count}"));
    }
    if let Some(usage) = c.usage.as_ref() {
        let prompt = number_at(Some(usage), &["prompt_tokens"]);
        let completion = number_at(Some(usage), &["completion_tokens"]);
        let total = number_at(Some(usage), &["total_tokens"]);
        if prompt.is_some() || completion.is_some() || total.is_some() {
            stats.push(format!(
                "Tokens: prompt {} | completion {} | total {}",
                prompt.map_or("?".into(), Value::to_string),
                completion.map_or("?".into(), Value::to_string),
                total.map_or("?".into(), Value::to_string),
            ));
        }
    }
    if let Some(timings) = c.timings.as_ref() {
        let predicted = number_at(
            Some(timings),
            &["predicted_per_second", "tokens_per_second"],
        );
        let prompt = number_at(Some(timings), &["prompt_per_second"]);
        if predicted.is_some() || prompt.is_some() {
            stats.push(format!(
                "Speed: generation {} tok/s | prompt {} tok/s",
                predicted.map_or("?".into(), Value::to_string),
                prompt.map_or("?".into(), Value::to_string),
            ));
        }
    }
    stats.join("\n")
}

fn extract_objects(buffer: &mut String) -> Vec<Value> {
    let mut out = vec![];
    let mut start = None;
    let mut depth = 0usize;
    let mut quoted = false;
    let mut escaped = false;
    let mut consumed = 0;
    for (i, b) in buffer.as_bytes().iter().copied().enumerate() {
        if start.is_none() {
            if b == b'{' {
                start = Some(i);
                depth = 1;
            }
            continue;
        }
        if quoted {
            if escaped {
                escaped = false
            } else if b == b'\\' {
                escaped = true
            } else if b == b'"' {
                quoted = false
            };
            continue;
        }
        match b {
            b'"' => quoted = true,
            b'{' => depth += 1,
            b'}' => {
                depth -= 1;
                if depth == 0 {
                    if let Ok(v) = serde_json::from_str(&buffer[start.unwrap()..=i]) {
                        out.push(v)
                    }
                    consumed = i + 1;
                    start = None;
                }
            }
            _ => {}
        }
    }
    *buffer = if let Some(i) = start {
        buffer[i..].to_owned()
    } else {
        buffer[consumed..]
            .chars()
            .rev()
            .take(4096)
            .collect::<String>()
            .chars()
            .rev()
            .collect()
    };
    out
}
fn request_text(request: Option<&Value>) -> String {
    let Some(r) = request else {
        return "(request began before capture)".into();
    };
    let mut out = String::new();
    if let Some(messages) = r.get("messages").and_then(Value::as_array) {
        for m in messages {
            let role = m.get("role").and_then(Value::as_str).unwrap_or("unknown");
            let content = m
                .get("content")
                .map(|v| {
                    v.as_str()
                        .map(str::to_owned)
                        .unwrap_or_else(|| serde_json::to_string_pretty(v).unwrap_or_default())
                })
                .unwrap_or_default();
            out.push_str(&format!("[{role}]\n{content}\n\n"));
        }
    } else {
        out = serde_json::to_string_pretty(r).unwrap_or_default()
    }
    out
}
fn tool_calls_text(c: &Chat) -> String {
    let mut out = String::new();
    for tc in &c.tool_calls {
        if tc.id.is_empty() && tc.name.is_empty() && tc.arguments.is_empty() {
            continue;
        }
        let name: &str = if tc.name.is_empty() { "function" } else { &tc.name };
        out.push_str(&format!("[{}] {name}\n", tc.id));
        let args = compact_arguments(&tc.arguments);
        if !args.is_empty() {
            out.push_str(&format!("    {args}\n"));
        }
    }
    out.trim_end().to_string()
}

fn render_chat(c: &Chat) -> String {
    let mut out = format!(
        "{}\n\n=== REQUEST ===\n{}\n=== REASONING ===\n{}\n\n=== ANSWER ===\n{}\n",
        stats_text(c),
        request_text(c.request.as_ref()),
        c.reasoning,
        c.answer
    );
    if !c.tool_calls.is_empty() {
        out.push_str(&format!("\n=== TOOL CALLS ===\n{}\n", tool_calls_text(c)));
    }
    out
}

fn body_section(out: &mut Vec<Line<'static>>, header: &str, text: &str, style: Style) {
    out.push(Line::from(Span::styled(
        header.to_string(),
        style.add_modifier(Modifier::BOLD),
    )));
    for l in text.lines() {
        out.push(Line::from(Span::styled(l.to_string(), style)));
    }
    out.push(Line::from(""));
}

fn render_body(c: &Chat) -> Text<'static> {
    let mut out: Vec<Line<'static>> = Vec::new();
    let default = Style::default();
    body_section(&mut out, "=== REQUEST ===", &request_text(c.request.as_ref()), default);
    body_section(&mut out, "=== REASONING ===", &c.reasoning, default);
    body_section(&mut out, "=== ANSWER ===", &c.answer, default);
    if !c.tool_calls.is_empty() {
        let orange = Style::default().fg(Color::Rgb(255, 165, 0));
        body_section(&mut out, "=== TOOL CALLS ===", &tool_calls_text(c), orange);
    }
    Text::from(out)
}

fn build_tab_line(items: &[(String, Style)], selected: usize, available: usize) -> Line<'static> {
    let n = items.len();
    if n == 0 {
        return Line::from(" no chats ");
    }
    let sep = " │ ";
    let sep_w = 3usize;
    let widths: Vec<usize> = items.iter().map(|(t, _)| t.chars().count()).collect();
    let ind_text = |count: usize| format!(" +{count}");
    let ind_width = |count: usize| ind_text(count).chars().count();
    let fits = |a: usize, b: usize| -> bool {
        let mut w = 0usize;
        if a > 0 {
            w += ind_width(a) + sep_w;
        }
        w += widths[a..b].iter().sum::<usize>();
        w += sep_w * (b - a - 1);
        if b < n {
            w += sep_w + ind_width(n - b);
        }
        w <= available
    };
    let sel = selected.min(n - 1);
    let mut a = sel;
    let mut b = sel + 1;
    while b < n && fits(a, b + 1) {
        b += 1;
    }
    while a > 0 && fits(a - 1, b) {
        a -= 1;
    }
    let dim = Style::default().fg(Color::DarkGray);
    let mut spans: Vec<Span> = Vec::new();
    if a > 0 {
        spans.push(Span::styled(ind_text(a), dim));
        spans.push(Span::raw(sep));
    }
    let sel_text = &items[sel].0;
    let mut first = true;
    for (text, style) in &items[a..b] {
        if !first {
            spans.push(Span::raw(sep));
        }
        first = false;
        let style = if text == sel_text {
            style
                .add_modifier(Modifier::BOLD)
                .add_modifier(Modifier::UNDERLINED)
        } else {
            *style
        };
        spans.push(Span::styled(text.clone(), style));
    }
    if b < n {
        spans.push(Span::raw(sep));
        spans.push(Span::styled(ind_text(n - b), dim));
    }
    Line::from(spans)
}

fn first_chars(s: &str, n: usize) -> String {
    s.chars().take(n).collect()
}
fn last_chars(s: &str, n: usize) -> String {
    s.chars().rev().take(n).collect::<Vec<_>>().into_iter().rev().collect()
}
fn name_prompt(c: &Chat) -> String {
    let first_user = c
        .request
        .as_ref()
        .and_then(|r| r.get("messages").and_then(Value::as_array))
        .and_then(|m| {
            m.iter()
                .find(|m| m.get("role").and_then(Value::as_str) == Some("user"))
                .and_then(|m| m.get("content").and_then(Value::as_str))
                .map(str::to_owned)
        })
        .map(|s| first_chars(&s, 100))
        .unwrap_or_default();
    let tail = last_chars(&c.answer, 1000);
    format!(
        "Name this chat conversation in 2-6 words. Reply with ONLY the name, no quotes, no trailing punctuation.\n\nFirst user message (first 100 chars):\n{first_user}\n\nEnd of conversation (last 1000 chars):\n{tail}"
    )
}
fn run_namer(model: &str, prompt: &str) -> Result<String, String> {
    let mut child = Command::new("ollama")
        .args(["run", "--nowordwrap", model])
        .stdin(Stdio::piped())
        .stdout(Stdio::piped())
        .stderr(Stdio::piped())
        .spawn()
        .map_err(|e| format!("spawn ollama: {e}"))?;
    if let Some(mut stdin) = child.stdin.take() {
        stdin
            .write_all(prompt.as_bytes())
            .map_err(|e| e.to_string())?;
    }
    let out = child.wait_with_output().map_err(|e| e.to_string())?;
    if !out.status.success() {
        return Err(String::from_utf8_lossy(&out.stderr).trim().to_string());
    }
    let text = String::from_utf8_lossy(&out.stdout);
    text.lines()
        .find(|l| !l.trim().is_empty())
        .map(|l| l.trim().to_string())
        .filter(|l| !l.is_empty())
        .ok_or_else(|| "empty model output".into())
}

fn spawn_ngrep(interface: &str) -> io::Result<(Child, Receiver<Packet>)> {
    let mut child = Command::new("pkexec")
        .arg("/usr/bin/ngrep")
        .args([
            "-q",
            "-l",
            "-u",
            "-d",
            interface,
            "-W",
            "byline",
            "",
            "tcp",
        ])
        .stdout(Stdio::piped())
        .spawn()?;
    let stdout = child.stdout.take().unwrap();
    let (tx, rx) = mpsc::channel();
    thread::spawn(move || {
        let mut header = String::new();
        let mut payload = String::new();
        for line in BufReader::new(stdout).lines().map_while(Result::ok) {
            if line == "####" {
                if !header.is_empty() {
                    let _ = tx.send(Packet {
                        header: std::mem::take(&mut header),
                        payload: std::mem::take(&mut payload),
                    });
                }
            } else if line.starts_with("T ") && line.contains(" -> ") {
                if !header.is_empty() {
                    let _ = tx.send(Packet { header, payload });
                }
                header = line;
                payload = String::new();
            } else {
                payload.push_str(&line);
                payload.push('\n');
            }
        }
        if !header.is_empty() {
            let _ = tx.send(Packet { header, payload });
        }
    });
    Ok((child, rx))
}

fn draw(frame: &mut ratatui::Frame, app: &mut App) {
    let areas = Layout::default()
        .direction(Direction::Vertical)
        .constraints([
            Constraint::Length(3),
            Constraint::Min(1),
            Constraint::Length(1),
        ])
        .split(frame.area());
    let tab_line = {
        let items: Vec<(String, Style)> = app
            .chats
            .iter()
            .map(|c| {
                let (marker, color) = match c.finish.as_deref() {
                    None => ("●", Color::Green),
                    Some("tool_calls") => ("✓", Color::DarkGray),
                    Some(_) => ("✓", Color::White),
                };
                let label = c.name.clone().unwrap_or_else(|| c.id.clone());
                (
                    format!(" {} {} ", middle_elide(&label, 24), marker),
                    Style::default().fg(color),
                )
            })
            .collect();
        build_tab_line(&items, app.selected, areas[0].width.saturating_sub(2) as usize)
    };
    frame.render_widget(
        Paragraph::new(tab_line).block(
            Block::default()
                .borders(Borders::ALL)
                .title(" llama.cpp conversations "),
        ),
        areas[0],
    );
    if let Some(c) = app.chats.get_mut(app.selected) {
        let stats = stats_text(c);
        let stats_height = stats
            .lines()
            .count()
            .saturating_add(2)
            .min(u16::MAX as usize) as u16;
        let details = Layout::default()
            .direction(Direction::Vertical)
            .constraints([Constraint::Length(stats_height), Constraint::Min(1)])
            .split(areas[1]);
        frame.render_widget(
            Paragraph::new(stats).block(Block::default().borders(Borders::ALL).title(" stats ")),
            details[0],
        );
        let body = render_body(c);
        let visible = details[1].height.saturating_sub(2) as usize;
        let max = body.height().saturating_sub(visible).min(u16::MAX as usize) as u16;
        if c.follow {
            c.scroll = max
        }
        frame.render_widget(
            Paragraph::new(body)
                .block(Block::default().borders(Borders::ALL).title(format!(
                    " {} | {} chunks | {} ",
                    c.model,
                    c.chunks,
                    c.finish.as_deref().unwrap_or("streaming")
                )))
                .wrap(Wrap { trim: false })
                .scroll((c.scroll, 0)),
            details[1],
        );
    } else {
        frame.render_widget(
            Paragraph::new("No conversations captured yet.")
                .block(Block::default().borders(Borders::ALL)),
            areas[1],
        );
    }
    let bottom = match app.rename.as_ref() {
        Some(buf) => Line::from(vec![
            Span::styled(
                " rename ",
                Style::default().fg(Color::Yellow).add_modifier(Modifier::BOLD),
            ),
            Span::raw(format!(" {buf} ")),
            Span::styled("│ Enter=save  Esc=cancel", Style::default().fg(Color::DarkGray)),
        ]),
        None => {
            let key = |k: &'static str| Span::styled(k, Style::default().fg(Color::Cyan));
            Line::from(vec![
                Span::raw(format!(" {}  ", app.status)),
                key("←/→"),
                Span::raw(" tabs "),
                key("↑/↓"),
                Span::raw(" scroll "),
                key("x"),
                Span::raw(" close "),
                key("d"),
                Span::raw(" dump "),
                key("a"),
                Span::raw(format!(" auto-clean:{} ", app.auto_clean.label())),
                key("r"),
                Span::raw(" rename "),
                key("R"),
                Span::raw(" name "),
                key("q"),
                Span::raw(" quit"),
            ])
        }
    };
    frame.render_widget(Paragraph::new(bottom), areas[2]);
}

fn restore(terminal: &mut Terminal<CrosstermBackend<io::Stdout>>) {
    let _ = disable_raw_mode();
    let _ = execute!(terminal.backend_mut(), LeaveAlternateScreen);
    let _ = terminal.show_cursor();
}
fn main() -> Result<(), Box<dyn std::error::Error>> {
    let args = env::args().collect::<Vec<_>>();
    if args.iter().any(|a| a == "-h" || a == "--help") {
        println!("Usage: sniff-llms [--interface any]");
        return Ok(());
    }
    let option = |n: &str, d: &str| {
        args.iter()
            .position(|a| a == n)
            .and_then(|i| args.get(i + 1))
            .cloned()
            .unwrap_or_else(|| d.into())
    };
    let interface = option("--interface", "any");
    let (mut capture, rx) = spawn_ngrep(&interface)?;
    enable_raw_mode()?;
    let mut stdout = io::stdout();
    execute!(stdout, EnterAlternateScreen)?;
    let mut terminal = Terminal::new(CrosstermBackend::new(stdout))?;
    let mut app = App::new();
    let (name_tx, name_rx) = mpsc::channel::<(String, Result<String, String>)>();
    let result = loop {
        while let Ok(p) = rx.try_recv() {
            app.packet(p)
        }
        while let Ok((id, res)) = name_rx.try_recv() {
            match res {
                Ok(name) => {
                    let name = name.trim().to_string();
                    if name.is_empty() {
                        app.status = "ai-name: empty result".into();
                    } else if let Some(c) = app.chats.iter_mut().find(|c| c.id == id) {
                        c.name = Some(name.clone());
                        app.status = format!("named → {name}");
                    } else {
                        app.status = "ai-name: chat no longer open".into();
                    }
                }
                Err(e) => app.status = format!("ai-name failed: {e}"),
            }
        }
        terminal.draw(|f| draw(f, &mut app))?;
        if event::poll(Duration::from_millis(33))?
            && let Event::Key(k) = event::read()?
        {
            if k.kind != KeyEventKind::Press {
                continue;
            }
            if app.rename.is_some() {
                match k.code {
                    KeyCode::Char(c) => {
                        if let Some(buf) = app.rename.as_mut() {
                            buf.push(c)
                        }
                    }
                    KeyCode::Backspace => {
                        if let Some(buf) = app.rename.as_mut() {
                            buf.pop();
                        }
                    }
                    KeyCode::Enter => app.rename_commit(),
                    KeyCode::Esc => {
                        app.rename = None;
                        app.status = "rename cancelled".into();
                    }
                    _ => {}
                }
                continue;
            }
            match k.code {
                KeyCode::Char('q') => break Ok(()),
                KeyCode::Left if !app.chats.is_empty() => {
                    app.selected = app.selected.checked_sub(1).unwrap_or(app.chats.len() - 1)
                }
                KeyCode::Right if !app.chats.is_empty() => {
                    app.selected = (app.selected + 1) % app.chats.len()
                }
                KeyCode::Up => {
                    if let Some(c) = app.chats.get_mut(app.selected) {
                        c.follow = false;
                        c.scroll = c.scroll.saturating_sub(1)
                    }
                }
                KeyCode::Down => {
                    if let Some(c) = app.chats.get_mut(app.selected) {
                        c.scroll = c.scroll.saturating_add(1)
                    }
                }
                KeyCode::End => {
                    if let Some(c) = app.chats.get_mut(app.selected) {
                        c.follow = true
                    }
                }
                KeyCode::Char('x') => app.close(),
                KeyCode::Char('d') => app.dump(),
                KeyCode::Char('a') => {
                    app.auto_clean = app.auto_clean.next();
                    app.status = format!("auto-clean: {}", app.auto_clean.label())
                }
                KeyCode::Char('r') => {
                    if app.chats.is_empty() {
                        app.status = "no chat to rename".into()
                    } else {
                        app.rename = Some(String::new());
                        app.status = "rename".into()
                    }
                }
                KeyCode::Char('R') => {
                    let Some(c) = app.chats.get(app.selected) else {
                        app.status = "no chat to name".into();
                        continue;
                    };
                    let prompt = name_prompt(c);
                    let id = c.id.clone();
                    let model = env::var("SNIFF_NAMER").unwrap_or_else(|_| "gemma4:e2b".into());
                    let tx = name_tx.clone();
                    app.status = format!("ai-naming with {model}…");
                    thread::spawn(move || {
                        let res = run_namer(&model, &prompt);
                        let _ = tx.send((id, res));
                    });
                }
                _ => {}
            }
        }
    };
    let _ = capture.kill();
    restore(&mut terminal);
    result
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::json;

    #[test]
    fn elides_the_middle_of_long_chat_ids() {
        assert_eq!(middle_elide("abcdefghijklmnopqrstuv", 11), "abcd...stuv");
        assert_eq!(middle_elide("short", 11), "short");
    }

    #[test]
    fn retains_usage_only_stream_chunks() {
        let mut app = App::new();
        app.flows
            .entry("client <-> server".into())
            .or_default()
            .requests
            .push(json!({
                "model": "qwen3.8",
                "messages": []
            }));
        app.response(
            "client <-> server",
            json!({
                "id": "chatcmpl-1234567890",
                "choices": [{"delta": {"content": "hello"}}]
            }),
        );
        app.response(
            "client <-> server",
            json!({
                "id": "chatcmpl-1234567890",
                "choices": [],
                "usage": {"prompt_tokens": 10, "completion_tokens": 2, "total_tokens": 12}
            }),
        );

        let chat = &app.chats[0];
        assert_eq!(chat.model, "qwen3.8");
        assert_eq!(chat.chunks, 2);
        assert!(stats_text(chat).contains("prompt 10 | completion 2 | total 12"));
    }

    #[test]
    fn detects_backend_from_response_markers() {
        assert_eq!(
            detect_backend(&json!({"timings": {"predicted_per_second": 1.0}})),
            Some("llama.cpp")
        );
        assert_eq!(
            detect_backend(
                &json!({"id": "c1", "choices": [], "prompt_eval_count": 10, "eval_count": 5})
            ),
            Some("ollama")
        );
        assert_eq!(
            detect_backend(&json!({"id": "gen-abc123", "choices": []})),
            Some("openrouter")
        );
        assert_eq!(
            detect_backend(&json!({"id": "msg_01abc", "type": "message"})),
            Some("anthropic")
        );
        assert_eq!(
            detect_backend(
                &json!({"id": "chatcmpl-1", "choices": [], "system_fingerprint": "abc"})
            ),
            None
        );
    }

    #[test]
    fn tab_bar_shows_overflow_indicators_and_keeps_selected_visible() {
        let style = Style::default();
        let items: Vec<(String, Style)> = (0..6).map(|i| (format!(" tab{i} ● "), style)).collect();
        let text = build_tab_line(&items, 3, 30).to_string();
        assert!(text.contains("tab3"), "selected tab must be visible: {text}");
        assert!(text.contains("+"), "overflow indicator expected: {text}");
    }

    #[test]
    fn tab_bar_fits_all_tabs_when_wide_enough() {
        let style = Style::default();
        let items: Vec<(String, Style)> = (0..3).map(|i| (format!(" t{i} ● "), style)).collect();
        let text = build_tab_line(&items, 1, 200).to_string();
        assert!(text.contains("t0") && text.contains("t1") && text.contains("t2"));
        assert!(!text.contains("+"), "no overflow expected: {text}");
    }

    #[test]
    fn auto_clean_closes_chats_matching_finish_reason() {
        let mut app = App::new();
        app.auto_clean = AutoClean::ToolCalls;
        app.response(
            "f",
            json!({"id": "c1", "choices": [{"delta": {"content": "hi"}, "finish_reason": "tool_calls"}]}),
        );
        assert!(app.chats.is_empty(), "chat should be auto-cleaned");
        assert!(app.ignored.contains("c1"));
    }

    #[test]
    fn auto_clean_off_keeps_finished_chats() {
        let mut app = App::new();
        app.auto_clean = AutoClean::Never;
        app.response(
            "f",
            json!({"id": "c1", "choices": [{"delta": {}, "finish_reason": "tool_calls"}]}),
        );
        assert_eq!(app.chats.len(), 1);
    }

    #[test]
    fn new_chats_do_not_steal_selection() {
        let mut app = App::new();
        app.response("f", json!({"id": "c1", "choices": [{"delta": {"content": "a"}}]}));
        app.response("f", json!({"id": "c2", "choices": [{"delta": {"content": "b"}}]}));
        assert_eq!(app.selected, 0, "selection should stay on the first chat");
        assert_eq!(app.chats.len(), 2);
    }

    #[test]
    fn concatenates_streamed_tool_call_argument_fragments() {
        let mut app = App::new();
        // Two deltas stream the same tool call's arguments in pieces.
        app.response(
            "f",
            json!({
                "id": "c1",
                "choices": [{"delta": {"tool_calls": [
                    {"index": 0, "id": "call_1", "function": {"name": "get_weather", "arguments": "{\"city\":"}}
                ]}}]
            }),
        );
        app.response(
            "f",
            json!({
                "id": "c1",
                "choices": [{"delta": {"tool_calls": [
                    {"index": 0, "function": {"arguments": "\"Paris\"}"}}
                ]}}]
            }),
        );
        let chat = &app.chats[0];
        assert_eq!(chat.tool_calls.len(), 1, "must be one call, not one line per fragment");
        assert_eq!(chat.tool_calls[0].id, "call_1");
        assert_eq!(chat.tool_calls[0].name, "get_weather");
        assert_eq!(chat.tool_calls[0].arguments, "{\"city\":\"Paris\"}");
        assert!(stats_text(chat).contains("Tool calls: 1"));
    }

    #[test]
    fn compacts_pretty_printed_tool_call_arguments() {
        let mut app = App::new();
        app.response(
            "f",
            json!({
                "id": "c1",
                "choices": [{"delta": {"tool_calls": [
                    {"index": 0, "id": "call_1",
                     "function": {"name": "read_file",
                                  "arguments": "{\n  \"path\": \"/tmp/agent-home/.local/share/agent/workspace\"\n}"}}
                ]}}]
            }),
        );
        let chat = &app.chats[0];
        let text = tool_calls_text(chat);
        let lines: Vec<&str> = text.lines().collect();
        // Pretty-printed arguments must collapse to a single compact line.
        let open_braces = lines.iter().filter(|l| l.trim_start().starts_with('{')).count();
        assert_eq!(open_braces, 1, "args should be one line: {lines:?}");
        assert!(!lines.iter().any(|l| l.trim() == "}"), "no orphaned brace: {lines:?}");
        assert!(text.contains("\"path\""));
        assert!(text.contains("/tmp/agent-home"));
    }

    #[test]
    fn rename_commit_sets_and_clears_name() {
        let mut app = App::new();
        app.response("f", json!({"id": "c1", "choices": [{"delta": {"content": "a"}}]}));
        app.rename = Some("my chat".into());
        app.rename_commit();
        assert_eq!(app.chats[0].name.as_deref(), Some("my chat"));
        app.rename = Some("   ".into());
        app.rename_commit();
        assert!(app.chats[0].name.is_none());
    }

    #[test]
    fn char_helpers() {
        assert_eq!(first_chars("abcdef", 3), "abc");
        assert_eq!(last_chars("abcdef", 3), "def");
        assert_eq!(last_chars("ab", 5), "ab");
    }

    #[test]
    fn classify_directions_by_http_and_json_shape() {
        assert_eq!(classify("HTTP/1.1 200 OK\r\ncontent-type: text/event-stream"), Some(Dir::Response));
        assert_eq!(classify("POST /v1/chat/completions HTTP/1.1"), Some(Dir::Request));
        assert_eq!(
            classify("data: {\"id\":\"c1\",\"choices\":[{\"delta\":{\"content\":\"hi\"}}]}"),
            Some(Dir::Response)
        );
        assert_eq!(
            classify("{\"model\":\"qwen\",\"messages\":[{\"role\":\"user\",\"content\":\"hi\"}]}"),
            Some(Dir::Request)
        );
        assert_eq!(classify("GET /index.html HTTP/1.1"), Some(Dir::Request));
        assert_eq!(classify("garbage that is not llm"), None);
    }

    #[test]
    fn llm_response_requires_id_and_body() {
        assert!(is_llm_response(&json!({"id":"c1","choices":[{"delta":{}}]})));
        assert!(is_llm_response(&json!({"id":"c1","choices":[],"usage":{}})));
        assert!(!is_llm_response(&json!({"choices":[{"delta":{}}]})), "missing id");
        assert!(!is_llm_response(&json!({"id":"c1","messages":[]})), "missing body");
    }

    #[test]
    fn prefilter_keeps_llm_traffic_only() {
        assert!(looks_like_llm("POST /v1/chat/completions HTTP/1.1"));
        assert!(looks_like_llm("{\"choices\":[],\"id\":\"c1\"}"));
        assert!(looks_like_llm("{\"messages\":[{\"role\":\"user\"}]}"));
        assert!(!looks_like_llm("GET /index.html HTTP/1.1"));
    }

    #[test]
    fn all_ports_packet_routes_by_content_not_port() {
        let mut app = App::new();
        // Request from client 5555 to server 8080 (no fixed port configured).
        app.packet(Packet {
            header: "T 192.168.1.50:5555 -> 192.168.1.50:8080".into(),
            payload: "{\"model\":\"qwen\",\"messages\":[{\"role\":\"user\",\"content\":\"hi\"}]}".into(),
        });
        // Response back from the same server endpoint.
        app.packet(Packet {
            header: "T 192.168.1.50:8080 -> 192.168.1.50:5555".into(),
            payload: "{\"id\":\"c1\",\"model\":\"qwen\",\"choices\":[{\"delta\":{\"content\":\"hello\"}}]}".into(),
        });
        assert_eq!(app.chats.len(), 1, "one chat expected");
        assert_eq!(app.chats[0].id, "c1");
        assert_eq!(app.chats[0].model, "qwen");
        // The non-LLM flow must not have been created.
        assert!(!app.flows.keys().any(|k| !k.contains("8080")), "no stray flows");
    }
}
