# Repository Guidelines

## Project Structure & Module Organization

This repository has three components. `frankn/` is the Flutter client: code is in `lib/`, tests in `test/`, and platform integrations and resources in `android/`, `ios/`, `linux/`, `macos/`, `windows/`, `web/`, and `assets/`. `frankn-host/` is the Rust host runtime, organized under `src/` by app, capability, platform, signaling, and transport. `frankn-signaling-server/` is the Rust signaling service. Top-level `docs/` contains architecture references. Keep changes within the affected component and update shared protocol behavior consistently.

## Build, Test, and Development Commands

Run commands from the relevant component directory:

- `cd frankn && flutter pub get` resolves client dependencies.
- `cd frankn && flutter run` launches the client on an available device.
- `cd frankn && flutter analyze` runs Dart static analysis.
- `cd frankn && flutter test` runs Flutter tests in `test/`.
- `cd frankn-host && cargo check` checks the host crate; `cargo test` runs its unit and integration tests.
- `cd frankn-signaling-server && cargo check` checks the signaling service; `cargo test` runs its tests.

The host manifest currently references a local `dohee-engine` crate, so host builds require that dependency at the configured path.

## Coding Style & Naming Conventions

Use `dart format` for Dart files and `cargo fmt` for Rust. Follow the existing Flutter lint rules in `frankn/analysis_options.yaml`. Use `snake_case.dart` for Dart files and Rust modules, `UpperCamelCase` for Dart types, and `snake_case` for Rust functions and variables. Keep capability-specific behavior in the corresponding capability module and add or update tests alongside the behavior.

## Testing Guidelines

Flutter tests use `flutter_test`; name test files `*_test.dart` under `frankn/test/`. Rust tests use Cargo's built-in test harness and may live inline or in module test files. Run the component's test command after changing behavior, and use the relevant analyzer/check command for compile and lint feedback.

## Commit & Pull Request Guidelines

Recent history uses Conventional Commit prefixes such as `feat`, `fix`, and `refactor`, often scoped (for example, `feat(camera): ...`). Use a specific summary. Pull requests should describe component and impact, link related issues, include screenshots for UI changes, and note commands run and any platform limitations.

## Security & Configuration

Do not commit credentials, private keys, or machine-specific settings. Review authentication, transport, and capability authorization changes across the host, client, and signaling service.
