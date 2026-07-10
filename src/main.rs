mod config;
mod install;
mod model;
mod platform;
mod shell;

use config::{
    load_effective_profile, load_profile, load_shell, load_state, save_state, state_path,
};
use install::{capture, prompt, run};
use model::{Platform, State};
use std::fs;
use std::path::PathBuf;
use std::process::Command;

fn main() {
    restore_sigpipe();
    if let Err(error) = real_main() {
        eprintln!("dotfiles: {error}");
        std::process::exit(1);
    }
}

#[cfg(unix)]
fn restore_sigpipe() {
    unsafe extern "C" {
        fn signal(signal: i32, handler: usize) -> usize;
    }
    // Rust ignores SIGPIPE by default, which turns ordinary short pipelines
    // into noisy panics. All supported targets use signal 13 for SIGPIPE.
    unsafe {
        signal(13, 0);
    }
}

#[cfg(not(unix))]
fn restore_sigpipe() {}

fn real_main() -> Result<(), String> {
    let args: Vec<String> = std::env::args().skip(1).collect();
    let command = args.first().map(String::as_str).unwrap_or("help");
    let tail = args.get(1..).unwrap_or(&[]);
    match command {
        "plan" => plan(false, feature_override(tail)?),
        "apply" | "install" => apply(tail.iter().any(|a| a == "--yes"), feature_override(tail)?),
        "features" => features(tail),
        "doctor" => doctor(),
        "update" => update(tail.iter().any(|a| a == "--yes")),
        "util" => util(tail),
        "worktree" => worktree(tail),
        "shell" => shell_command(tail),
        "help" | "--help" | "-h" => {
            help();
            Ok(())
        }
        "version" | "--version" | "-V" => {
            println!("dotfiles {}", env!("CARGO_PKG_VERSION"));
            Ok(())
        }
        other => Err(format!("unknown command '{other}'; run 'dotfiles help'")),
    }
}

fn context(
    interactive_features: bool,
    requested_features: Option<Vec<String>>,
) -> Result<(PathBuf, Platform, String, Vec<String>), String> {
    let existing = load_state().ok();
    let repo = locate_repo(existing.as_ref())?;
    let detected = platform::detect()?;
    let profile_name = detected.profile().to_string();
    let profile = load_effective_profile(&repo, &profile_name)?;
    let shell = platform::default_shell(detected)?;
    let features = if let Some(requested) = requested_features {
        requested
    } else if let Some(state) =
        existing.filter(|s| s.profile == profile_name && !s.features.is_empty())
    {
        state.features
    } else if interactive_features {
        choose_features(
            &profile.default_features,
            profile.features.keys().cloned().collect(),
        )?
    } else {
        profile.default_features.clone()
    };
    Ok((repo, detected, shell, features))
}

fn plan(interactive: bool, requested_features: Option<Vec<String>>) -> Result<(), String> {
    let (repo, platform, shell_name, features) = context(interactive, requested_features)?;
    let profile = load_effective_profile(&repo, platform.profile())?;
    let selected = profile.selected(&features)?;
    println!(
        "Platform: {}{}",
        platform.profile(),
        if platform::is_wsl() { " (WSL)" } else { "" }
    );
    println!("Default shell: {shell_name}");
    println!("Features: {}", features.join(", "));
    println!("Repository: {}", repo.display());
    println!("\nPlan:");
    for line in install::describe(platform, &selected, &shell_name) {
        println!("  - {line}");
    }
    Ok(())
}

fn apply(assume_yes: bool, requested_features: Option<Vec<String>>) -> Result<(), String> {
    let (repo, platform, shell_name, features) = context(!assume_yes, requested_features)?;
    let profile = load_effective_profile(&repo, platform.profile())?;
    let selected = profile.selected(&features)?;
    println!(
        "Platform: {}, shell: {}, features: {}",
        platform.profile(),
        shell_name,
        features.join(", ")
    );
    let actions = install::describe(platform, &selected, &shell_name);
    for line in &actions {
        println!("  - {line}");
    }
    if !assume_yes {
        let answer = prompt("Apply this plan? [y/N] ")?;
        if !matches!(answer.to_ascii_lowercase().as_str(), "y" | "yes") {
            println!("Cancelled.");
            return Ok(());
        }
    }
    install::ensure_package_manager(platform)?;
    install::install_packages(platform, &selected)?;
    install::apply_actions(platform, &selected.actions, &repo, assume_yes)?;
    if let Some(path) = install::stow(&repo, &selected.stow)? {
        println!("Conflicts backed up to {}", path.display());
    }
    let shell_manifest = load_shell(&repo, platform.profile())?;
    let rendered = shell::render(&shell_name, &shell_manifest, &repo)?;
    for path in shell::install(&shell_name, &rendered)? {
        println!("wrote {}", path.display());
    }
    save_state(&State {
        repo,
        profile: platform.profile().into(),
        shell: shell_name,
        features,
    })?;
    println!("Dotfiles applied. Start a new shell to load the generated adapter.");
    Ok(())
}

