//! ark-dash — Executive dashboard for the agentic operating system
//!
//! Real-time TUI showing all projects, agents (employees), events, and metrics.
//! Pluggable employee registry: drop a JSON file in vault/employees/ to add a role.

mod app;
mod employees;
mod ui;
mod vault;

use anyhow::Result;
use clap::Parser;
use crossterm::{
    event::{self, DisableMouseCapture, EnableMouseCapture, Event, KeyCode},
    execute,
    terminal::{disable_raw_mode, enable_raw_mode, EnterAlternateScreen, LeaveAlternateScreen},
};
use ratatui::{backend::CrosstermBackend, Terminal};
use std::{io, path::PathBuf, time::Duration};

#[derive(Parser, Debug)]
#[command(name = "ark-dash")]
#[command(about = "Executive dashboard for Ark OS — agentic operating system")]
struct Args {
    /// Path to projects directory (default: ~/code)
    #[arg(short, long, default_value = "~/code")]
    projects: String,

    /// Path to vault (default: ~/vaults/automation-brain)
    #[arg(short, long, default_value = "~/vaults/automation-brain")]
    vault: String,

    /// Refresh interval in milliseconds
    #[arg(short, long, default_value_t = 2000)]
    refresh: u64,
}

fn expand_tilde(p: &str) -> PathBuf {
    if let Some(rest) = p.strip_prefix("~/") {
        if let Some(home) = std::env::var_os("HOME") {
            return PathBuf::from(home).join(rest);
        }
    }
    PathBuf::from(p)
}

fn main() -> Result<()> {
    let args = Args::parse();
    let projects_path = expand_tilde(&args.projects);
    let vault_path = expand_tilde(&args.vault);

    enable_raw_mode()?;
    let mut stdout = io::stdout();
    execute!(stdout, EnterAlternateScreen, EnableMouseCapture)?;
    let backend = CrosstermBackend::new(stdout);
    let mut terminal = Terminal::new(backend)?;

    let res = run_app(
        &mut terminal,
        projects_path,
        vault_path,
        Duration::from_millis(args.refresh),
    );

    disable_raw_mode()?;
    execute!(
        terminal.backend_mut(),
        LeaveAlternateScreen,
        DisableMouseCapture
    )?;
    terminal.show_cursor()?;

    if let Err(err) = res {
        eprintln!("Error: {err:?}");
    }

    Ok(())
}

fn run_app<B: ratatui::backend::Backend>(
    terminal: &mut Terminal<B>,
    projects_path: PathBuf,
    vault_path: PathBuf,
    refresh: Duration,
) -> Result<()> {
    let mut app = app::App::new(projects_path, vault_path);
    app.refresh_state();

    let mut last_refresh = std::time::Instant::now();

    loop {
        terminal.draw(|f| ui::render(f, &app))?;

        let timeout = refresh
            .checked_sub(last_refresh.elapsed())
            .unwrap_or_else(|| Duration::from_millis(0));

        if event::poll(timeout)? {
            if let Event::Key(key) = event::read()? {
                match key.code {
                    KeyCode::Char('q') | KeyCode::Esc => return Ok(()),
                    KeyCode::Char('r') => app.refresh_state(),
                    KeyCode::Tab => app.next_tab(),
                    KeyCode::BackTab => app.prev_tab(),
                    KeyCode::Down | KeyCode::Char('j') => app.select_next(),
                    KeyCode::Up | KeyCode::Char('k') => app.select_prev(),
                    KeyCode::Char('h') => app.toggle_help(),
                    _ => {}
                }
            }
        }

        if last_refresh.elapsed() >= refresh {
            app.refresh_state();
            last_refresh = std::time::Instant::now();
        }
    }
}
