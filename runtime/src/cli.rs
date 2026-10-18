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
        "{PROGRAM} <module> [--dry-run] [--kiosk]\n{PROGRAM} glyphs\n{PROGRAM} --version\n\n<module>   {modules}\n--dry-run  show the run, start nothing\n--kiosk    the machine is only this: leaving starts it again\nglyphs     every character the interface draws on a console\n"
    )
}

/// What a run was started with.
pub struct Start {
    pub module: &'static spec::Module,
    pub dry_run: bool,
    pub kiosk: bool,
}

pub fn main() -> ExitCode {
    let mut module = None;
    let mut dry_run = false;
    let mut kiosk = false;
    let mut glyphs = false;
    for arg in std::env::args().skip(1) {
        match arg.as_str() {
            "-h" | "--help" => {
                print!("{}", help());
                return ExitCode::SUCCESS;
            }
            "-V" | "--version" => {
                println!("{PROGRAM} {}", crate::version::version());
                return ExitCode::SUCCESS;
            }
            "--dry-run" => dry_run = true,
            "--kiosk" => kiosk = true,
            "glyphs" => glyphs = true,
            a if a.starts_with('-') => {
                eprint!("{PROGRAM}: unknown argument {a}\n\n{}", help());
                return ExitCode::from(64);
            }
            id => match spec::loaded().module(id) {
                Some(m) if module.is_none() => module = Some(m),
                Some(_) => {
                    eprint!("{PROGRAM}: one module at a time\n\n{}", help());
                    return ExitCode::from(64);
                }
                None => {
                    eprint!("{PROGRAM}: no module called {id}\n\n{}", help());
                    return ExitCode::from(64);
                }
            },
        }
    }
    if glyphs {
        println!("{}", crate::ui::glyphs());
        return ExitCode::SUCCESS;
    }
    let Some(module) = module else {
        eprint!("{PROGRAM}: name a module\n\n{}", help());
        return ExitCode::from(64);
    };
    if !std::io::stdin().is_terminal() || !std::io::stdout().is_terminal() {
        eprintln!("{PROGRAM}: needs a terminal");
        return ExitCode::FAILURE;
    }
    let result = crate::term::run(Start {
        module,
        dry_run,
        kiosk,
    });
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