fn features(args: &[String]) -> Result<(), String> {
    let mut state = load_state()?;
    let profile = load_profile(&state.repo, &state.profile)?;
    if args.is_empty() {
        println!("Available features:");
        for name in profile.features.keys() {
            let selected = if state.features.contains(name) {
                "*"
            } else {
                " "
            };
            println!("  [{selected}] {name}");
        }
        return Ok(());
    }
    profile.selected(args)?;
    state.features = args.to_vec();
    save_state(&state)?;
    println!("Saved features: {}", args.join(", "));
    println!("Run 'dotfiles apply' to reconcile the machine.");
    Ok(())
}

fn doctor() -> Result<(), String> {
    let state = load_state().ok();
    let repo = locate_repo(state.as_ref())?;
    let platform = platform::detect()?;
    let shell_name = platform::default_shell(platform)?;
    let mut failed = false;
    check("repository", repo.join("Cargo.toml").is_file(), &mut failed);
    check(
        "profile manifest",
        load_effective_profile(&repo, platform.profile()).is_ok(),
        &mut failed,
    );
    check(
        "shell manifest",
        load_shell(&repo, platform.profile()).is_ok(),
        &mut failed,
    );
    check("GNU Stow", install::command_exists("stow"), &mut failed);
    check("Git", install::command_exists("git"), &mut failed);
    check(
        "default shell supported",
        ["bash", "zsh", "fish"].contains(&shell_name.as_str()),
        &mut failed,
    );
    check(
        "generated adapter",
        shell::generated_path(&shell_name).is_file(),
        &mut failed,
    );
    let identity =
        capture(Command::new("git").args(["config", "--global", "user.email"])).unwrap_or_default();
    check("Git identity", identity.trim().contains('@'), &mut failed);
    if let Some(state) = state {
        check("saved repository exists", state.repo.is_dir(), &mut failed);
        println!("  state: {}", state_path().display());
    } else {
        println!("  WARN state: not created yet");
        failed = true;
    }
    if failed {
        Err("doctor found problems".into())
    } else {
        println!("All checks passed.");
        Ok(())
    }
}

fn update(assume_yes: bool) -> Result<(), String> {
    let state = load_state()?;
    let dirty = capture(
        Command::new("git")
            .current_dir(&state.repo)
            .args(["status", "--porcelain"]),
    )?;
    if !dirty.trim().is_empty() {
        return Err("repository has local changes; commit or stash them before updating".into());
    }
    run(Command::new("git")
        .current_dir(&state.repo)
        .args(["pull", "--ff-only"]))?;
    run(Command::new("cargo")
        .current_dir(&state.repo)
        .args(["build", "--release", "--locked"]))?;
    let built = state.repo.join("target/release/dotfiles");
    let current = std::env::current_exe().map_err(|e| e.to_string())?;
    if fs::canonicalize(&built).ok() != fs::canonicalize(&current).ok() {
        let temp = current.with_extension("new");
        fs::copy(&built, &temp).map_err(|e| format!("{}: {e}", temp.display()))?;
        fs::rename(&temp, &current).map_err(|e| format!("{}: {e}", current.display()))?;
    }
    let mut command = Command::new(&current);
    command.arg("apply");
    if assume_yes {
        command.arg("--yes");
    }
    run(&mut command)
}

