use crate::model::Platform;
use std::fs;
use std::process::Command;

pub fn detect() -> Result<Platform, String> {
    if let Ok(value) = std::env::var("DOTFILES_PLATFORM") {
        return parse(&value);
    }
    if std::env::var_os("TERMUX_VERSION").is_some()
        || std::env::var("PREFIX")
            .map(|v| v.contains("com.termux"))
            .unwrap_or(false)
    {
        return Ok(Platform::Termux);
    }
    if cfg!(target_os = "macos") {
        return Ok(Platform::Macos);
    }
    if cfg!(target_os = "linux") {
        let release = fs::read_to_string("/etc/os-release")
            .unwrap_or_default()
            .to_lowercase();
        if release.contains("omarchy") {
            return Ok(Platform::Omarchy);
        }
        if fs::metadata("/etc/arch-release").is_ok() || release.contains("id=arch") {
            return Ok(Platform::Arch);
        }
        if release.lines().any(|line| line == "id=ubuntu") {
            return Ok(Platform::Ubuntu);
        }
        return Ok(Platform::Debian);
    }
    Err(format!(
        "unsupported operating system: {}",
        std::env::consts::OS
    ))
}

fn parse(value: &str) -> Result<Platform, String> {
    match value {
        "arch" | "archlinux" => Ok(Platform::Arch),
        "debian" => Ok(Platform::Debian),
        "ubuntu" | "wsl-ubuntu" => Ok(Platform::Ubuntu),
        "macos" | "osx" => Ok(Platform::Macos),
        "termux" => Ok(Platform::Termux),
        "omarchy" => Ok(Platform::Omarchy),
        _ => Err(format!("unsupported platform override '{value}'")),
    }
}

pub fn is_wsl() -> bool {
    std::env::var_os("DOTFILES_WSL").is_some()
        || std::env::var_os("WSL_DISTRO_NAME").is_some()
        || fs::read_to_string("/proc/version")
            .map(|v| v.to_lowercase().contains("microsoft"))
            .unwrap_or(false)
}

pub fn default_shell(platform: Platform) -> Result<String, String> {
    if let Ok(value) = std::env::var("DOTFILES_SHELL") {
        return normalize_shell(&value);
    }
    if platform == Platform::Termux {
        return std::env::var("SHELL")
            .map_err(|_| "SHELL is not set on Termux".into())
            .and_then(|v| normalize_shell(&v));
    }
    let user = std::env::var("USER").unwrap_or_default();
    let discovered = if platform == Platform::Macos {
        output(Command::new("dscl").args([".", "-read", &format!("/Users/{user}"), "UserShell"]))
            .and_then(|line| line.split_whitespace().last().map(str::to_string))
    } else {
        output(Command::new("getent").args(["passwd", &user]))
            .and_then(|line| line.trim().split(':').nth(6).map(str::to_string))
    };
    discovered
        .or_else(|| std::env::var("SHELL").ok())
        .ok_or_else(|| "could not determine the account's default shell".into())
        .and_then(|value| normalize_shell(&value))
}

fn normalize_shell(value: &str) -> Result<String, String> {
    let name = value.rsplit('/').next().unwrap_or(value);
    match name {
        "bash" | "zsh" | "fish" => Ok(name.into()),
        _ => Err(format!(
            "unsupported default shell '{value}'; supported shells: bash, zsh, fish"
        )),
    }
}

fn output(command: &mut Command) -> Option<String> {
    command
        .output()
        .ok()
        .filter(|o| o.status.success())
        .map(|o| String::from_utf8_lossy(&o.stdout).into_owned())
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn shell_names_are_validated() {
        assert_eq!(normalize_shell("/usr/bin/fish").unwrap(), "fish");
        assert!(normalize_shell("nu").is_err());
    }
}
