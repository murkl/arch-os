//! What runs when inside one stage: a task runs after what it names in `needs`. Tasks no `needs`
//! separates keep the order their folders sort in.

/// The indices of `tasks` in the order they run, or the ring that keeps them waiting.
pub fn order(tasks: &[(String, Vec<String>)]) -> Result<Vec<usize>, String> {
    let mut out = Vec::with_capacity(tasks.len());
    let mut done = vec![false; tasks.len()];
    while out.len() < tasks.len() {
        let next = (0..tasks.len()).find(|&i| {
            !done[i]
                && tasks[i].1.iter().all(|n| {
                    tasks
                        .iter()
                        .position(|t| t.0 == *n)
                        .is_some_and(|j| done[j])
                })
        });
        match next {
            Some(i) => {
                out.push(i);
                done[i] = true;
            }
            None => return Err(format!("tasks wait on each other: {}", ring(tasks, &done))),
        }
    }
    Ok(out)
}

/// The ring the tasks left are waiting round, in the order they wait.
fn ring(tasks: &[(String, Vec<String>)], done: &[bool]) -> String {
    let mut path: Vec<&str> = Vec::new();
    let mut at = tasks.iter().position(|_| true).map(|_| {
        (0..tasks.len())
            .find(|&i| !done[i])
            .map(|i| tasks[i].0.as_str())
            .unwrap_or_default()
    });
    while let Some(name) = at.filter(|n| !n.is_empty()) {
        if let Some(i) = path.iter().position(|p| *p == name) {
            path.push(name);
            return path[i..].join(" → ");
        }
        path.push(name);
        at = tasks.iter().find(|t| t.0 == name).and_then(|t| {
            let mut waiting: Vec<&str> =
                t.1.iter()
                    .filter(|n| {
                        tasks
                            .iter()
                            .position(|o| o.0 == **n)
                            .is_some_and(|j| !done[j])
                    })
                    .map(String::as_str)
                    .collect();
            waiting.sort();
            waiting.first().copied()
        });
    }
    path.join(" → ")
}

#[cfg(test)]
mod tests {
    use super::*;

    fn t(name: &str, needs: &[&str]) -> (String, Vec<String>) {
        (name.into(), needs.iter().map(|n| n.to_string()).collect())
    }

    #[test]
    fn needs_order_and_a_ring_is_named() {
        let tasks = [t("c", &["a"]), t("a", &[]), t("b", &["c", "a"])];
        assert_eq!(order(&tasks).unwrap(), [1, 0, 2]);
        let ring = [t("a", &["b"]), t("b", &["c"]), t("c", &["a"])];
        assert_eq!(
            order(&ring).unwrap_err(),
            "tasks wait on each other: a → b → c → a"
        );
    }
}
