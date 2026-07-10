use crate::model::{Package, Profile, ShellManifest, State};
use std::collections::BTreeSet;
use std::fs;
use std::path::{Path, PathBuf};

pub fn load_profile(root: &Path, name: &str) -> Result<Profile, String> {
    load_profile_inner(root, name, &mut BTreeSet::new())
}

pub fn load_effective_profile(root: &Path, name: &str) -> Result<Profile, String> {
    let mut profile = load_profile(root, name)?;
    if crate::platform::is_wsl() {
        profile.merge(load_profile(root, "wsl")?);
        profile.name = name.into();
    }
    validate_profile(root, &profile)?;
    Ok(profile)
}

fn load_profile_inner(
    root: &Path,
    name: &str,
    stack: &mut BTreeSet<String>,
) -> Result<Profile, String> {
    if !stack.insert(name.into()) {
        return Err(format!("profile inheritance cycle at '{name}'"));
    }
    let path = root.join("manifests/profiles").join(format!("{name}.toml"));
    let text = fs::read_to_string(&path).map_err(|e| format!("{}: {e}", path.display()))?;
    let parsed = parse_profile(name, &text)?;
    let mut merged = Profile::default();
    for parent in &parsed.inherits {
        merged.merge(load_profile_inner(root, parent, stack)?);
    }
    merged.merge(parsed);
    stack.remove(name);
    validate_profile(root, &merged)?;
    Ok(merged)
}

fn parse_profile(name: &str, text: &str) -> Result<Profile, String> {
    let mut profile = Profile {
        name: name.into(),
        ..Profile::default()
    };
    let mut section = String::new();
    for (index, raw) in text.lines().enumerate() {
        let line = strip_comment(raw).trim();
        if line.is_empty() {
            continue;
        }
        if line.starts_with('[') && line.ends_with(']') {
            section = line[1..line.len() - 1].trim().into();
            continue;
        }
        let (key, value) = key_value(line, index + 1)?;
        if section == "profile" {
            match key {
                "inherits" => profile.inherits = parse_array(value)?,
                "default_features" => profile.default_features = parse_array(value)?,
                _ => return Err(format!("line {}: unknown profile key '{key}'", index + 1)),
            }
        } else if let Some(feature_name) = section.strip_prefix("feature.") {
            let feature = profile.features.entry(feature_name.into()).or_default();
            match key {
                "packages" => {
                    for item in parse_array(value)? {
                        feature.packages.push(Package::parse(&item)?);
                    }
                }
                "stow" => feature.stow.extend(parse_array(value)?),
                "actions" => feature.actions.extend(parse_array(value)?),
                _ => return Err(format!("line {}: unknown feature key '{key}'", index + 1)),
            }
        } else {
            return Err(format!("line {}: key outside a known section", index + 1));
        }
    }
    Ok(profile)
}

pub fn load_shell(root: &Path, profile: &str) -> Result<ShellManifest, String> {
    let mut result = parse_shell_file(&root.join("manifests/shell.toml"))?;
    let overlay = root.join("manifests/shell").join(format!("{profile}.toml"));
    if overlay.is_file() {
        let child = parse_shell_file(&overlay)?;
        result.env.extend(child.env);
        result.paths.extend(child.paths);
        result.aliases.extend(child.aliases);
    }
    if crate::platform::is_wsl() {
        let child = parse_shell_file(&root.join("manifests/shell/wsl.toml"))?;
        result.env.extend(child.env);
        result.paths.extend(child.paths);
        result.aliases.extend(child.aliases);
    }
    Ok(result)
}

fn parse_shell_file(path: &Path) -> Result<ShellManifest, String> {
    let text = fs::read_to_string(path).map_err(|e| format!("{}: {e}", path.display()))?;
    let mut result = ShellManifest::default();
    let mut section = String::new();
    for (index, raw) in text.lines().enumerate() {
        let line = strip_comment(raw).trim();
        if line.is_empty() {
            continue;
        }
        if line.starts_with('[') && line.ends_with(']') {
            section = line[1..line.len() - 1].into();
            continue;
        }
        let (key, value) = key_value(line, index + 1)?;
        match section.as_str() {
            "env" => {
                if !valid_env_name(key) {
                    return Err(format!(
                        "line {}: invalid environment name '{key}'",
                        index + 1
                    ));
                }
                result.env.insert(key.into(), parse_string(value)?);
            }
            "path" if key == "entries" => result.paths = parse_array(value)?,
            "aliases" => {
                if !valid_alias_name(key) {
                    return Err(format!("line {}: invalid alias name '{key}'", index + 1));
                }
                result.aliases.insert(key.into(), parse_string(value)?);
            }
            _ => return Err(format!("line {}: unknown shell manifest entry", index + 1)),
        }
    }
    Ok(result)
}

