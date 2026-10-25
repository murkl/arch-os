// Embeds the product beside this crate, so the binary is the whole program. Sets the version.
use std::path::{Path, PathBuf};
use std::{env, fs, process::Command};

/// Files below `dir` relative to the product, in name order. Manual checks stay out, dotfiles
/// stay in: a task may ship `.config/`.
fn files(dir: &Path, prefix: &str, out: &mut Vec<String>) {
    let mut entries: Vec<_> = fs::read_dir(dir)
        .unwrap_or_else(|e| panic!("{}: {e}", dir.display()))
        .map(|e| e.unwrap())
        .collect();
    entries.sort_by_key(|e| e.file_name());
    for e in entries {
        let name = e.file_name().into_string().unwrap();
        if ["check.sh", "check.zsh", "README.md"].contains(&name.as_str()) {
            continue;
        }
        let path = format!("{prefix}{name}");
        if e.file_type().unwrap().is_dir() {
            files(&e.path(), &format!("{path}/"), out);
        } else {
            out.push(path);
        }
    }
}

fn main() {
    let root = PathBuf::from(env::var("CARGO_MANIFEST_DIR").unwrap()).join("..");
    let mut found = Vec::new();
    for name in ["product.yaml", "lib.sh"] {
        println!("cargo::rerun-if-changed=../{name}");
        if root.join(name).is_file() {
            found.push(name.to_string());
        }
    }
    println!("cargo::rerun-if-changed=../locales");
    if root.join("locales").is_dir() {
        files(&root.join("locales"), "locales/", &mut found);
    }
    let mut dirs: Vec<_> = fs::read_dir(&root)
        .unwrap()
        .map(|e| e.unwrap())
        .filter(|e| e.path().join("module.yaml").is_file())
        .collect();
    dirs.sort_by_key(|e| e.file_name());
    for dir in dirs {
        let name = dir.file_name().into_string().unwrap();
        println!("cargo::rerun-if-changed=../{name}");
        files(&dir.path(), &format!("{name}/"), &mut found);
    }
    let mut code = String::from("pub static FILES: &[(&str, &[u8])] = &[\n");
    for f in &found {
        code += &format!(
            "    ({f:?}, include_bytes!(concat!(env!(\"CARGO_MANIFEST_DIR\"), \"/../{f}\"))),\n"
        );
    }
    code += "];\n";
    let out = PathBuf::from(env::var("OUT_DIR").unwrap());
    fs::write(out.join("embedded.rs"), code).unwrap();

    // A release sets <PACKAGE>_VERSION. Other builds are a pre-release of the patch after the
    // last release tag.
    let key = format!(
        "{}_VERSION",
        env::var("CARGO_PKG_NAME")
            .unwrap()
            .to_uppercase()
            .replace('-', "_")
    );
    println!("cargo::rerun-if-env-changed={key}");
    println!("cargo::rerun-if-changed=../.git/refs/tags");
    let version = match env::var(&key) {
        Ok(v) if !v.is_empty() => {
            assert!(
                is_version(&v),
                "{key}={v:?} is not a version like 2.1.0 or 2.1.0-rc1"
            );
            v
        }
        _ => last_release()
            .map(|v| next_dev(&v))
            .unwrap_or_else(|| "0.0.0-dev".into()),
    };
    println!("cargo::rustc-env=VERSION={version}");
}

/// `2.1.0` or `2.1.0-rc1`.
fn is_version(v: &str) -> bool {
    let (release, pre) = v.split_once('-').unwrap_or((v, "dev"));
    let numbers: Vec<&str> = release.split('.').collect();
    numbers.len() == 3
        && numbers
            .iter()
            .all(|n| !n.is_empty() && n.bytes().all(|b| b.is_ascii_digit()))
        && !pre.is_empty()
        && pre
            .bytes()
            .all(|b| b.is_ascii_alphanumeric() || b == b'.' || b == b'-')
}

/// The newest release tag before HEAD, `v` dropped, by the patterns of murkl/workflows.
fn last_release() -> Option<String> {
    let out = Command::new("git")
        .args(["describe", "--tags", "--abbrev=0"])
        .args([
            "--match",
            "[0-9]*.[0-9]*.[0-9]*",
            "--match",
            "v[0-9]*.[0-9]*.[0-9]*",
        ])
        .output()
        .ok()?;
    let tag = String::from_utf8(out.stdout).ok()?;
    out.status
        .success()
        .then(|| tag.trim().trim_start_matches('v').to_owned())
}

/// `2.0.0` as `2.0.1-dev`.
fn next_dev(released: &str) -> String {
    let parts: Vec<u64> = released.split('.').filter_map(|p| p.parse().ok()).collect();
    let [major, minor, patch] = parts[..] else {
        panic!("the release tag {released:?} names no x.y.z");
    };
    format!("{major}.{minor}.{}-dev", patch + 1)
}
