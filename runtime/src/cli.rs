//! The command line: a module to open, or one of two answers for the build.

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
        "{PROGRAM} <module> [--dry-run] [--kiosk]\n{PROGRAM} glyphs\n{PROGRAM} --version\n\n<module>   {modules}\n--dry-run  show the run, start nothing\n--kiosk    the machine's only program: leaving restarts it\nglyphs     every character the interface draws on a console\n"
    )
}

/// What a run was started with.
pub struct Start {
    pub module: &'static spec::Module,
    pub dry_run: bool,
    pub kiosk: bool,
}

/// What the command line asks for.
enum Ask {
    Help,
    Version,
    Glyphs,
    Run(Start),
}

/// The arguments after the program's name, or why they ask for nothing it does.
fn parse(args: impl IntoIterator<Item = String>) -> Result<Ask, String> {
    let (mut module, mut dry_run, mut kiosk, mut glyphs) = (None, false, false, false);
    for arg in args {
        match arg.as_str() {
            "-h" | "--help" => return Ok(Ask::Help),
            "-V" | "--version" => return Ok(Ask::Version),
            "--dry-run" => dry_run = true,
            "--kiosk" => kiosk = true,
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
    Ok(Ask::Run(Start {
        module,
        dry_run,
        kiosk,
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
        ] {
            assert_eq!(ask(args).err(), Some(why), "{args:?}");
        }
    }
}