fn util(args: &[String]) -> Result<(), String> {
    let Some(command) = args.first().map(String::as_str) else {
        return Err("usage: dotfiles util <killport|ipp|ipl|docker|dockersh>".into());
    };
    match command {
        "killport" => {
            let port = args.get(1).ok_or("usage: killport <port>")?;
            let pids = capture(
                Command::new("lsof")
                    .arg(format!("-tiTCP:{port}"))
                    .arg("-sTCP:LISTEN"),
            )?;
            for pid in pids.lines().filter(|v| !v.is_empty()) {
                run(Command::new("kill").args(["-9", pid]))?;
            }
            Ok(())
        }
        "ipp" => run(Command::new("curl").args(["-fsSL", "https://ifconfig.me"])),
        "ipl" => run(Command::new("hostname").arg("-I")),
        "dockersh" => {
            let image = args.get(1).ok_or("usage: dockersh <image>")?;
            run(Command::new("docker").args(["run", "-it", "--entrypoint", "sh", image]))
        }
        "docker" => {
            if cfg!(target_os = "macos")
                && Command::new("docker")
                    .arg("version")
                    .status()
                    .map(|s| !s.success())
                    .unwrap_or(true)
            {
                run(Command::new("colima").arg("start"))?;
            }
            run(Command::new("docker").args(&args[1..]))
        }
        "rho" | "rhu" => {
            let remote = if command == "rho" {
                "origin"
            } else {
                "upstream"
            };
            run(Command::new("git").args(["fetch", remote]))?;
            let branch = capture(Command::new("git").args(["branch", "--show-current"]))?
                .trim()
                .to_string();
            if branch.is_empty() {
                return Err("not on a branch".into());
            }
            run(Command::new("git").args(["reset", "--hard", &format!("{remote}/{branch}")]))
        }
        "npmv" => {
            let version = args.get(1).ok_or("usage: npmv <version>")?;
            run(Command::new("npm").args(["version", version]))?;
            run(Command::new("git").args(["push", "--follow-tags"]))?;
            run(Command::new("npm").arg("publish"))
        }
        "pacin" => {
            let package = args.get(1).ok_or("usage: pacin <package>")?;
            if install::command_exists("yay") {
                run(Command::new("yay").args(["-S", "--noconfirm", package]))
            } else {
                run(Command::new("sudo").args(["pacman", "-S", "--needed", "--noconfirm", package]))
            }
        }
        "zapt" => {
            if let Some(package) = args.get(1) {
                run(Command::new("sudo").args(["apt-get", "install", package]))
            } else {
                interactive_packages(
                    "apt-cache",
                    &["pkgnames"],
                    "sudo",
                    &["apt-get", "install"],
                )
            }
        }
        "dark" => {
            let enabled = args.get(1).map(String::as_str).unwrap_or("true");
            run(Command::new("osascript").args(["-e", &format!("tell application \"System Events\" to tell appearance preferences to set dark mode to {enabled}")]))
        }
        "xcode-reinstall" => {
            let path = capture(Command::new("xcode-select").arg("-print-path"))?;
            run(Command::new("sudo").args(["rm", "-rf", path.trim()]))?;
            run(Command::new("xcode-select").arg("--install"))
        }
        "empty-trash" => {
            if install::command_exists("gio") {
                run(Command::new("gio").args(["trash", "--empty"]))
            } else {
                Err("safe trash emptying requires gio".into())
            }
        }
        "gcommits" => {
            if let Some(count) = args.get(1) {
                run(Command::new("git").args(["log", "--format=%H", "-n", count]))
            } else {
                run(Command::new("git").args([
                    "log",
                    "--format=%C(auto)%h (%s, %ad)",
                    "-n",
                    "20",
                ]))
            }
        }
        "use" => {
            println!("\x1b[0;34m( {} )\x1b[0m", args[1..].join(" "));
            Ok(())
        }
        "killname" => kill_name(args.get(1).ok_or("usage: killname <name>")?),
        "node-admin" => node_admin(),
        "bwload" => bwload(),
        "git-test" => git_test(args),
        "codeai" => code_ai(args),
        "speakai" => speak_ai(args),
        "pie-score" => {
            let output = capture_with_input(
                Command::new("ollama").args(["run", "mistral"]),
                "Generate a PIE score by listing Physical, Intellectual and Emotional scores with a casual reason for each.\n",
            )?;
            print!("{output}");
            Ok(())
        }
        "check-devbox" => check_devbox(),
        "termux-backup" => termux_backup(),
        "pacbig" => run(Command::new("sh").args(["-c", "pacman -Qi | awk '/^Name/{name=$3} /^Installed Size/{print $4$5, name}' | sort -h | tail -20"])),
        "mirrorup" => run(Command::new("sudo").args(["reflector", "--latest", "20", "--protocol", "https", "--sort", "rate", "--save", "/etc/pacman.d/mirrorlist"])),
        "paci" => interactive_packages("pacman", &["-Slq"], "sudo", &["pacman", "-S", "--needed", "--noconfirm"]),
        "yayi" => interactive_packages("yay", &["-Slq"], "yay", &["-S", "--noconfirm"]),
        other => Err(format!("unknown utility '{other}'")),
    }
}

