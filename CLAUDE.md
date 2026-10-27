# Lad

The owner's personal keyboard layout switcher for macOS (a Punto Switcher replacement). Menu bar
app, Swift 6, built with the Command Line Tools only — never propose installing Xcode.

## Commands

- `make check` — build + all tests with warnings as errors and complete concurrency checking. Run before calling work done.
- `make test`, `make coverage` (LadCore line coverage), `make eval` (detector quality; add `EVAL_FLAGS='--code <dir>'`).
- `make install` — release build, sign, install to ~/Applications/Lad.app, launch. Signing uses the
  "Babak Local Code Signing" identity so the Accessibility grant survives rebuilds.
- `make fixtures` re-captures the owner's layouts (Ukrainian-PC is a custom layout,
  `org.unknown.keylayout.Українська-PC`); `make dictionaries` rebuilds Resources/Dictionaries.

## Layout

- `Sources/LadCore` — pure logic, no AppKit: `LayoutTable` (UCKeyTranslate tables), `LanguageModel`
  (word counts + character trigrams), `Detector` (verdicts), `LadEngine` (word tracking, chains,
  undo, double Shift). Tests in `Tests/LadCoreTests` use the real layout fixture and dictionaries.
- `Sources/Lad` — AppKit glue, main-actor by default: `EventTap`, `KeyboardOutput`, `InputSources`,
  `SelectionConverter`, `TypingController`, `StatusMenu`, `Settings`.
- `Sources/LadEval` — developer tool (`quality`, `sweep`, `explain`, `dump-layouts`); never shipped.

## Rules

- Privacy is the point of this app: no networking APIs, no `print`, logging only through the fixed
  `LogEvent`s in Log.swift. Persisted (Settings.swift only): switches, the two word lists the user
  builds with double Shift (exceptions, learned words — the only typed text on disk, shown in the
  panel), bundle ID → layout ID per app, and per-day fix counts. Keys typed by other programs and
  everything under secure input never reach the engine. `Tests/LintTests` and `make verify`
  (otool/nm on the binary) enforce this — keep them passing, extend them when adding APIs.
- Hotkeys are ⌃⌥ + L/T/U (`Hotkey` in LadCore); Babak owns ⌃⌥A/J/D/P. Avoid Space chords.
- Change detector thresholds only with `lad-eval sweep`/`quality` numbers before and after; a false
  conversion of a correctly typed word is worse than a missed one.
- Code and comments in English; README and UI strings in Ukrainian.
