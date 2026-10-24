//! A module to open, or the version or glyphs for the build.

use std::io::IsTerminal;
use std::process::ExitCode;

use crate::spec;

const PROGRAM: &str = env!("CARGO_PKG_NAME");

fn help() -> String {
    let modules = spec::loaded()
        .modules
        .iter()
        .map(|m| m.id.as_str())
        .collect::<Vec<_>>()
        .join(", ");
    format!(
        "{PROGRAM} <module> [--dry-run] [--kiosk] [--unattended]\n{PROGRAM} glyphs\n{PROGRAM} --version\n\n<module>      {modules}\n--dry-run     show the run, start nothing\n--kiosk       the machine's only program: leaving restarts it\n--unattended  the work with the answers in <module>.conf and the passwords in the environment, nobody at the keyboard\nglyphs        every character the interface draws on a console\n"
    )
}

pub struct Start {
    pub module: &'static spec::Module,
    pub dry_run: bool,
    pub kiosk: bool,
    /// Answers from the answer file, passwords from the environment.
    pub unattended: bool,
}

enum Ask {
    Help,
    Version,
    Glyphs,
    Run(Start),
}

fn parse(args: impl IntoIterator<Item = String>) -> Result<Ask, String> {
    let (mut module, mut dry_run, mut kiosk, mut unattended, mut glyphs) =
        (None, false, false, false, false);
    for arg in args {
        match arg.as_str() {
            "-h" | "--help" => return Ok(Ask::Help),
            "-V" | "--version" => return Ok(Ask::Version),
            "--dry-run" => dry_run = true,
            "--kiosk" => kiosk = true,
            "--unattended" => unattended = true,
            "glyphs" => glyphs = true,
            a if a.starts_with('-') => return Err(format!("unknown argument {a}")),
            id => match spec::loaded().module(id) {
                Some(m) if module.is_none() => module = Some(m),
                Some(_) => return Err("one module at a time".into()),
                None => return Err(format!("no module called {id}")),
            },
        }
    }
    if glyphs {
        return Ok(Ask::Glyphs);
    }
    let module = module.ok_or("name a module")?;
    // A kiosk restarts after its run, an unattended run exits.
    if kiosk && unattended {
        return Err("--kiosk and --unattended do not go together".into());
    }
    Ok(Ask::Run(Start {
        module,
        dry_run,
        kiosk,
        unattended,
    }))
}

pub fn main() -> ExitCode {
    let start = match parse(std::env::args().skip(1)) {
        Ok(Ask::Help) => {
            print!("{}", help());
            return ExitCode::SUCCESS;
        }
        Ok(Ask::Version) => {
            println!("{PROGRAM} {}", crate::version::version());
            return ExitCode::SUCCESS;
        }
        Ok(Ask::Glyphs) => {
            println!("{}", crate::ui::glyphs());
            return ExitCode::SUCCESS;
        }
        Ok(Ask::Run(start)) => start,
        Err(why) => {
            eprint!("{PROGRAM}: {why}\n\n{}", help());
            return ExitCode::from(64);
        }
    };
    if start.unattended {
        let result = crate::unattended::run(start);
        crate::script::cleanup();
        return match result {
            Ok(true) => ExitCode::SUCCESS,
            Ok(false) => ExitCode::FAILURE,
            Err(e) => {
                eprintln!("{PROGRAM}: {e}");
                ExitCode::FAILURE
            }
        };
    }
    if !std::io::stdin().is_terminal() || !std::io::stdout().is_terminal() {
        eprintln!("{PROGRAM}: needs a terminal");
        return ExitCode::FAILURE;
    }
    let result = crate::term::run(start);
    crate::script::cleanup();
    match result {
        Ok(()) => ExitCode::SUCCESS,
        Err(e) => {
            crate::error!("{e}");
            eprintln!("{PROGRAM}: {e}");
            ExitCode::FAILURE
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn ask(args: &[&str]) -> Result<Ask, String> {
        parse(args.iter().map(|a| a.to_string()))
    }

    #[test]
    fn the_command_line_opens_one_module_with_its_switches() {
        let modules = &spec::loaded().modules;
        let (one, other) = (modules[0].id.as_str(), modules[1].id.as_str());
        let Ok(Ask::Run(start)) = ask(&[one, "--dry-run"]) else {
            panic!("{one} --dry-run starts nothing");
        };
        assert_eq!(
            (start.module.id.as_str(), start.dry_run, start.kiosk),
            (one, true, false)
        );
        let Ok(Ask::Run(start)) = ask(&["--kiosk", other]) else {
            panic!("--kiosk {other} starts nothing");
        };
        assert_eq!((start.module.id.as_str(), start.kiosk), (other, true));
        let Ok(Ask::Run(start)) = ask(&[one, "--unattended"]) else {
            panic!("{one} --unattended starts nothing");
        };
        assert!(start.unattended && !start.kiosk);
        assert!(matches!(ask(&["--help", "nope"]), Ok(Ask::Help)));
        assert!(matches!(ask(&["-V"]), Ok(Ask::Version)));
        assert!(matches!(ask(&[one, "glyphs"]), Ok(Ask::Glyphs)));
        for (args, why) in [
            (&[one, other][..], "one module at a time".to_string()),
            (
                &["--language=de"][..],
                "unknown argument --language=de".into(),
            ),
            (&["nope"][..], "no module called nope".into()),
            (&[][..], "name a module".into()),
            (
                &["--kiosk", "--unattended", one][..],
                "--kiosk and --unattended do not go together".into(),
            ),
        ] {
            assert_eq!(ask(args).err(), Some(why), "{args:?}");
        }
    }
}
