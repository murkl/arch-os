pub fn version() -> &'static str {
    env!("VERSION")
}

#[cfg(test)]
mod tests {
    #[test]
    fn is_a_release_or_a_pre_release() {
        let (release, pre) = super::version()
            .split_once('-')
            .unwrap_or((super::version(), "dev"));
        assert_eq!(pre, "dev");
        let parts: Vec<&str> = release.split('.').collect();
        assert_eq!(parts.len(), 3, "{release}");
        assert!(parts.iter().all(|p| p.parse::<u64>().is_ok()), "{release}");
    }
}
