# Lad

The owner's personal keyboard layout switcher for macOS (a Punto Switcher replacement). Menu bar
app, Swift 6, built with the Command Line Tools only — never propose installing Xcode.

## Commands

- `make check` — build + all tests with warnings as errors and complete concurrency checking. Run before calling work done.
- `make test`, `make coverage` (LadCore line coverage), `make eval` (detector quality; add `EVAL_FLAGS='--code <dir>'`;
  `lad-eval live` sweeps the live switching thresholds).
- `make install` — release build, sign, install to ~/Applications/Lad.app, launch. Signing uses Lad's
  own "Lad Local Code Signing" identity in a password-locked keychain (`make setup-signing`), so the
  Accessibility grant survives rebuilds; the owner types that password, never ask for it.
- `make release` (universal build, signed like an install: the owner types the password; zip, DMG and
  sums in dist/) and `make publish` (tools/publish.sh: tag, push, GitHub release, cask in
  OlehFostyak/homebrew-tap). Lad never gets networking for updates: Homebrew and this script do it.
- `make verify` (otool/nm checks of the built binary; the allow-list covers non-Swift symbols and
  Foundation's Swift API), `make symbols` (refresh `tools/allowed-symbols.txt`
  after using a new API; review the diff).
- `make fixtures` re-captures the owner's layouts (Ukrainian-PC is a custom layout,
  `org.unknown.keylayout.Українська-PC`); `make dictionaries` rebuilds Resources/Dictionaries
  (keep `Resources/Licenses.txt`, shipped in the bundle, in step with its sources).

## Layout

- `Sources/LadCore` — pure logic, no AppKit: `LayoutTable` (UCKeyTranslate tables), `WordTable`
  (sorted word counts in one block, prefix totals), `LanguageModel` (word table + character
  trigrams; `packed()` is the `.lad` file `make bundle` ships and the app maps), `Detector`
  (verdicts, early switching), `LadEngine` (word tracking, chains, undo, double Shift, Return,
  short replies, apostrophes, learning, case fixes, live switching), `CaseFix`,
  `Transliterator`/`CaseCycle`, `Hotkey`, `LayoutMemory`, `UsageCounter`, `TypingRhythm`/`SourceFilter`,
  `AppKind` (terminal and remote apps by bundle ID). Tests in
  `Tests/LadCoreTests` use the real layout fixture and dictionaries.
- `Sources/Lad` — AppKit glue, main-actor by default: `EventTap`, `KeyboardOutput`, `InputSources`,
  `FocusObserver`, `SelectionTransformer`, `TypingController`, `LayoutHint`, `StatusItemController`,
  `PanelModel`/`PanelView`, `Settings`.
- `Sources/LadEval` — developer tool (`quality`, `sweep`, `live`, `explain`, `pack`, `dump-layouts`); `make bundle`
  runs its `pack`, the app never includes it.

## Rules

- Privacy is the point of this app: no networking APIs, no `print`, logging only through the fixed
  `LogEvent`s in Log.swift. Persisted (Settings.swift only): switches, the two word lists the user
  builds with double Shift (exceptions, learned words — the only typed text on disk, shown in the
  panel; learned words are listed or word-like and never from a terminal, a turned-back live switch
  only if word-like), bundle ID → layout ID per app, and per-day fix counts. Nothing under secure
  input reaches the engine. Keys other programs type are dropped with the rest of their word:
  caught by sender PID, or by rhythm from the fifth fast press (the engine then forgets the first
  four). In terminals and apps with one built in
  (`AppKind`; password prompts) Return never converts, words never switch while typed and nothing
  is learned; remote desktops and VMs get nothing at all.
  `Tests/LintTests` and `make verify` (otool/nm on the binary, symbol allow-list) enforce this —
  keep them passing, extend them when adding APIs.
- Hotkeys are ⌃⌥ + L/T/U (`Hotkey` in LadCore); Babak owns ⌃⌥A/J/D/P. Avoid Space chords.
- Change detector thresholds only with `lad-eval sweep`/`quality`/`live` numbers before and after; a
  false conversion of a correctly typed word is worse than a missed one. The lists are mapped from
  the bundle, so more words cost disk, not memory.
- Code and comments in English; README and UI strings in Ukrainian.
