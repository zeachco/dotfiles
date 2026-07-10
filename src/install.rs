use crate::config::home;
use crate::model::{Feature, Platform};
use std::collections::BTreeSet;
use std::ffi::OsStr;
use std::fs;
use std::path::{Path, PathBuf};
use std::process::{Command, Stdio};
use std::time::{SystemTime, UNIX_EPOCH};

pub fn command_exists(name: &str) -> bool {
    let name = if name == "fd" && path_command_exists("fdfind") {
        "fdfind"
    } else {
        name
    };
    path_command_exists(name)
}

fn path_command_exists(name: &str) -> bool {
    Command::new("sh")
        .args([
            "-c",
            &format!("command -v {} >/dev/null 2>&1", safe_word(name)),
        ])
        .stdout(Stdio::null())
        .stderr(Stdio::null())
        .status()
        .map(|s| s.success())
        .unwrap_or(false)
}

pub fn describe(platform: Platform, selected: &Feature, shell: &str) -> Vec<String> {
    let mut lines = Vec::new();
    for package in &selected.packages {
        if !command_exists(&package.command) {
            let name = platform.package_name(package);
            if !name.is_empty() {
                lines.push(format!(
                    "install package {name} (provides {})",
                    package.command
                ));
            }
        }
    }
    for package in &selected.stow {
        lines.push(format!("stow config package {package}"));
    }
    for action in &selected.actions {
        lines.push(format!("apply action {action}"));
    }
    lines.push(format!("generate and install {shell} adapter"));
    lines
}

pub fn ensure_package_manager(platform: Platform) -> Result<(), String> {
    if platform != Platform::Macos || command_exists("brew") {
        return Ok(());
    }
    println!("install Homebrew...");
    let output = Command::new("curl")
        .args([
            "-fsSL",
            "https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh",
        ])
        .output()
        .map_err(|e| e.to_string())?;
    if !output.status.success() {
        return Err("failed to download the Homebrew installer".into());
    }
    let mut child = Command::new("/bin/bash")
        .env("NONINTERACTIVE", "1")
        .stdin(Stdio::piped())
        .spawn()
        .map_err(|e| e.to_string())?;
    use std::io::Write;
    child
        .stdin
        .take()
        .unwrap()
        .write_all(&output.stdout)
        .map_err(|e| e.to_string())?;
    if !child.wait().map_err(|e| e.to_string())?.success() {
        return Err("Homebrew installation failed".into());
    }
    let brew_bin = ["/opt/homebrew/bin", "/usr/local/bin"]
        .into_iter()
        .find(|path| Path::new(path).join("brew").is_file())
        .ok_or("Homebrew installed but brew was not found")?;
    let old_path = std::env::var("PATH").unwrap_or_default();
    std::env::set_var("PATH", format!("{brew_bin}:{old_path}"));
    Ok(())
}

pub fn install_packages(platform: Platform, selected: &Feature) -> Result<(), String> {
    for package in &selected.packages {
        if command_exists(&package.command) {
            println!("found {}", package.command);
            continue;
        }
        let name = platform.package_name(package);
        if name.is_empty() {
            println!("skip {}: no package for this platform", package.command);
            continue;
        }
        println!("install {name}...");
        let mut command = match platform {
            Platform::Arch | Platform::Omarchy => {
                let mut c = Command::new("sudo");
                c.args(["pacman", "-S", "--needed", "--noconfirm", name]);
                c
            }
            Platform::Debian | Platform::Ubuntu => {
                let mut c = Command::new("sudo");
                c.args(["apt-get", "install", "-y", name]);
                c
            }
            Platform::Macos => {
                let mut c = Command::new("brew");
                c.args(["install", name]);
                c
            }
            Platform::Termux => {
                let mut c = Command::new("pkg");
                c.args(["install", "-y", name]);
                c
            }
        };
        run(&mut command)?;
    }
    Ok(())
}

pub fn apply_actions(
    platform: Platform,
    actions: &[String],
    repo: &Path,
    assume_yes: bool,
) -> Result<(), String> {
    for action in actions {
        println!("action {action}...");
        match action.as_str() {
            "git_config" => git_config(assume_yes)?,
            "ensure_dev_dir" => {
                fs::create_dir_all(home().join("dev")).map_err(|e| e.to_string())?
            }
            "arch_yay" => arch_yay()?,
            "macos_defaults" => macos_defaults()?,
            "termux_storage" => termux_storage()?,
            "ubuntu_shortcuts" => ubuntu_shortcuts()?,
            "omarchy_binding" => omarchy_binding()?,
            "nerd_font" => nerd_font(platform)?,
            "macos_apps" => macos_apps()?,
            "devbox_installer" if !command_exists("devbox") => {
                external_installer("https://get.jetify.com/devbox")?
            }
            "devbox_installer" => {}
            "claude_installer" if !command_exists("claude") => {
                external_installer("https://claude.ai/install.sh")?
            }
            "ollama_installer" if !command_exists("ollama") => {
                external_installer("https://ollama.com/install.sh")?
            }
            "claude_installer" | "ollama_installer" => {}
            "theme_executable" => ensure_executable(&repo.join("bin/theme-switch"))?,
            other => return Err(format!("unknown action '{other}'")),
        }
    }
    if matches!(platform, Platform::Arch | Platform::Omarchy) {
        // No implicit pacman -Syu: system upgrades are deliberately outside setup.
    }
    Ok(())
}

