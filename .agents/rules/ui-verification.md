# UI Verification Rule

- ALWAYS use `grim` (with proper `WAYLAND_DISPLAY` environment) to take a desktop screenshot when making UI-related code changes.
- Inspect the captured image using `view_file` to empirically verify whether the UI change had the intended visual effect or not before concluding a task.
