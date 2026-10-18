//! One line of `when:`: a setting, `==` or `!=`, a value. Every line must hold, and there is no
//! or: a row for two unrelated cases is two rows.

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct Condition {
    pub name: String,
    pub equal: bool,
    pub want: String,
}

impl Condition {
    pub fn parse(s: &str) -> Result<Condition, String> {
        let f: Vec<&str> = s.split_whitespace().collect();
        if f.len() != 3 || (f[1] != "==" && f[1] != "!=") {
            return Err(format!(
                "{s:?} is no condition: NAME == value or NAME != value"
            ));
        }
        Ok(Condition {
            name: f[0].to_string(),
            equal: f[1] == "==",
            want: f[2].trim_matches(['"', '\'']).to_string(),
        })
    }

    pub fn holds_for(&self, value: &str) -> bool {
        (value == self.want) == self.equal
    }

    pub fn holds(&self, get: impl Fn(&str) -> String) -> bool {
        self.holds_for(&get(&self.name))
    }
}

impl std::fmt::Display for Condition {
    fn fmt(&self, f: &mut std::fmt::Formatter) -> std::fmt::Result {
        let op = if self.equal { "==" } else { "!=" };
        write!(f, "{} {op} {}", self.name, self.want)
    }
}

/// Whether every condition holds. None always do.
pub fn hold_all(conds: &[Condition], get: impl Fn(&str) -> String) -> bool {
    conds.iter().all(|c| c.holds(&get))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn parses_and_holds() {
        let c = Condition::parse("X_DESKTOP != none").unwrap();
        assert_eq!(c.to_string(), "X_DESKTOP != none");
        assert!(c.holds_for("gnome") && !c.holds_for("none"));
        assert!(Condition::parse("X_DESKTOP = none").is_err());
        assert!(Condition::parse("X_DESKTOP").is_err());
        let eq = Condition::parse("A == 'x'").unwrap();
        assert!(eq.holds(|_| "x".into()));
    }
}
