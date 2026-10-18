//! English source strings, every other language from `locales/<code>.po`. The English sentence
//! is the key, so a missing translation leaves readable English rather than a key.

use std::collections::HashMap;
use std::fmt::Display;
use std::sync::OnceLock;
use std::sync::atomic::{AtomicUsize, Ordering};

pub const SOURCE: &str = "en";

/// One language on offer: its code, and the name it calls itself, which is its translation of
/// "English".
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct Lang {
    pub code: String,
    pub name: String,
}

struct Catalog {
    lang: Lang,
    messages: HashMap<String, &'static str>,
}

/// The source language first, then every embedded catalog by the name it calls itself.
fn catalogs() -> &'static [Catalog] {
    static ALL: OnceLock<Vec<Catalog>> = OnceLock::new();
    ALL.get_or_init(|| {
        let mut all = vec![Catalog {
            lang: Lang {
                code: SOURCE.into(),
                name: "English".into(),
            },
            messages: HashMap::new(),
        }];
        let mut found: Vec<Catalog> = crate::embedded::FILES
            .iter()
            .filter_map(|(path, bytes)| {
                let code = path.strip_prefix("locales/")?.strip_suffix(".po")?;
                let messages: HashMap<String, &'static str> =
                    parse_po(std::str::from_utf8(bytes).ok()?)
                        .into_iter()
                        .map(|(k, v)| (k, &*Box::leak(v.into_boxed_str())))
                        .collect();
                let name = messages
                    .get("English")
                    .map(|n| n.to_string())
                    .unwrap_or_else(|| code.to_uppercase());
                Some(Catalog {
                    lang: Lang {
                        code: code.to_string(),
                        name,
                    },
                    messages,
                })
            })
            .collect();
        found.sort_by(|a, b| a.lang.name.cmp(&b.lang.name));
        all.extend(found);
        all
    })
}

pub fn langs() -> Vec<Lang> {
    catalogs().iter().map(|c| c.lang.clone()).collect()
}

static CURRENT: AtomicUsize = AtomicUsize::new(0);

/// Held by tests that switch the language or read English text, which share one process.
#[cfg(test)]
pub static LOCK: std::sync::Mutex<()> = std::sync::Mutex::new(());

/// Puts the interface in a language. A code no catalog has leaves the source language.
pub fn set(code: &str) {
    let at = catalogs()
        .iter()
        .position(|c| c.lang.code == code)
        .unwrap_or(0);
    CURRENT.store(at, Ordering::Relaxed);
}

pub fn current() -> &'static Lang {
    &catalogs()[CURRENT.load(Ordering::Relaxed)].lang
}

/// The best of the languages for a locale as the environment writes one, `de_DE.UTF-8` or
/// `de`: the exact code, then the part before the underscore.
pub fn matched(locale: &str) -> Option<&'static str> {
    let locale = locale.trim().to_lowercase();
    let locale = locale
        .split(['.', '@'])
        .next()
        .unwrap_or_default()
        .replace('_', "-");
    if locale.is_empty() || locale == "c" || locale == "posix" {
        return None;
    }
    let codes = catalogs().iter().map(|c| c.lang.code.as_str());
    let exact = codes.clone().find(|c| c.eq_ignore_ascii_case(&locale));
    let base = locale.split('-').next().unwrap_or_default();
    exact.or_else(|| codes.into_iter().find(|c| c.eq_ignore_ascii_case(base)))
}

/// The language of messages as the environment sets it, the way gettext reads it.
pub fn detect() -> &'static str {
    ["LC_ALL", "LC_MESSAGES", "LANG"]
        .iter()
        .filter_map(|k| std::env::var(k).ok())
        .find(|v| !v.is_empty())
        .and_then(|v| matched(&v))
        .unwrap_or(SOURCE)
}

pub fn t(msgid: &str) -> String {
    tr(msgid).to_string()
}

fn tr(msgid: &str) -> &str {
    let at = CURRENT.load(Ordering::Relaxed);
    if at == 0 {
        return msgid;
    }
    catalogs()[at].messages.get(msgid).copied().unwrap_or(msgid)
}

/// Translates, then fills `{{name}}` placeholders.
pub fn tf(msgid: &str, args: &[(&str, &dyn Display)]) -> String {
    let mut out = tr(msgid).to_string();
    for (name, value) in args {
        out = out.replace(&format!("{{{{{name}}}}}"), &value.to_string());
    }
    out
}

/// msgid → msgstr, without the header and without untranslated entries.
pub fn parse_po(src: &str) -> HashMap<String, String> {
    let mut map = HashMap::new();
    let (mut id, mut text) = (String::new(), String::new());
    let mut target: Option<bool> = None; // Some(false) msgid, Some(true) msgstr
    let mut flush = |id: &mut String, text: &mut String| {
        if !id.is_empty() && !text.is_empty() {
            map.insert(std::mem::take(id), std::mem::take(text));
        }
        id.clear();
        text.clear();
    };
    for line in src.lines().map(str::trim) {
        if let Some(rest) = line.strip_prefix("msgid ") {
            flush(&mut id, &mut text);
            id = unquote(rest);
            target = Some(false);
        } else if let Some(rest) = line.strip_prefix("msgstr ") {
            text = unquote(rest);
            target = Some(true);
        } else if line.starts_with('"') {
            match target {
                Some(false) => id += &unquote(line),
                Some(true) => text += &unquote(line),
                None => {}
            }
        } else if line.is_empty() || line.starts_with('#') {
            target = None;
        }
    }
    flush(&mut id, &mut text);
    map
}

