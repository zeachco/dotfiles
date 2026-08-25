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
    widgets::{Block, Borders, Paragraph, Tabs, Wrap},
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

#[derive(Default)]
struct Flow {
    request_buf: String,
    response_buf: String,
    requests: Vec<Value>,
}
struct Packet {
    header: String,
    payload: String,
}
struct Chat {
    id: String,
    model: String,
    flow: String,
    request: Option<Value>,
    reasoning: String,
    answer: String,
    finish: Option<String>,
    scroll: u16,
    follow: bool,
    chunks: usize,
}
struct App {
    port: u16,
    flows: HashMap<String, Flow>,
    chats: Vec<Chat>,
    selected: usize,
    ignored: HashSet<String>,
    status: String,
}

impl App {
    fn new(port: u16) -> Self {
        Self {
            port,
            flows: HashMap::new(),
            chats: vec![],
            selected: 0,
            ignored: HashSet::new(),
            status: "waiting for traffic".into(),
        }
    }
    fn packet(&mut self, packet: Packet) {
        let Some((src, dst)) = parse_header(&packet.header) else {
            return;
        };
        let response = endpoint_port(src) == Some(self.port);
        if !response && endpoint_port(dst) != Some(self.port) {
            return;
        }
        let mut endpoints = [src.to_owned(), dst.to_owned()];
        endpoints.sort();
        let key = endpoints.join(" <-> ");
        let objects = {
            let flow = self.flows.entry(key.clone()).or_default();
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
        let Some(id) = value.get("id").and_then(Value::as_str) else {
            return;
        };
        let Some(choice) = value.pointer("/choices/0") else {
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
                self.chats.push(Chat {
                    id: id.into(),
                    model: value
                        .get("model")
                        .and_then(Value::as_str)
                        .unwrap_or("unknown")
                        .into(),
                    flow: flow_key.into(),
                    request,
                    reasoning: String::new(),
                    answer: String::new(),
                    finish: None,
                    scroll: 0,
                    follow: true,
                    chunks: 0,
                });
                self.selected = self.chats.len() - 1;
                self.status = format!("following {id}");
                self.selected
            });
        let chat = &mut self.chats[index];
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
        if let Some(s) = choice.get("finish_reason").and_then(Value::as_str) {
            chat.finish = Some(s.into());
        }
        chat.chunks += 1;
    }
    fn close(&mut self) {
        if self.chats.is_empty() {
            return;
        }
        let chat = self.chats.remove(self.selected);
        self.ignored.insert(chat.id.clone());
        if let Some(flow) = self.flows.get_mut(&chat.flow) {
            flow.requests.clear();
            flow.request_buf.clear();
            flow.response_buf.clear();
        }
        self.selected = self.selected.min(self.chats.len().saturating_sub(1));
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
}

fn parse_header(s: &str) -> Option<(&str, &str)> {
    let mut p = s.split_whitespace();
    (p.next()? == "T").then_some(())?;
    let a = p.next()?;
    (p.next()? == "->").then_some(())?;
    Some((a, p.next()?))
}
fn endpoint_port(s: &str) -> Option<u16> {
    s.rsplit_once(':')?.1.parse().ok()
}
fn is_request(v: &Value) -> bool {
    v.get("messages").is_some_and(Value::is_array) || v.get("prompt").is_some_and(Value::is_string)
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
fn render_chat(c: &Chat) -> String {
    format!(
        "ID: {}\nModel: {}\nFinish: {}\nChunks: {}\nFlow: {}\n\n=== REQUEST ===\n{}\n=== REASONING ===\n{}\n\n=== ANSWER ===\n{}\n",
        c.id,
        c.model,
        c.finish.as_deref().unwrap_or("streaming"),
        c.chunks,
        c.flow,
        request_text(c.request.as_ref()),
        c.reasoning,
        c.answer
    )
}

fn spawn_ngrep(port: u16, interface: &str) -> io::Result<(Child, Receiver<Packet>)> {
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
            &format!("tcp port {port}"),
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
    let tabs = app
        .chats
        .iter()
        .map(|c| {
            Line::from(format!(
                " {} {} ",
                c.id,
                if c.finish.is_some() { "✓" } else { "●" }
            ))
        })
        .collect::<Vec<_>>();
    frame.render_widget(
        Tabs::new(tabs)
            .select(app.selected)
            .block(
                Block::default()
                    .borders(Borders::ALL)
                    .title(" llama.cpp conversations "),
            )
            .highlight_style(
                Style::default()
                    .fg(Color::Cyan)
                    .add_modifier(Modifier::BOLD),
            ),
        areas[0],
    );
    if let Some(c) = app.chats.get_mut(app.selected) {
        let body = render_chat(c);
        let visible = areas[1].height.saturating_sub(2) as usize;
        let max = Text::from(body.as_str())
            .height()
            .saturating_sub(visible)
            .min(u16::MAX as usize) as u16;
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
            areas[1],
        );
    } else {
        frame.render_widget(
            Paragraph::new("No conversations captured yet.")
                .block(Block::default().borders(Borders::ALL)),
            areas[1],
        );
    }
    frame.render_widget(
        Paragraph::new(Line::from(vec![
            Span::styled("←/→", Style::default().fg(Color::Cyan)),
            Span::raw(" tabs  "),
            Span::styled("↑/↓", Style::default().fg(Color::Cyan)),
            Span::raw(" scroll  "),
            Span::styled("x", Style::default().fg(Color::Cyan)),
            Span::raw(" close/forget  "),
            Span::styled("d", Style::default().fg(Color::Cyan)),
            Span::raw(" dump  "),
            Span::styled("q", Style::default().fg(Color::Cyan)),
            Span::raw(format!(" quit  | {}", app.status)),
        ])),
        areas[2],
    );
}

fn restore(terminal: &mut Terminal<CrosstermBackend<io::Stdout>>) {
    let _ = disable_raw_mode();
    let _ = execute!(terminal.backend_mut(), LeaveAlternateScreen);
    let _ = terminal.show_cursor();
}
fn main() -> Result<(), Box<dyn std::error::Error>> {
    let args = env::args().collect::<Vec<_>>();
    if args.iter().any(|a| a == "-h" || a == "--help") {
        println!("Usage: sniff-llms [--port 8080] [--interface any]");
        return Ok(());
    }
    let option = |n: &str, d: &str| {
        args.iter()
            .position(|a| a == n)
            .and_then(|i| args.get(i + 1))
            .cloned()
            .unwrap_or_else(|| d.into())
    };
    let port: u16 = option("--port", "8080").parse()?;
    let interface = option("--interface", "any");
    let (mut capture, rx) = spawn_ngrep(port, &interface)?;
    enable_raw_mode()?;
    let mut stdout = io::stdout();
    execute!(stdout, EnterAlternateScreen)?;
    let mut terminal = Terminal::new(CrosstermBackend::new(stdout))?;
    let mut app = App::new(port);
    let result = loop {
        while let Ok(p) = rx.try_recv() {
            app.packet(p)
        }
        terminal.draw(|f| draw(f, &mut app))?;
        if event::poll(Duration::from_millis(33))? {
            if let Event::Key(k) = event::read()? {
                if k.kind != KeyEventKind::Press {
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
                    _ => {}
                }
            }
        }
    };
    let _ = capture.kill();
    restore(&mut terminal);
    result
}