pub fn stow(repo: &Path, packages: &[String]) -> Result<Option<PathBuf>, String> {
    if packages.is_empty() {
        return Ok(None);
    }
    if !command_exists("stow") {
        return Err("GNU Stow is required but was not installed".into());
    }
    // Keep the shared config root physical. Otherwise Stow can fold all of
    // ~/.config into the first package on a fresh machine, and later generated
    // shell/state files would be written back into that package's source tree.
    fs::create_dir_all(home().join(".config")).map_err(|e| e.to_string())?;
    let timestamp = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map_err(|e| e.to_string())?
        .as_secs();
    let backup = home().join(format!(".local/state/dotfiles/backups/{timestamp}"));
    let mut backed_up = false;
    let mut moved = BTreeSet::new();
    for package in packages {
        let source = repo.join("configs").join(package);
        for relative in leaf_paths(&source)? {
            let target = home().join(&relative);
            if let Some((ancestor, expected)) = symlink_ancestor(&source, &relative)? {
                if expected {
                    continue;
                }
                if moved.insert(ancestor.clone()) {
                    backup_target(&home().join(&ancestor), &backup.join(&ancestor))?;
                    backed_up = true;
                }
                continue;
            }
            if target.symlink_metadata().is_err() {
                continue;
            }
            let expected = source.join(&relative);
            if is_expected_link(&target, &expected) {
                continue;
            }
            let destination = backup.join(&relative);
            backup_target(&target, &destination)?;
            backed_up = true;
        }
        let mut command = Command::new("stow");
        command
            .current_dir(repo.join("configs"))
            .arg("--target")
            .arg(home())
            .arg("--no-folding")
            .arg("--restow")
            .arg(package);
        run(&mut command)?;
    }
    Ok(backed_up.then_some(backup))
}

fn symlink_ancestor(source: &Path, relative: &Path) -> Result<Option<(PathBuf, bool)>, String> {
    let mut prefix = PathBuf::new();
    for component in relative.components() {
        prefix.push(component);
        let target = home().join(&prefix);
        let metadata = match target.symlink_metadata() {
            Ok(metadata) => metadata,
            Err(error) if error.kind() == std::io::ErrorKind::NotFound => return Ok(None),
            Err(error) => return Err(format!("{}: {error}", target.display())),
        };
        if metadata.file_type().is_symlink() {
            return Ok(Some((
                prefix.clone(),
                is_expected_link(&target, &source.join(&prefix)),
            )));
        }
    }
    Ok(None)
}

fn backup_target(target: &Path, destination: &Path) -> Result<(), String> {
    if let Some(parent) = destination.parent() {
        fs::create_dir_all(parent).map_err(|e| e.to_string())?;
    }
    println!("backup {} -> {}", target.display(), destination.display());
    fs::rename(target, destination).map_err(|e| format!("backup {}: {e}", target.display()))
}

fn leaf_paths(root: &Path) -> Result<Vec<PathBuf>, String> {
    fn walk(base: &Path, current: &Path, out: &mut Vec<PathBuf>) -> Result<(), String> {
        for entry in fs::read_dir(current).map_err(|e| format!("{}: {e}", current.display()))? {
            let entry = entry.map_err(|e| e.to_string())?;
            let path = entry.path();
            let kind = entry.file_type().map_err(|e| e.to_string())?;
            if kind.is_dir() {
                walk(base, &path, out)?;
            } else {
                out.push(
                    path.strip_prefix(base)
                        .map_err(|e| e.to_string())?
                        .to_path_buf(),
                );
            }
        }
        Ok(())
    }
    let mut result = Vec::new();
    walk(root, root, &mut result)?;
    Ok(result)
}

fn is_expected_link(target: &Path, expected: &Path) -> bool {
    fs::read_link(target)
        .ok()
        .map(|link| {
            let resolved = if link.is_absolute() {
                link
            } else {
                target.parent().unwrap_or(Path::new(".")).join(link)
            };
            fs::canonicalize(resolved).ok() == fs::canonicalize(expected).ok()
        })
        .unwrap_or(false)
}