fn kill_name(name: &str) -> Result<(), String> {
    let output = Command::new("pgrep")
        .args(["-f", name])
        .output()
        .map_err(|e| e.to_string())?;
    let current_pid = std::process::id().to_string();
    for pid in String::from_utf8_lossy(&output.stdout).lines() {
        if pid == current_pid {
            continue;
        }
        let answer = prompt(&format!("Kill process {pid} matching '{name}'? [y/N] "))?;
        if matches!(answer.to_ascii_lowercase().as_str(), "y" | "yes") {
            run(Command::new("kill").args(["-9", pid]))?;
        }
    }
    Ok(())
}

fn node_admin() -> Result<(), String> {
    let node = capture(Command::new("sh").args(["-c", "command -v node"]))?;
    run(Command::new("sudo").args(["setcap", "cap_net_bind_service=+ep", node.trim()]))?;
    run(Command::new("sudo").args(["sysctl", "-w", "fs.inotify.max_user_watches=524288"]))
}

fn bwload() -> Result<(), String> {
    let template = [".env.example", "example.env", ".env.bw"]
        .into_iter()
        .find(|path| PathBuf::from(path).is_file())
        .ok_or("no .env.example, example.env, or .env.bw found")?;
    let text = fs::read_to_string(template).map_err(|e| e.to_string())?;
    let start = text
        .find('"')
        .ok_or("environment template has no quoted Bitwarden item")?
        + 1;
    let end = text[start..]
        .find('"')
        .map(|index| start + index)
        .ok_or("environment template has an unterminated item name")?;
    run(Command::new("bw").arg("sync"))?;
    let notes = capture(Command::new("bw").args(["get", "notes", &text[start..end]]))?;
    fs::write(".env", notes).map_err(|e| e.to_string())?;
    println!("Created .env from Bitwarden item {}", &text[start..end]);
    Ok(())
}

fn git_test(args: &[String]) -> Result<(), String> {
    let filter = args.get(1).map(String::as_str).unwrap_or("test.ts");
    let changed = capture(Command::new("git").args(["diff", "origin/main", "--name-only"]))?;
    let candidates = changed
        .lines()
        .filter(|line| line.contains(filter))
        .collect::<Vec<_>>()
        .join("\n");
    if candidates.is_empty() {
        return Err(format!("no changed files match '{filter}'"));
    }
    let selected = capture_with_input(Command::new("fzf").arg("-m"), &(candidates + "\n"))?;
    let files = selected.lines().collect::<Vec<_>>();
    if files.is_empty() {
        return Ok(());
    }
    let mut command = Command::new("npx");
    command.args(["jest", "--watch"]);
    command.args(files);
    run(&mut command)
}

fn code_ai(args: &[String]) -> Result<(), String> {
    let file = args.get(1).ok_or("usage: codeai <file> <prompt>")?;
    let request = args
        .get(2..)
        .ok_or("usage: codeai <file> <prompt>")?
        .join(" ");
    if request.is_empty() {
        return Err("usage: codeai <file> <prompt>".into());
    }
    let content = fs::read_to_string(file).map_err(|e| e.to_string())?;
    let prompt = format!("Rewrite this file to satisfy: {request}\n\n```\n{content}\n```\n");
    let output = capture_with_input(
        Command::new("ollama").args(["run", "codellama:13b"]),
        &prompt,
    )?;
    fs::write(file, output).map_err(|e| e.to_string())
}

