use serde::{Deserialize, Serialize};

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

#[cfg(target_os = "linux")]
pub use crate::platform::linux::uinput::InputManager;

#[cfg(not(target_os = "linux"))]
pub struct InputManager;

#[cfg(not(target_os = "linux"))]
impl InputManager {
    pub fn new() -> Result<Self, String> {
        Err("Virtual input only supported on Linux".to_string())
    }
    pub fn handle_msg(&mut self, _msg: InputMsg) {}
}
