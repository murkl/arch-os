//! The sentences a declaration writes: paragraphs, and the `{{NAME}}` filled in from the answers.

/// Joins the lines of each paragraph and keeps the blank lines between them, so the text shown
/// and the key a catalog looks it up by are one string however the yaml wrapped it.
pub fn reflow(s: &str) -> String {
    s.split("\n\n")
        .map(|p| p.split_whitespace().collect::<Vec<_>>().join(" "))
        .filter(|p| !p.is_empty())
        .collect::<Vec<_>>()
        .join("\n\n")
}

/// The first paragraph, and the rest.
pub fn split(s: &str) -> (&str, &str) {
    match s.split_once("\n\n") {
        Some((head, body)) => (head, body),
        None => (s, ""),
    }
}

/// Fills `{{NAME}}` from `get`. A name nothing answers is left empty, which the loader rules
/// out for a name no setting declares.
pub fn expand(s: &str, get: impl Fn(&str) -> String) -> String {
    let mut out = String::new();
    let mut rest = s;
    while let Some(i) = rest.find("{{") {
        let Some(j) = rest[i..].find("}}") else { break };
        out.push_str(&rest[..i]);
        out.push_str(&get(rest[i + 2..i + j].trim()));
        rest = &rest[i + j + 2..];
    }
    out + rest
}

/// Every `{{NAME}}` a text asks for, in order, once each.
pub fn names(s: &str) -> Vec<String> {
    let mut out: Vec<String> = Vec::new();
    let mut rest = s;
    while let Some(i) = rest.find("{{") {
        let Some(j) = rest[i..].find("}}") else { break };
        let name = rest[i + 2..i + j].trim().to_string();
        if !out.contains(&name) {
            out.push(name);
        }
        rest = &rest[i + j + 2..];
    }
    out
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn reflows_paragraphs_and_fills_names() {
        assert_eq!(reflow("A\n  b\n\n\n c\n"), "A b\n\nc");
        assert_eq!(
            split("Head\n\nBody one\n\nBody two"),
            ("Head", "Body one\n\nBody two")
        );
        assert_eq!(split("Only"), ("Only", ""));
        assert_eq!(
            expand("On {{ DISK }} for {{USER}} {{", |n| n.to_lowercase()),
            "On disk for user {{"
        );
        assert_eq!(names("{{A}} and {{B}}, {{A}} again"), ["A", "B"]);
    }
}