fn speak_ai(args: &[String]) -> Result<(), String> {
    let prompt = args.get(1..).ok_or("usage: speakai <prompt>")?.join(" ");
    if prompt.is_empty() {
        return Err("usage: speakai <prompt>".into());
    }
    let answer = capture_with_input(
        Command::new("ollama").args(["run", "mistral"]),
        &(prompt + "\n"),
    )?;
    run_with_input(
        Command::new("espeak").args(["-s150", "-g4", "-p55", "-a", "200"]),
        &answer,
    )
}

fn check_devbox() -> Result<(), String> {
    if !PathBuf::from("devbox.json").is_file() {
        return Ok(());
    }
    if !install::command_exists("devbox") {
        return Err("devbox.json found but devbox is not installed".into());
    }
    run(Command::new("devbox").arg("shell"))
}

fn termux_backup() -> Result<(), String> {
    let timestamp = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .map_err(|e| e.to_string())?
        .as_secs();
    let destination = config::home().join(format!("termux-backup-{timestamp}.tar.gz"));
    let mut command = Command::new("tar");
    command.arg("-czf").arg(&destination);
    for path in [".termux", "dotfiles", ".config"] {
        if config::home().join(path).exists() {
            command.arg("-C").arg(config::home()).arg(path);
        }
    }
    run(&mut command)?;
    println!("Created {}", destination.display());
    Ok(())
}

fn interactive_packages(
    list_command: &str,
    list_args: &[&str],
    install_command: &str,
    install_args: &[&str],
) -> Result<(), String> {
    let packages = capture(Command::new(list_command).args(list_args))?;
    let selected = capture_with_input(Command::new("fzf").arg("-m"), &packages)?;
    let names = selected
        .lines()
        .filter(|line| !line.is_empty())
        .collect::<Vec<_>>();
    if names.is_empty() {
        return Ok(());
    }
    let mut command = Command::new(install_command);
    command.args(install_args);
    command.args(names);
    run(&mut command)
}

fn capture_with_input(command: &mut Command, input: &str) -> Result<String, String> {
    use std::io::Write;
    use std::process::Stdio;
    let mut child = command
        .stdin(Stdio::piped())
        .stdout(Stdio::piped())
        .spawn()
        .map_err(|e| e.to_string())?;
    child
        .stdin
        .take()
        .unwrap()
        .write_all(input.as_bytes())
        .map_err(|e| e.to_string())?;
    let output = child.wait_with_output().map_err(|e| e.to_string())?;
    if output.status.success() {
        Ok(String::from_utf8_lossy(&output.stdout).into_owned())
    } else {
        Err(format!("command failed: {}", output.status))
    }
}

fn run_with_input(command: &mut Command, input: &str) -> Result<(), String> {
    capture_with_input(command, input).map(|_| ())
}

fn shell_command(args: &[String]) -> Result<(), String> {
    if args.first().map(String::as_str) != Some("render") {
        return Err("usage: dotfiles shell render <bash|zsh|fish> [profile]".into());
    }
    let shell_name = args.get(1).ok_or("missing shell name")?;
    let state = load_state().ok();
    let repo = locate_repo(state.as_ref())?;
    let profile = args
        .get(2)
        .cloned()
        .unwrap_or(platform::detect()?.profile().into());
    let manifest = load_shell(&repo, &profile)?;
    print!("{}", shell::render(shell_name, &manifest, &repo)?);
    Ok(())
}

fn worktree(args: &[String]) -> Result<(), String> {
    let Some(command) = args.first().map(String::as_str) else {
        return Err("usage: dotfiles worktree <open|delete|delete-all|jira>".into());
    };
    match command {
        "open" => worktree_open(args.get(1).map(String::as_str).unwrap_or("main")),
        "delete" => worktree_delete(),
        "delete-all" => worktree_delete_all(),
        "jira" => worktree_jira(args),
        other => Err(format!("unknown worktree command '{other}'")),
    }
}

fn worktree_open(branch: &str) -> Result<(), String> {
    worktree_open_with(branch, "devbox shell")
}

