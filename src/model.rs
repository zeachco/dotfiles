use std::collections::{BTreeMap, BTreeSet};
use std::path::PathBuf;

#[derive(Clone, Debug, Default, PartialEq, Eq)]
pub struct Feature {
    pub packages: Vec<Package>,
    pub stow: Vec<String>,
    pub actions: Vec<String>,
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct Package {
    pub command: String,
    pub apt: String,
    pub pacman: String,
    pub brew: String,
    pub pkg: String,
}

impl Package {
    pub fn parse(value: &str) -> Result<Self, String> {
        let parts: Vec<_> = value.split('|').collect();
        if parts.len() != 5 {
            return Err(format!(
                "package '{value}' must contain command|apt|pacman|brew|pkg"
            ));
        }
        Ok(Self {
            command: parts[0].into(),
            apt: parts[1].into(),
            pacman: parts[2].into(),
            brew: parts[3].into(),
            pkg: parts[4].into(),
        })
    }
}

#[derive(Clone, Debug, Default)]
pub struct Profile {
    pub name: String,
    pub inherits: Vec<String>,
    pub default_features: Vec<String>,
    pub features: BTreeMap<String, Feature>,
}

impl Profile {
    pub fn merge(&mut self, child: Profile) {
        self.name = child.name;
        if !child.default_features.is_empty() {
            self.default_features = child.default_features;
        }
        for (name, feature) in child.features {
            let target = self.features.entry(name).or_default();
            target.packages.extend(feature.packages);
            target.stow.extend(feature.stow);
            target.actions.extend(feature.actions);
        }
    }

    pub fn selected(&self, names: &[String]) -> Result<Feature, String> {
        let mut result = Feature::default();
        for name in names {
            let feature = self
                .features
                .get(name)
                .ok_or_else(|| format!("unknown feature '{name}' for profile {}", self.name))?;
            result.packages.extend(feature.packages.clone());
            result.stow.extend(feature.stow.clone());
            result.actions.extend(feature.actions.clone());
        }
        dedupe_packages(&mut result.packages);
        dedupe(&mut result.stow);
        dedupe(&mut result.actions);
        Ok(result)
    }
}

fn dedupe(values: &mut Vec<String>) {
    let mut seen = BTreeSet::new();
    values.retain(|value| seen.insert(value.clone()));
}

fn dedupe_packages(values: &mut Vec<Package>) {
    let mut seen = BTreeSet::new();
    values.retain(|value| seen.insert(value.command.clone()));
}

#[derive(Clone, Debug, Default)]
pub struct ShellManifest {
    pub env: BTreeMap<String, String>,
    pub paths: Vec<String>,
    pub aliases: BTreeMap<String, String>,
}

#[derive(Clone, Debug, Default)]
pub struct State {
    pub repo: PathBuf,
    pub profile: String,
    pub shell: String,
    pub features: Vec<String>,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Platform {
    Arch,
    Debian,
    Ubuntu,
    Macos,
    Termux,
    Omarchy,
}

impl Platform {
    pub fn profile(self) -> &'static str {
        match self {
            Self::Arch => "archlinux",
            Self::Debian => "debian",
            Self::Ubuntu => "ubuntu",
            Self::Macos => "osx",
            Self::Termux => "termux",
            Self::Omarchy => "omarchy",
        }
    }

    pub fn package_name(self, package: &Package) -> &str {
        match self {
            Self::Arch | Self::Omarchy => &package.pacman,
            Self::Debian | Self::Ubuntu => &package.apt,
            Self::Macos => &package.brew,
            Self::Termux => &package.pkg,
        }
    }
}
