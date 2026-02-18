use crossterm::{
    event::{self, DisableMouseCapture, EnableMouseCapture, Event, KeyCode},
    execute,
    terminal::{disable_raw_mode, enable_raw_mode, EnterAlternateScreen, LeaveAlternateScreen},
};
use ratatui::{
    backend::{Backend, CrosstermBackend},
    layout::{Constraint, Direction, Layout, Rect},
    style::{Color, Modifier, Style},
    text::{Line, Span},
    widgets::{Block, Borders, Clear, List, ListItem, ListState, Paragraph},
    Frame, Terminal,
};
use std::{error::Error, io};
use crate::config::HostConfig;
use crate::auth::AuthManager;

enum InputMode {
    Normal,
    Editing,
    VerifyingPassword,
    SettingNewPassword,
}

struct App {
    config: HostConfig,
    items: Vec<String>,
    state: ListState,
    input: String,
    input_mode: InputMode,
    cursor_position: usize,
    error_msg: Option<String>,
}

impl App {
    fn new(config: HostConfig) -> App {
        let mut state = ListState::default();
        state.select(Some(0));
        App {
            config,
            items: vec![
                "Host Name".to_string(),
                "Public Listing".to_string(),
                "Signaling URL".to_string(),
                "Change Passcode".to_string(),
                "SAVE & EXIT".to_string(),
            ],
            state,
            input: String::new(),
            input_mode: InputMode::Normal,
            cursor_position: 0,
            error_msg: None,
        }
    }

    fn next(&mut self) {
        let i = match self.state.selected() {
            Some(i) => {
                if i >= self.items.len() - 1 {
                    0
                } else {
                    i + 1
                }
            }
            None => 0,
        };
        self.state.select(Some(i));
    }

    fn previous(&mut self) {
        let i = match self.state.selected() {
            Some(i) => {
                if i == 0 {
                    self.items.len() - 1
                } else {
                    i - 1
                }
            }
            None => 0,
        };
        self.state.select(Some(i));
    }

    fn move_cursor_left(&mut self) {
        let cursor_moved_left = self.cursor_position.saturating_sub(1);
        self.cursor_position = self.clamp_cursor(cursor_moved_left);
    }

    fn move_cursor_right(&mut self) {
        let cursor_moved_right = self.cursor_position.saturating_add(1);
        self.cursor_position = self.clamp_cursor(cursor_moved_right);
    }

    fn enter_char(&mut self, new_char: char) {
        self.input.insert(self.cursor_position, new_char);
        self.move_cursor_right();
    }

    fn delete_char(&mut self) {
        if self.cursor_position != 0 {
            let offset = self.cursor_position - 1;
            self.input.remove(offset);
            self.move_cursor_left();
        }
    }

    fn clamp_cursor(&self, new_cursor_pos: usize) -> usize {
        new_cursor_pos.clamp(0, self.input.len())
    }

    fn submit_input(&mut self) {
        match self.input_mode {
            InputMode::Editing => {
                if let Some(i) = self.state.selected() {
                    match i {
                        0 => self.config.host_name = self.input.clone(),
                        2 => self.config.signaling_url = self.input.clone(),
                        _ => {}
                    }
                }
                self.input_mode = InputMode::Normal;
            }
            InputMode::VerifyingPassword => {
                if AuthManager::verify_password(&self.input, &self.config.password_hash) {
                    self.input_mode = InputMode::SettingNewPassword;
                    self.error_msg = None;
                } else {
                    self.error_msg = Some("Invalid passcode!".to_string());
                    self.input_mode = InputMode::Normal;
                }
            }
            InputMode::SettingNewPassword => {
                let auth = AuthManager::new(&self.input);
                self.config.password_hash = auth.password_hash;
                self.input_mode = InputMode::Normal;
                self.error_msg = Some("Passcode updated successfully.".to_string());
            }
            _ => {}
        }
        self.input.clear();
        self.cursor_position = 0;
    }
}

pub async fn run_tui(config: HostConfig) -> Result<(), Box<dyn Error>> {
    enable_raw_mode()?;
    let mut stdout = io::stdout();
    execute!(stdout, EnterAlternateScreen, EnableMouseCapture)?;
    let backend = CrosstermBackend::new(stdout);
    let mut terminal = Terminal::new(backend)?;

    let app = App::new(config);
    let res = run_app(&mut terminal, app).await;

    disable_raw_mode()?;
    execute!(
        terminal.backend_mut(),
        LeaveAlternateScreen,
        DisableMouseCapture
    )?;
    terminal.show_cursor()?;

    if let Ok(config) = res {
        config.save().await;
        println!("Configuration saved.");
    }

    Ok(())
}