fn worktree_open_with(branch: &str, right_command: &str) -> Result<(), String> {
    let root = git_root()?;
    let repo_name = root
        .file_name()
        .and_then(|v| v.to_str())
        .ok_or("invalid repository name")?;
    let target = if ["main", "master"].contains(&branch) {
        root.clone()
    } else {
        config::home()
            .join("worktrees")
            .join(repo_name)
            .join(branch)
    };
    if target != root && !target.exists() {
        if let Some(parent) = target.parent() {
            fs::create_dir_all(parent).map_err(|e| e.to_string())?;
        }
        let exists = Command::new("git")
            .current_dir(&root)
            .args([
                "show-ref",
                "--verify",
                "--quiet",
                &format!("refs/heads/{branch}"),
            ])
            .status()
            .map(|s| s.success())
            .unwrap_or(false);
        let remote_exists = Command::new("git")
            .current_dir(&root)
            .args([
                "show-ref",
                "--verify",
                "--quiet",
                &format!("refs/remotes/origin/{branch}"),
            ])
            .status()
            .map(|status| status.success())
            .unwrap_or(false);
        let mut command = Command::new("git");
        command.current_dir(&root).args(["worktree", "add"]);
        if exists {
            command.arg(&target).arg(branch);
        } else if remote_exists {
            command
                .args(["--track", "-b", branch])
                .arg(&target)
                .arg(format!("origin/{branch}"));
        } else {
            command.args(["-b", branch]).arg(&target);
        }
        run(&mut command)?;
    }
    if std::env::var_os("ZELLIJ").is_some() {
        run(Command::new("zellij").args([
            "action",
            "new-tab",
            "--name",
            &format!("{repo_name}:{branch}"),
        ]))?;
        run(Command::new("zellij").args([
            "action",
            "write-chars",
            &format!("cd {} && nvim .", shell_argument(&target.to_string_lossy())),
        ]))?;
        run(Command::new("zellij").args(["action", "write", "13"]))?;
        run(Command::new("zellij").args(["action", "new-pane", "--direction", "right"]))?;
        run(Command::new("zellij").args([
            "action",
            "write-chars",
            &format!(
                "cd {} && {right_command}",
                shell_argument(&target.to_string_lossy())
            ),
        ]))?;
        run(Command::new("zellij").args(["action", "write", "13"]))?;
        run(Command::new("zellij").args(["action", "move-focus", "left"]))?;
    } else {
        println!("Worktree ready at {}", target.display());
    }
    Ok(())
}

fn worktree_jira(args: &[String]) -> Result<(), String> {
    let input = args
        .get(1)
        .ok_or("usage: jc <JIRA-ticket-or-PR-url> [keyword]")?;
    if input.contains("github.com/") && input.contains("/pull/") {
        let branch = capture(Command::new("gh").args([
            "pr",
            "view",
            input,
            "--json",
            "headRefName",
            "--jq",
            ".headRefName",
        ]))?
        .trim()
        .to_string();
        if branch.is_empty() {
            return Err("could not determine the pull request branch".into());
        }
        return worktree_open_with(&branch, "echo 'Ready to work on PR'");
    }
    let ticket = input
        .trim_end_matches('/')
        .rsplit('/')
        .next()
        .unwrap_or(input)
        .to_ascii_uppercase();
    let (project, number) = ticket
        .split_once('-')
        .ok_or("JIRA ticket must look like PROJECT-123")?;
    if project.is_empty()
        || !project.chars().all(|ch| ch.is_ascii_alphanumeric())
        || number.parse::<u64>().is_err()
    {
        return Err("JIRA ticket must look like PROJECT-123".into());
    }
    let branch = if let Some(keyword) = args.get(2) {
        format!("{ticket}-{keyword}")
    } else {
        ticket.clone()
    };
    let prompt = format!("Please fetch the details for JIRA ticket {ticket} and create a plan to implement it. If devbox.json exists, use devbox for project commands.");
    worktree_open_with(
        &branch,
        &format!(
            "claude --dangerously-skip-permissions {}",
            shell_argument(&prompt)
        ),
    )
}

fn shell_argument(value: &str) -> String {
    format!("'{}'", value.replace("'", "'\\''"))
}

fn worktree_delete() -> Result<(), String> {
    let root = git_root()?;
    let main =
        capture(
            Command::new("git")
                .current_dir(&root)
                .args(["worktree", "list", "--porcelain"]),
        )?
        .lines()
        .find_map(|line| line.strip_prefix("worktree "))
        .ok_or("no main worktree")?
        .to_string();
    if root == PathBuf::from(&main) {
        return Err("refusing to remove the main worktree".into());
    }
    let branch = capture(
        Command::new("git")
            .current_dir(&root)
            .args(["branch", "--show-current"]),
    )?
    .trim()
    .to_string();
    run(Command::new("git").current_dir(&main).args([
        "worktree",
        "remove",
        "--force",
        root.to_str().unwrap(),
    ]))?;
    if !branch.is_empty() {
        run(Command::new("git")
            .current_dir(&main)
            .args(["branch", "-D", &branch]))?;
    }
    Ok(())
}

