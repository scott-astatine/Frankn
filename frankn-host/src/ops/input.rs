use serde::{Deserialize, Serialize};
use uinput::event::controller::Controller::Mouse;
use uinput::event::controller::Mouse as MouseBtn;
use uinput::event::relative::Position;
use uinput::event::relative::Relative;
use uinput::event::relative::Wheel;
use uinput::event::Event;

#[derive(Serialize, Deserialize, Debug)]
#[serde(tag = "type")]
pub enum InputMsg {
    #[serde(rename = "mouse_move")]
    MouseMove { dx: f64, dy: f64 },
    #[serde(rename = "mouse_click")]
    MouseClick { button: u16, down: bool },
    #[serde(rename = "scroll")]
    Scroll { dx: f64, dy: f64 },
    #[serde(rename = "key_press")]
    KeyPress { key_code: u16, down: bool },
    #[serde(rename = "type_text")]
    TypeText { text: String },
}

pub struct InputManager {
    mouse: uinput::Device,
    keyboard: uinput::Device,
}

impl InputManager {
    pub fn new() -> Result<Self, uinput::Error> {
        let mouse = uinput::default()?
            .name("frankn_virtual_mouse")?
            .event(Event::Relative(Relative::Position(Position::X)))?
            .event(Event::Relative(Relative::Position(Position::Y)))?
            .event(Event::Relative(Relative::Wheel(Wheel::Vertical)))?
            .event(Event::Relative(Relative::Wheel(Wheel::Horizontal)))?
            .event(Event::Controller(Mouse(MouseBtn::Left)))?
            .event(Event::Controller(Mouse(MouseBtn::Right)))?
            .event(Event::Controller(Mouse(MouseBtn::Middle)))?
            .create()?;

        let keyboard = uinput::default()?
            .name("frankn_virtual_keyboard")?
            .event(Event::Keyboard(uinput::event::Keyboard::All))?
            .create()?;

        Ok(Self { mouse, keyboard })
    }

    pub fn handle_msg(&mut self, msg: InputMsg) {
        match msg {
            InputMsg::MouseMove { dx, dy } => {
                let _ = self.mouse.send(Position::X, dx as i32);
                let _ = self.mouse.send(Position::Y, dy as i32);
                let _ = self.mouse.synchronize();
            }
            InputMsg::MouseClick { button, down } => {
                let key = match button {
                    1 => MouseBtn::Left,
                    2 => MouseBtn::Right,
                    3 => MouseBtn::Middle,
                    _ => return,
                };
                let _ = self.mouse.send(key, if down { 1 } else { 0 });
                let _ = self.mouse.synchronize();
            }
            InputMsg::Scroll { dx, dy } => {
                // Scale down scroll speed. Flutter deltas are large, Linux expects small clicks.
                let sy = (dy / 10.0) as i32;
                let sx = (dx / 10.0) as i32;
                if sy != 0 {
                    let _ = self.mouse.send(Wheel::Vertical, -sy); // Invert for natural scroll
                }
                if sx != 0 {
                    let _ = self.mouse.send(Wheel::Horizontal, sx);
                }
                let _ = self.mouse.synchronize();
            }
            InputMsg::KeyPress { key_code, down } => {
                let _ = self.keyboard.write(1, key_code as i32, if down { 1 } else { 0 });
                let _ = self.keyboard.synchronize();
            }
            InputMsg::TypeText { text } => {
                for c in text.chars() {
                    self.type_char(c);
                }
            }
        }
    }

    fn type_char(&mut self, c: char) {
        // Basic mapping for a standard US QWERTY layout.
        // Format: (keycode, needs_shift)
        let mapping: Option<(i32, bool)> = match c {
            'a' | 'A' => Some((30, c.is_uppercase())),
            'b' | 'B' => Some((48, c.is_uppercase())),
            'c' | 'C' => Some((46, c.is_uppercase())),
            'd' | 'D' => Some((32, c.is_uppercase())),
            'e' | 'E' => Some((18, c.is_uppercase())),
            'f' | 'F' => Some((33, c.is_uppercase())),
            'g' | 'G' => Some((34, c.is_uppercase())),
            'h' | 'H' => Some((35, c.is_uppercase())),
            'i' | 'I' => Some((23, c.is_uppercase())),
            'j' | 'J' => Some((36, c.is_uppercase())),
            'k' | 'K' => Some((37, c.is_uppercase())),
            'l' | 'L' => Some((38, c.is_uppercase())),
            'm' | 'M' => Some((50, c.is_uppercase())),
            'n' | 'N' => Some((49, c.is_uppercase())),
            'o' | 'O' => Some((24, c.is_uppercase())),
            'p' | 'P' => Some((25, c.is_uppercase())),
            'q' | 'Q' => Some((16, c.is_uppercase())),
            'r' | 'R' => Some((19, c.is_uppercase())),
            's' | 'S' => Some((31, c.is_uppercase())),
            't' | 'T' => Some((20, c.is_uppercase())),
            'u' | 'U' => Some((22, c.is_uppercase())),
            'v' | 'V' => Some((47, c.is_uppercase())),
            'w' | 'W' => Some((17, c.is_uppercase())),
            'x' | 'X' => Some((45, c.is_uppercase())),
            'y' | 'Y' => Some((21, c.is_uppercase())),
            'z' | 'Z' => Some((44, c.is_uppercase())),
            '1' | '!' => Some((2, c == '!')),
            '2' | '@' => Some((3, c == '@')),
            '3' | '#' => Some((4, c == '#')),
            '4' | '$' => Some((5, c == '$')),
            '5' | '%' => Some((6, c == '%')),
            '6' | '^' => Some((7, c == '^')),
            '7' | '&' => Some((8, c == '&')),
            '8' | '*' => Some((9, c == '*')),
            '9' | '(' => Some((10, c == '(')),
            '0' | ')' => Some((11, c == ')')),
            '-' | '_' => Some((12, c == '_')),
            '=' | '+' => Some((13, c == '+')),
            '[' | '{' => Some((26, c == '{')),
            ']' | '}' => Some((27, c == '}')),
            ';' | ':' => Some((39, c == ':')),
            '\'' | '"' => Some((40, c == '"')),
            '`' | '~' => Some((41, c == '~')),
            '\\' | '|' => Some((43, c == '|')),
            ',' | '<' => Some((51, c == '<')),
            '.' | '>' => Some((52, c == '>')),
            '/' | '?' => Some((53, c == '?')),
            ' ' => Some((57, false)),
            '\n' => Some((28, false)),
            '\t' => Some((15, false)),
            _ => None,
        };

        if let Some((code, shift)) = mapping {
            if shift { self.keyboard.write(1, 42, 1).unwrap(); } // L_SHIFT Down
            let _ = self.keyboard.write(1, code, 1);
            let _ = self.keyboard.write(1, code, 0);
            if shift { self.keyboard.write(1, 42, 0).unwrap(); } // L_SHIFT Up
            let _ = self.keyboard.synchronize();
        }
    }
}