fn git_config(assume_yes: bool) -> Result<(), String> {
    let settings = [
        ("credential.helper", "cache"),
        ("color.ui", "auto"),
        ("core.editor", "nvim"),
        ("push.default", "tracking"),
        ("pull.rebase", "true"),
        ("init.defaultBranch", "main"),
        ("alias.b", "branch -a"),
        ("alias.aa", "add -A"),
        ("alias.d", "diff"),
        ("alias.s", "status"),
        ("alias.co", "checkout"),
        ("alias.cp", "cherry-pick"),
        ("alias.ci", "commit"),
        ("alias.rb", "rebase -i"),
        ("alias.p", "pull"),
        ("alias.pp", "push"),
        ("alias.fa", "fetch --all"),
        ("alias.fu", "fetch upstream"),
        ("alias.rh", "reset --hard"),
        ("alias.mt", "mergetool"),
        ("alias.l", "log --oneline --graph"),
    ];
    for (key, value) in settings {
        run(Command::new("git").args(["config", "--global", "--replace-all", key, value]))?;
    }
    let email = capture(Command::new("git").args(["config", "--global", "user.email"]))?
        .trim()
        .to_string();
    if email.is_empty() {
        if assume_yes {
            eprintln!("warning: Git user.email is not configured");
        } else {
            let email = prompt("Git email (leave blank to skip): ")?;
            if !email.is_empty() {
                run(Command::new("git").args(["config", "--global", "user.email", &email]))?;
            }
            let name = prompt("Git full name (leave blank to skip): ")?;
            if !name.is_empty() {
                run(Command::new("git").args(["config", "--global", "user.name", &name]))?;
            }
        }
    }
    Ok(())
}

fn arch_yay() -> Result<(), String> {
    if command_exists("yay") {
        return Ok(());
    }
    run(Command::new("sudo").args([
        "pacman",
        "-S",
        "--needed",
        "--noconfirm",
        "git",
        "base-devel",
    ]))?;
    let path = Path::new("/tmp/dotfiles-yay");
    if path.exists() {
        fs::remove_dir_all(path).map_err(|e| e.to_string())?;
    }
    run(Command::new("git").args([
        "clone",
        "https://aur.archlinux.org/yay.git",
        path.to_str().unwrap(),
    ]))?;
    run(Command::new("makepkg")
        .current_dir(path)
        .args(["-si", "--noconfirm"]))
}

fn macos_defaults() -> Result<(), String> {
    let settings: &[&[&str]] = &[
        &[
            "write",
            "NSGlobalDomain",
            "NSWindowResizeTime",
            "-float",
            "0.001",
        ],
        &[
            "write",
            "NSGlobalDomain",
            "NSAutomaticWindowAnimationsEnabled",
            "-bool",
            "false",
        ],
        &["write", "com.apple.dock", "launchanim", "-bool", "false"],
        &[
            "write",
            "com.apple.finder",
            "DisableAllAnimations",
            "-bool",
            "true",
        ],
        &[
            "write",
            "-g",
            "NSWindowShouldDragOnGesture",
            "-bool",
            "true",
        ],
    ];
    for args in settings {
        run(Command::new("defaults").args(*args))?;
    }
    Ok(())
}

fn termux_storage() -> Result<(), String> {
    if !home().join("storage").exists() && command_exists("termux-setup-storage") {
        run(&mut Command::new("termux-setup-storage"))?;
    }
    Ok(())
}

fn ubuntu_shortcuts() -> Result<(), String> {
    if !command_exists("gsettings") {
        return Ok(());
    }
    let commands: &[&[&str]] = &[
        &["set", "org.gnome.settings-daemon.plugins.media-keys", "terminal", "[]"],
        &["set", "org.gnome.settings-daemon.plugins.media-keys", "custom-keybindings", "['/org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/custom0/']"],
        &["set", "org.gnome.settings-daemon.plugins.media-keys.custom-keybinding:/org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/custom0/", "name", "Alacritty"],
        &["set", "org.gnome.settings-daemon.plugins.media-keys.custom-keybinding:/org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/custom0/", "command", "alacritty"],
        &["set", "org.gnome.settings-daemon.plugins.media-keys.custom-keybinding:/org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/custom0/", "binding", "<Control><Alt>t"],
    ];
    for args in commands {
        run(Command::new("gsettings").args(*args))?;
    }
    Ok(())
}