async fn run_app<B: Backend>(terminal: &mut Terminal<B>, mut app: App) -> io::Result<HostConfig> {
    loop {
        terminal.draw(|f| ui(f, &mut app)).map_err(|e| io::Error::new(io::ErrorKind::Other, e.to_string()))?;

        if event::poll(std::time::Duration::from_millis(100))? {
            if let Event::Key(key) = event::read()? {
                match app.input_mode {
                    InputMode::Normal => match key.code {
                        KeyCode::Char('q') | KeyCode::Esc => return Ok(app.config),
                        KeyCode::Char('j') | KeyCode::Down => {
                            app.error_msg = None;
                            app.next();
                        },
                        KeyCode::Char('k') | KeyCode::Up => {
                            app.error_msg = None;
                            app.previous();
                        },
                        KeyCode::Enter => {
                            app.error_msg = None;
                            if let Some(i) = app.state.selected() {
                                match i {
                                    0 => {
                                        app.input_mode = InputMode::Editing;
                                        app.input = app.config.host_name.clone();
                                        app.cursor_position = app.input.len();
                                    }
                                    1 => {
                                        app.config.is_public = !app.config.is_public;
                                    }
                                    2 => {
                                        app.input_mode = InputMode::Editing;
                                        app.input = app.config.signaling_url.clone();
                                        app.cursor_position = app.input.len();
                                    }
                                    3 => {
                                        app.input_mode = InputMode::VerifyingPassword;
                                        app.input.clear();
                                        app.cursor_position = 0;
                                    }
                                    4 => return Ok(app.config),
                                    _ => {}
                                }
                            }
                        }
                        _ => {}
                    },
                    InputMode::Editing | InputMode::VerifyingPassword | InputMode::SettingNewPassword => match key.code {
                        KeyCode::Enter => app.submit_input(),
                        KeyCode::Char(c) => app.enter_char(c),
                        KeyCode::Backspace => app.delete_char(),
                        KeyCode::Left => app.move_cursor_left(),
                        KeyCode::Right => app.move_cursor_right(),
                        KeyCode::Esc => {
                            app.input_mode = InputMode::Normal;
                            app.input.clear();
                            app.cursor_position = 0;
                        }
                        _ => {}
                    },
                }
            }
        }
    }
}

fn ui(f: &mut Frame, app: &mut App) {
    let chunks = Layout::default()
        .direction(Direction::Vertical)
        .margin(2)
        .constraints(
            [
                Constraint::Length(3),
                Constraint::Min(10),
                Constraint::Length(3),
            ]
            .as_ref(),
        )
        .split(f.area());

    let title = Paragraph::new(Line::from(vec![
        Span::styled(" ⚡ FRANKN ", Style::default().fg(Color::Cyan).add_modifier(Modifier::BOLD)),
        Span::styled("CONFIG_CORE ", Style::default().fg(Color::Magenta)),
    ]))
    .block(Block::default().borders(Borders::ALL).border_style(Style::default().fg(Color::Cyan)));
    f.render_widget(title, chunks[0]);

    let items: Vec<ListItem> = app
        .items
        .iter()
        .enumerate()
        .map(|(i, s)| {
            let val = match i {
                0 => format!(": {}", app.config.host_name),
                1 => format!(": {}", if app.config.is_public { "PUBLIC" } else { "PRIVATE" }),
                2 => format!(": {}", app.config.signaling_url),
                3 => ": ********".to_string(),
                _ => String::new(),
            };
            
            let content = Line::from(vec![
                Span::styled(s, Style::default().add_modifier(Modifier::BOLD)),
                Span::styled(val, Style::default().fg(Color::DarkGray)),
            ]);
            ListItem::new(content)
        })
        .collect();

    let list = List::new(items)
        .block(Block::default().borders(Borders::ALL).title(" Settings "))
        .highlight_style(
            Style::default()
                .bg(Color::Cyan)
                .fg(Color::Black)
                .add_modifier(Modifier::BOLD),
        )
        .highlight_symbol(">> ");
    f.render_stateful_widget(list, chunks[1], &mut app.state);

    let footer_content = if let Some(err) = &app.error_msg {
        Line::from(vec![Span::styled(err, Style::default().fg(Color::Yellow))])
    } else {
        match app.input_mode {
            InputMode::Normal => Line::from(" [j/k] Navigate  [Enter] Edit/Toggle  [Esc/q] Quit "),
            InputMode::Editing => Line::from(" [Enter] Submit  [Esc] Cancel "),
            InputMode::VerifyingPassword => Line::from(" [Enter] Verify Current Passcode  [Esc] Cancel "),
            InputMode::SettingNewPassword => Line::from(" [Enter] Set NEW Passcode  [Esc] Cancel "),
        }
    };

    let help = Paragraph::new(footer_content)
        .block(Block::default().borders(Borders::ALL).border_style(Style::default().fg(Color::DarkGray)));
    f.render_widget(help, chunks[2]);

    match app.input_mode {
        InputMode::Editing | InputMode::VerifyingPassword | InputMode::SettingNewPassword => {
            let area = centered_rect(60, 20, f.area());
            f.render_widget(Clear, area);
            
            let title = match app.input_mode {
                InputMode::Editing => " Edit Value ",
                InputMode::VerifyingPassword => " Enter Current Passcode ",
                InputMode::SettingNewPassword => " Enter New Passcode ",
                _ => "",
            };

            let masked_input = "*".repeat(app.input.len());
            let input_display = if let InputMode::Editing = app.input_mode {
                app.input.as_str()
            } else {
                masked_input.as_str()
            };

            let input_block = Block::default()
                .title(title)
                .borders(Borders::ALL)
                .border_style(Style::default().fg(Color::Yellow));
            let input_para = Paragraph::new(input_display).block(input_block);
            f.render_widget(input_para, area);
            
            f.set_cursor_position((
                area.x + app.cursor_position as u16 + 1,
                area.y + 1,
            ));
        }
        _ => {}
    }
}

fn centered_rect(percent_x: u16, percent_y: u16, r: Rect) -> Rect {
    let popup_layout = Layout::default()
        .direction(Direction::Vertical)
        .constraints(
            [
                Constraint::Percentage((100 - percent_y) / 2),
                Constraint::Percentage(percent_y),
                Constraint::Percentage((100 - percent_y) / 2),
            ]
            .as_ref(),
        )
        .split(r);

    Layout::default()
        .direction(Direction::Horizontal)
        .constraints(
            [
                Constraint::Percentage((100 - percent_x) / 2),
                Constraint::Percentage(percent_x),
                Constraint::Percentage((100 - percent_x) / 2),
            ]
            .as_ref(),
        )
        .split(popup_layout[1])[1]
}