/// One quote off each end: a quote before the closing one is text.
fn unquote(s: &str) -> String {
    let s = s.trim();
    let inner = s.strip_prefix('"').unwrap_or(s);
    let inner = inner.strip_suffix('"').unwrap_or(inner);
    let mut out = String::new();
    let mut chars = inner.chars();
    while let Some(c) = chars.next() {
        if c != '\\' {
            out.push(c);
            continue;
        }
        match chars.next() {
            Some('n') => out.push('\n'),
            Some('t') => out.push('\t'),
            Some(other) => out.push(other),
            None => {}
        }
    }
    out
}

/// Every translation of every embedded catalog, for what the console has to be able to draw.
pub fn translations() -> Vec<&'static str> {
    catalogs()
        .iter()
        .flat_map(|c| c.messages.values().copied())
        .collect()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn parses_multiline_entries_and_escapes() {
        let po = r#"
msgid ""
msgstr "Content-Type: text/plain; charset=UTF-8\n"

msgid "One"
msgstr "Eins"

msgid ""
"Two "
"lines\n"
msgstr ""
"Zwei "
"\"Zeilen\"\n"

msgid "Say \"hi\""
msgstr "Sag \"hallo\""

msgid "Open"
msgstr ""
"#;
        let map = parse_po(po);
        assert_eq!(
            map.get("Say \"hi\"").map(String::as_str),
            Some("Sag \"hallo\""),
            "a quote at the end is text"
        );
        assert_eq!(map.get("One").map(String::as_str), Some("Eins"));
        assert_eq!(
            map.get("Two lines\n").map(String::as_str),
            Some("Zwei \"Zeilen\"\n")
        );
        assert!(
            !map.contains_key("Open"),
            "untranslated entries fall back to English"
        );
        assert!(!map.contains_key(""), "the header is no entry");
    }

    #[test]
    fn matches_a_locale_to_a_catalog() {
        assert_eq!(matched("en_US.UTF-8"), Some("en"));
        assert_eq!(matched("C"), None);
        assert_eq!(matched(""), None);
        assert_eq!(matched("fr_FR"), None);
    }

    #[test]
    fn fills_placeholders() {
        let _lang = LOCK.lock().unwrap_or_else(|e| e.into_inner());
        set(SOURCE);
        assert_eq!(
            tf("{{a}} of {{b}}", &[("a", &1), ("b", &"two")]),
            "1 of two"
        );
    }
}

/// A string literal's text, from just after its opening quote, and what follows it.
#[cfg(test)]
fn literal_at(src: &str) -> (String, &str) {
    let mut text = String::new();
    let mut chars = src.char_indices();
    while let Some((i, c)) = chars.next() {
        match c {
            '"' => return (text, &src[i + 1..]),
            '\\' => match chars.next() {
                Some((_, 'n')) => text.push('\n'),
                Some((_, other)) => text.push(other),
                None => {}
            },
            _ => text.push(c),
        }
    }
    (text, "")
}

/// Every msgid the program uses: the literals given to t and tf, the language's own name, and
/// the texts of the product.
#[cfg(test)]
pub fn used() -> std::collections::BTreeSet<String> {
    let mut ids = std::collections::BTreeSet::new();
    let mut stack = vec![std::path::PathBuf::from(concat!(
        env!("CARGO_MANIFEST_DIR"),
        "/src"
    ))];
    while let Some(path) = stack.pop() {
        if path.is_dir() {
            stack.extend(std::fs::read_dir(&path).unwrap().map(|e| e.unwrap().path()));
            continue;
        }
        let src = std::fs::read_to_string(&path).unwrap();
        // The program's part of the file: the tests under it translate texts of their own.
        let src = ["#[cfg(test)]\nmod ", "#[cfg(test)]\npub mod "]
            .iter()
            .filter_map(|m| src.find(m))
            .min()
            .map_or(src.as_str(), |at| &src[..at]);
        for call in ["t(", "tf("] {
            for (i, _) in src.match_indices(call) {
                let before = src[..i].chars().last().unwrap_or(' ');
                if before.is_alphanumeric() || before == '_' {
                    continue;
                }
                // A literal, possibly on the next line where rustfmt put it.
                if let Some(literal) = src[i + call.len()..].trim_start().strip_prefix('"') {
                    ids.insert(literal_at(literal).0);
                }
            }
        }
    }
    ids.insert("English".into());
    ids.extend(crate::spec::loaded().texts());
    ids
}

#[cfg(test)]
mod catalog {
    use super::*;

    fn placeholders(s: &str) -> Vec<String> {
        let mut v = crate::spec::text::names(s);
        v.sort();
        v
    }

    /// Every catalog covers every text exactly, and keeps its placeholders.
    #[test]
    fn every_catalog_covers_every_text_exactly_and_keeps_its_placeholders() {
        let used = used();
        for (path, bytes) in crate::embedded::FILES {
            let Some(code) = path
                .strip_prefix("locales/")
                .and_then(|p| p.strip_suffix(".po"))
            else {
                continue;
            };
            let po = parse_po(std::str::from_utf8(bytes).unwrap());
            let missing: Vec<&String> = used.iter().filter(|id| !po.contains_key(*id)).collect();
            assert!(
                missing.is_empty(),
                "not in locales/{code}.po:\n{}",
                missing
                    .iter()
                    .map(|m| format!("{m:?}"))
                    .collect::<Vec<_>>()
                    .join("\n")
            );
            let unused: Vec<&String> = po.keys().filter(|id| !used.contains(*id)).collect();
            assert!(
                unused.is_empty(),
                "in locales/{code}.po but used nowhere: {unused:?}"
            );
            for (id, text) in &po {
                assert_eq!(
                    placeholders(id),
                    placeholders(text),
                    "placeholders differ: {id:?}"
                );
            }
        }
    }
}