fn validate_profile(root: &Path, profile: &Profile) -> Result<(), String> {
    for feature in &profile.default_features {
        if !profile.features.contains_key(feature) {
            return Err(format!("default feature '{feature}' is not defined"));
        }
    }
    for (feature_name, feature) in &profile.features {
        for package in &feature.packages {
            if package.command.is_empty() {
                return Err(format!(
                    "feature '{feature_name}' has a package with no command"
                ));
            }
        }
        for package in &feature.stow {
            if !root.join("configs").join(package).is_dir() {
                return Err(format!(
                    "feature '{feature_name}' references missing Stow package '{package}'"
                ));
            }
        }
        const ACTIONS: &[&str] = &[
            "git_config",
            "ensure_dev_dir",
            "arch_yay",
            "macos_defaults",
            "termux_storage",
            "ubuntu_shortcuts",
            "omarchy_binding",
            "claude_installer",
            "ollama_installer",
            "theme_executable",
            "nerd_font",
            "macos_apps",
            "devbox_installer",
        ];
        for action in &feature.actions {
            if !ACTIONS.contains(&action.as_str()) {
                return Err(format!(
                    "feature '{feature_name}' references unknown action '{action}'"
                ));
            }
        }
    }
    Ok(())
}

pub fn state_path() -> PathBuf {
    config_home().join("dotfiles/state.toml")
}

pub fn load_state() -> Result<State, String> {
    let path = state_path();
    let text = fs::read_to_string(&path).map_err(|e| format!("{}: {e}", path.display()))?;
    let mut state = State::default();
    for (index, raw) in text.lines().enumerate() {
        let line = strip_comment(raw).trim();
        if line.is_empty() {
            continue;
        }
        let (key, value) = key_value(line, index + 1)?;
        match key {
            "repo" => state.repo = PathBuf::from(parse_string(value)?),
            "profile" => state.profile = parse_string(value)?,
            "shell" => state.shell = parse_string(value)?,
            "features" => state.features = parse_array(value)?,
            _ => return Err(format!("unknown state key '{key}'")),
        }
    }
    Ok(state)
}

pub fn save_state(state: &State) -> Result<(), String> {
    let path = state_path();
    if let Some(parent) = path.parent() {
        fs::create_dir_all(parent).map_err(|e| e.to_string())?;
    }
    let features = state
        .features
        .iter()
        .map(|v| quote(v))
        .collect::<Vec<_>>()
        .join(", ");
    let text = format!(
        "repo = {}\nprofile = {}\nshell = {}\nfeatures = [{}]\n",
        quote(&state.repo.to_string_lossy()),
        quote(&state.profile),
        quote(&state.shell),
        features
    );
    fs::write(path, text).map_err(|e| e.to_string())
}

pub fn config_home() -> PathBuf {
    std::env::var_os("XDG_CONFIG_HOME")
        .map(PathBuf::from)
        .unwrap_or_else(|| home().join(".config"))
}

pub fn home() -> PathBuf {
    std::env::var_os("HOME")
        .map(PathBuf::from)
        .unwrap_or_else(|| PathBuf::from("."))
}

fn key_value(line: &str, number: usize) -> Result<(&str, &str), String> {
    line.split_once('=')
        .map(|(k, v)| (k.trim(), v.trim()))
        .ok_or_else(|| format!("line {number}: expected key = value"))
}

fn parse_string(value: &str) -> Result<String, String> {
    let value = value.trim();
    if value.len() >= 2 && value.starts_with('"') && value.ends_with('"') {
        Ok(value[1..value.len() - 1]
            .replace("\\\"", "\"")
            .replace("\\\\", "\\"))
    } else {
        Err(format!("expected quoted string, got '{value}'"))
    }
}

fn parse_array(value: &str) -> Result<Vec<String>, String> {
    let value = value.trim();
    if !value.starts_with('[') || !value.ends_with(']') {
        return Err(format!("expected array, got '{value}'"));
    }
    let inner = &value[1..value.len() - 1];
    if inner.trim().is_empty() {
        return Ok(Vec::new());
    }
    inner
        .split(',')
        .map(|item| parse_string(item.trim()))
        .collect()
}

fn quote(value: &str) -> String {
    format!("\"{}\"", value.replace('\\', "\\\\").replace('"', "\\\""))
}

fn strip_comment(line: &str) -> &str {
    let mut quoted = false;
    for (i, ch) in line.char_indices() {
        if ch == '"' {
            quoted = !quoted;
        }
        if ch == '#' && !quoted {
            return &line[..i];
        }
    }
    line
}

fn valid_env_name(value: &str) -> bool {
    let mut chars = value.chars();
    matches!(chars.next(), Some('_') | Some('A'..='Z') | Some('a'..='z'))
        && chars.all(|ch| ch == '_' || ch.is_ascii_alphanumeric())
}

fn valid_alias_name(value: &str) -> bool {
    !value.is_empty()
        && value
            .chars()
            .all(|ch| ch.is_ascii_alphanumeric() || matches!(ch, '_' | '-'))
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn parses_package() {
        let p = Package::parse("rg|ripgrep|ripgrep|ripgrep|ripgrep").unwrap();
        assert_eq!(p.command, "rg");
        assert_eq!(p.apt, "ripgrep");
    }
    #[test]
    fn parses_array_values() {
        assert_eq!(parse_array("[\"a\", \"b\"]").unwrap(), vec!["a", "b"]);
    }

    #[test]
    fn every_repository_profile_is_valid() {
        let root = Path::new(env!("CARGO_MANIFEST_DIR"));
        for name in [
            "debian",
            "ubuntu",
            "archlinux",
            "osx",
            "termux",
            "omarchy",
            "wsl",
        ] {
            let profile =
                load_profile(root, name).unwrap_or_else(|error| panic!("{name}: {error}"));
            profile.selected(&profile.default_features).unwrap();
            load_shell(root, name).unwrap();
        }
    }
}