fn worktree_delete_all() -> Result<(), String> {
    let root = git_root()?;
    let listing =
        capture(
            Command::new("git")
                .current_dir(&root)
                .args(["worktree", "list", "--porcelain"]),
        )?;
    let paths: Vec<_> = listing
        .lines()
        .filter_map(|line| line.strip_prefix("worktree "))
        .map(str::to_string)
        .collect();
    if paths.len() <= 1 {
        println!("No linked worktrees to remove.");
        return Ok(());
    }
    let answer = prompt(&format!(
        "Remove {} linked worktree(s)? [y/N] ",
        paths.len() - 1
    ))?;
    if !matches!(answer.to_ascii_lowercase().as_str(), "y" | "yes") {
        println!("Cancelled.");
        return Ok(());
    }
    for path in paths.iter().skip(1) {
        run(Command::new("git")
            .current_dir(&root)
            .args(["worktree", "remove", "--force", path]))?;
    }
    run(Command::new("git")
        .current_dir(&root)
        .args(["worktree", "prune"]))
}

fn git_root() -> Result<PathBuf, String> {
    Ok(PathBuf::from(
        capture(Command::new("git").args(["rev-parse", "--show-toplevel"]))?.trim(),
    ))
}

fn choose_features(defaults: &[String], all: Vec<String>) -> Result<Vec<String>, String> {
    println!("Available feature groups: {}", all.join(", "));
    let answer = prompt(&format!("Features [{}]: ", defaults.join(",")))?;
    if answer.is_empty() {
        Ok(defaults.to_vec())
    } else {
        Ok(answer
            .split(',')
            .map(|v| v.trim().to_string())
            .filter(|v| !v.is_empty())
            .collect())
    }
}

fn feature_override(args: &[String]) -> Result<Option<Vec<String>>, String> {
    for (index, arg) in args.iter().enumerate() {
        let value = if let Some(value) = arg.strip_prefix("--features=") {
            Some(value)
        } else if arg == "--features" {
            Some(
                args.get(index + 1)
                    .ok_or("--features requires a comma-separated value")?
                    .as_str(),
            )
        } else {
            None
        };
        if let Some(value) = value {
            let parsed = value
                .split(',')
                .map(str::trim)
                .filter(|value| !value.is_empty())
                .map(str::to_string)
                .collect::<Vec<_>>();
            if parsed.is_empty() {
                return Err("--features cannot be empty".into());
            }
            return Ok(Some(parsed));
        }
    }
    Ok(None)
}

fn locate_repo(state: Option<&State>) -> Result<PathBuf, String> {
    if let Some(value) = std::env::var_os("DOTFILES_ROOT") {
        let path = PathBuf::from(value);
        if path.join("Cargo.toml").is_file() {
            return Ok(path);
        }
    }
    let current = std::env::current_dir().map_err(|e| e.to_string())?;
    if current.join("Cargo.toml").is_file() {
        return Ok(current);
    }
    if let Some(state) = state {
        if state.repo.join("Cargo.toml").is_file() {
            return Ok(state.repo.clone());
        }
    }
    let conventional = config::home().join("dotfiles");
    if conventional.join("Cargo.toml").is_file() {
        return Ok(conventional);
    }
    Err("could not locate dotfiles repository; run from the checkout or set DOTFILES_ROOT".into())
}

fn check(name: &str, okay: bool, failed: &mut bool) {
    println!("  {:4} {name}", if okay { "OK" } else { "FAIL" });
    if !okay {
        *failed = true;
    }
}

fn help() {
    println!("dotfiles - shell-neutral machine configuration\n\nCommands:\n  plan [--features F]             Preview changes\n  apply [--yes] [--features F]    Reconcile the machine\n  features [NAMES...]             Show or save feature groups\n  doctor                          Validate the installation\n  update [--yes]                  Safely update, rebuild, and apply\n  shell render ...                Render a shell adapter\n  worktree ...                    Git worktree/Zellij helpers\n  util ...                        Portable utility commands");
}