fn omarchy_binding() -> Result<(), String> {
    let path = home().join(".config/hypr/bindings.conf");
    let mut text = fs::read_to_string(&path).unwrap_or_default();
    if !text.contains("dotfiles_alacritty") {
        text.push_str("\n# dotfiles_alacritty\nbindd = SUPER, RETURN, Terminal with Zellij, exec, uwsm-app -- alacritty --config-file ~/.dotfiles_alacritty.toml\n");
        fs::write(path, text).map_err(|e| e.to_string())?;
    }
    Ok(())
}

fn external_installer(url: &str) -> Result<(), String> {
    let output = Command::new("curl")
        .args(["-fsSL", url])
        .output()
        .map_err(|e| e.to_string())?;
    if !output.status.success() {
        return Err(format!("failed to download {url}"));
    }
    let mut child = Command::new("sh")
        .stdin(Stdio::piped())
        .spawn()
        .map_err(|e| e.to_string())?;
    use std::io::Write;
    child
        .stdin
        .take()
        .unwrap()
        .write_all(&output.stdout)
        .map_err(|e| e.to_string())?;
    let status = child.wait().map_err(|e| e.to_string())?;
    if status.success() {
        Ok(())
    } else {
        Err(format!("installer from {url} failed"))
    }
}

fn nerd_font(platform: Platform) -> Result<(), String> {
    if platform == Platform::Macos {
        return run(Command::new("brew").args(["install", "--cask", "font-victor-mono-nerd-font"]));
    }
    let destination = home().join(".local/share/fonts/VictorMono");
    if destination.is_dir()
        && fs::read_dir(&destination)
            .map(|mut v| v.next().is_some())
            .unwrap_or(false)
    {
        return Ok(());
    }
    fs::create_dir_all(&destination).map_err(|e| e.to_string())?;
    let archive = Path::new("/tmp/dotfiles-victor-mono.zip");
    run(Command::new("curl")
        .args([
            "-fL",
            "https://github.com/ryanoasis/nerd-fonts/releases/latest/download/VictorMono.zip",
            "-o",
        ])
        .arg(archive))?;
    run(Command::new("unzip")
        .arg("-o")
        .arg(archive)
        .arg("-d")
        .arg(&destination))?;
    if command_exists("fc-cache") {
        run(Command::new("fc-cache").arg("-f").arg(&destination))?;
    }
    Ok(())
}

fn macos_apps() -> Result<(), String> {
    let applications = [
        ("/Applications/Alacritty.app", "alacritty"),
        ("/Applications/Chromium.app", "chromium"),
        ("/Applications/Tiles.app", "tiles"),
    ];
    for (path, package) in applications {
        if !Path::new(path).exists() {
            run(Command::new("brew").args(["install", "--cask", package]))?;
        }
    }
    if !Path::new("/Applications/AeroSpace.app").exists() {
        run(Command::new("brew").args(["install", "--cask", "nikitabobko/tap/aerospace"]))?;
    }
    Ok(())
}

fn ensure_executable(path: &Path) -> Result<(), String> {
    #[cfg(unix)]
    {
        use std::os::unix::fs::PermissionsExt;
        let mut permissions = fs::metadata(path).map_err(|e| e.to_string())?.permissions();
        permissions.set_mode(permissions.mode() | 0o755);
        fs::set_permissions(path, permissions).map_err(|e| e.to_string())?;
    }
    Ok(())
}

pub fn run(command: &mut Command) -> Result<(), String> {
    let display = format_command(command);
    let status = command.status().map_err(|e| format!("{display}: {e}"))?;
    if status.success() {
        Ok(())
    } else {
        Err(format!("command failed ({status}): {display}"))
    }
}

pub fn capture(command: &mut Command) -> Result<String, String> {
    let display = format_command(command);
    let output = command.output().map_err(|e| format!("{display}: {e}"))?;
    if output.status.success() {
        Ok(String::from_utf8_lossy(&output.stdout).into_owned())
    } else {
        Err(format!("command failed ({}): {display}", output.status))
    }
}

pub fn prompt(label: &str) -> Result<String, String> {
    use std::io::{self, Write};
    print!("{label}");
    io::stdout().flush().map_err(|e| e.to_string())?;
    let mut input = String::new();
    io::stdin()
        .read_line(&mut input)
        .map_err(|e| e.to_string())?;
    Ok(input.trim().into())
}

fn safe_word(value: &str) -> String {
    value
        .chars()
        .filter(|c| c.is_ascii_alphanumeric() || "_-".contains(*c))
        .collect()
}
fn format_command(command: &Command) -> String {
    std::iter::once(command.get_program())
        .chain(command.get_args())
        .map(OsStr::to_string_lossy)
        .collect::<Vec<_>>()
        .join(" ")
}
