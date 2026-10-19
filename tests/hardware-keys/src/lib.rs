// Tests use copies of the production modules, without the renderer dependencies.
#![allow(dead_code)]
extern crate self as eframe;
pub use egui;
mod key_codes;
mod keyboard;
