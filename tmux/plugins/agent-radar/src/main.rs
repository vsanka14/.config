use agent_radar::boundary::{self, Config, RowMode};
use std::env;
use std::io;
use std::process::ExitCode;

#[derive(Debug, Eq, PartialEq)]
enum Command {
    Popup,
    Preview(String),
    List,
    TmuxStatus(String),
    TmuxStatusCached(String),
    NotifyLines,
    AcknowledgePane(String),
    Refresh { notify: bool },
    Hook(Option<String>),
    SetupInstall,
    SetupDoctor,
}

fn parse_command(args: &[String]) -> Result<Command, String> {
    match args {
        [] => Ok(Command::Popup),
        [command, pane] if command == "preview" => Ok(Command::Preview(pane.clone())),
        [command] if command == "--list" => Ok(Command::List),
        [command, session] if command == "--tmux-status" => Ok(Command::TmuxStatus(session.clone())),
        [command, session] if command == "--tmux-status-cached" => {
            Ok(Command::TmuxStatusCached(session.clone()))
        }
        [command] if command == "--notify-lines" => Ok(Command::NotifyLines),
        [command, pane] if command == "--ack-pane" => Ok(Command::AcknowledgePane(pane.clone())),
        [command] if command == "--refresh" => Ok(Command::Refresh { notify: false }),
        [command, notify] if command == "--refresh" && notify == "--notify" => {
            Ok(Command::Refresh { notify: true })
        }
        [command] if command == "hook" => Ok(Command::Hook(None)),
        [command, event] if command == "hook" => Ok(Command::Hook(Some(event.clone()))),
        [command, action] if command == "setup" && action == "install" => Ok(Command::SetupInstall),
        [command, action] if command == "setup" && action == "doctor" => Ok(Command::SetupDoctor),
        _ => Err("usage: agent-radar [preview PANE_ID|--list|--tmux-status SESSION|--tmux-status-cached SESSION|--notify-lines|--ack-pane PANE_ID|--refresh [--notify]|hook EVENT|setup <install|doctor>]".into()),
    }
}

fn dispatch(command: Command, config: &Config) -> Result<(), String> {
    match command {
        Command::Popup => boundary::open_popup(config),
        Command::Preview(pane) => {
            print!("{}", boundary::preview(config, &pane)?);
            Ok(())
        }
        Command::List => print_line(
            boundary::rows_text(
                config,
                RowMode::Full,
                env::var("NO_COLOR").ok().as_deref() != Some("1"),
            )
            .map_err(|error| error.to_string())?,
        ),
        Command::TmuxStatus(session) => print_value(boundary::status(config, &session)),
        Command::TmuxStatusCached(session) => {
            print_value(boundary::cached_status(config, &session))
        }
        Command::NotifyLines => {
            print_line(boundary::notification_text(config).map_err(|error| error.to_string())?)
        }
        Command::AcknowledgePane(pane) => {
            if boundary::acknowledge(config, &pane).map_err(|error| error.to_string())? {
                boundary::refresh(config, true).map_err(|error| error.to_string())?;
            }
            Ok(())
        }
        Command::Refresh { notify } => {
            boundary::refresh(config, notify).map_err(|error| error.to_string())
        }
        Command::Hook(event) => match boundary::hook(config, event.as_deref(), &mut io::stdin()) {
            Ok(()) => Ok(()),
            Err(error) if env::var_os("AGENT_RADAR_HOOK_DEBUG").is_some() => Err(error.to_string()),
            Err(_) => Ok(()),
        },
        Command::SetupInstall => {
            let descriptor = boundary::install_default(config)?;
            println!("installed {}", descriptor.display());
            Ok(())
        }
        Command::SetupDoctor => {
            let (output, ok) = boundary::doctor_default(config)?;
            println!("{output}");
            ok.then_some(())
                .ok_or_else(|| "doctor found problems".into())
        }
    }
}

fn print_value(value: io::Result<String>) -> Result<(), String> {
    print!("{}", value.map_err(|error| error.to_string())?);
    Ok(())
}

fn print_line(value: String) -> Result<(), String> {
    if !value.is_empty() {
        println!("{value}");
    }
    Ok(())
}

fn main() -> ExitCode {
    let args: Vec<String> = env::args().skip(1).collect();
    match parse_command(&args).and_then(|command| dispatch(command, &Config::from_env())) {
        Ok(()) => ExitCode::SUCCESS,
        Err(message) => {
            eprintln!("agent-radar: {message}");
            ExitCode::from(1)
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn accepts_the_complete_contract_command_shape() {
        assert_eq!(parse_command(&[]), Ok(Command::Popup));
        assert_eq!(
            parse_command(&["--refresh".into(), "--notify".into()]),
            Ok(Command::Refresh { notify: true })
        );
        assert_eq!(parse_command(&["hook".into()]), Ok(Command::Hook(None)));
        assert_eq!(
            parse_command(&["setup".into(), "doctor".into()]),
            Ok(Command::SetupDoctor)
        );
    }
}
