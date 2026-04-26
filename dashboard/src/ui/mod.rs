//! UI rendering

mod employees;
mod events;
mod metrics;
mod projects;

use crate::app::{App, Tab};
use ratatui::{
    layout::{Constraint, Direction, Layout, Rect},
    style::{Color, Modifier, Style},
    text::{Line, Span},
    widgets::{Block, Borders, Paragraph, Tabs},
    Frame,
};

pub fn render(f: &mut Frame, app: &App) {
    let chunks = Layout::default()
        .direction(Direction::Vertical)
        .margin(0)
        .constraints([
            Constraint::Length(3),  // Header / tabs
            Constraint::Min(0),     // Body
            Constraint::Length(2),  // Footer / help
        ])
        .split(f.area());

    render_header(f, app, chunks[0]);
    render_body(f, app, chunks[1]);
    render_footer(f, app, chunks[2]);

    if app.show_help {
        render_help_overlay(f);
    }
}

fn render_header(f: &mut Frame, app: &App, area: Rect) {
    let titles = vec!["Projects", "Employees", "Events", "Metrics"];
    let selected = match app.current_tab {
        Tab::Projects => 0,
        Tab::Employees => 1,
        Tab::Events => 2,
        Tab::Metrics => 3,
    };

    let title = format!("🧠 BRAIN OS — Executive Dashboard │ refresh {}", app.last_refresh);
    let tabs = Tabs::new(titles.into_iter().map(Line::from).collect::<Vec<_>>())
        .block(
            Block::default()
                .borders(Borders::ALL)
                .title(title)
                .title_style(Style::default().fg(Color::Cyan).add_modifier(Modifier::BOLD)),
        )
        .select(selected)
        .style(Style::default().fg(Color::Gray))
        .highlight_style(
            Style::default()
                .fg(Color::Black)
                .bg(Color::Cyan)
                .add_modifier(Modifier::BOLD),
        );

    f.render_widget(tabs, area);
}

fn render_body(f: &mut Frame, app: &App, area: Rect) {
    match app.current_tab {
        Tab::Projects => projects::render(f, app, area),
        Tab::Employees => employees::render(f, app, area),
        Tab::Events => events::render(f, app, area),
        Tab::Metrics => metrics::render(f, app, area),
    }
}

fn render_footer(f: &mut Frame, _app: &App, area: Rect) {
    let help = Paragraph::new(Line::from(vec![
        Span::styled("↹/Tab", Style::default().fg(Color::Yellow)),
        Span::raw(" switch panel │ "),
        Span::styled("↑↓/jk", Style::default().fg(Color::Yellow)),
        Span::raw(" navigate │ "),
        Span::styled("r", Style::default().fg(Color::Yellow)),
        Span::raw(" refresh │ "),
        Span::styled("h", Style::default().fg(Color::Yellow)),
        Span::raw(" help │ "),
        Span::styled("q", Style::default().fg(Color::Yellow)),
        Span::raw(" quit"),
    ]))
    .style(Style::default().fg(Color::DarkGray));
    f.render_widget(help, area);
}

fn render_help_overlay(f: &mut Frame) {
    let area = centered_rect(60, 60, f.area());
    let help_text = vec![
        Line::from(""),
        Line::from(vec![Span::styled(
            "  Ark OS — Executive Dashboard",
            Style::default().fg(Color::Cyan).add_modifier(Modifier::BOLD),
        )]),
        Line::from(""),
        Line::from("  Navigation:"),
        Line::from("    Tab / Shift-Tab  Switch panel"),
        Line::from("    ↑↓ or j/k         Move selection"),
        Line::from("    r                 Force refresh"),
        Line::from("    h                 Toggle this help"),
        Line::from("    q / Esc           Quit"),
        Line::from(""),
        Line::from("  Panels:"),
        Line::from("    Projects  All brain-integrated projects"),
        Line::from("    Employees Pluggable agent roster (vault/employees/)"),
        Line::from("    Events    Recent decisions, budget tier changes"),
        Line::from("    Metrics   Aggregate stats: tokens, lessons, projects"),
        Line::from(""),
        Line::from("  Add an employee:"),
        Line::from("    Drop a JSON file in vault/employees/"),
        Line::from(""),
    ];

    let block = Block::default()
        .borders(Borders::ALL)
        .style(Style::default().bg(Color::Black).fg(Color::White))
        .title("Help");

    let para = Paragraph::new(help_text).block(block);
    f.render_widget(ratatui::widgets::Clear, area);
    f.render_widget(para, area);
}

fn centered_rect(percent_x: u16, percent_y: u16, r: Rect) -> Rect {
    let popup_layout = Layout::default()
        .direction(Direction::Vertical)
        .constraints([
            Constraint::Percentage((100 - percent_y) / 2),
            Constraint::Percentage(percent_y),
            Constraint::Percentage((100 - percent_y) / 2),
        ])
        .split(r);

    Layout::default()
        .direction(Direction::Horizontal)
        .constraints([
            Constraint::Percentage((100 - percent_x) / 2),
            Constraint::Percentage(percent_x),
            Constraint::Percentage((100 - percent_x) / 2),
        ])
        .split(popup_layout[1])[1]
}
