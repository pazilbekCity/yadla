# AGENTS.md

Stable, project-wide instructions for AI agents working in this repository.

## 1. Purpose
Offline-first flashcard application (Anki-inspired) for Android and iOS, built with Flutter/Dart.
No backend, no user accounts, no cloud database; all data is stored locally in SQLite.
Content hierarchy: Subject > Book > Topic > Deck > Flashcard (plus ReviewHistory and AppSettings).

## 2. Architecture
- Data layer lives in `lib/data/`: `database/` (open, migrations, errors, ids), `models/`, `repositories/`.
- Reuse the existing `AppDatabase`, `migrations.dart`, models, and repositories. Do not create parallel database code.
- UI must not access sqflite or SQL directly; it uses repositories only. Keep UI code separate from `lib/data/`.
- Data-layer failures are reported through `AppDatabaseException` (see `DbErrorKind`). Never swallow database errors.

## 3. Data integrity
- Never delete or reset user data as a side effect of a change.
- Schema changes are append-only: add a new `Migration` with the next version number. Never edit a released migration.
- Keep `PRAGMA foreign_keys = ON`. Hierarchy foreign keys use `ON DELETE RESTRICT`; deleting a subtree must be an explicit, transactional `cascade: true`.
- Use transactions for multi-step writes. Avoid destructive schema changes (dropping columns/tables); migrate data instead.
- Primary keys are TEXT UUIDs (`generateId()`); timestamps are UTC epoch milliseconds.

## 4. Dependencies
Do not add packages unless technically necessary. Explain why before adding one. Current runtime dependencies: `sqflite`, `path`, `path_provider`; dev: `sqflite_common_ffi`, `flutter_lints`.

## 5. Code quality
- Follow the existing conventions and `analysis_options.yaml` (flutter_lints).
- Do not duplicate existing implementations; extend them.
- Keep changes minimal and focused. Preserve unrelated comments and docstrings.

## 6. Localization
- All user-facing UI text must support Karakalpak (`kaa`), Uzbek (`uz`), and Russian (`ru`). Do not hard-code text in a single language once localization infrastructure exists.
- During development, write newly added UI text in Karakalpak unless a task says otherwise.
- The interface language is stored in AppSettings under `interface_language`.

## 7. Verification
- After code changes, run `flutter analyze` and the relevant tests (`flutter test`).
- Report actual results only. Never claim a check or build passed unless it was actually run; state clearly what was not run.
- Add or update tests for changed data-layer behavior.

## 8. Environment
- Flutter SDK is at `C:\src\flutter` and is not on PATH; call `C:\src\flutter\bin\flutter.bat` by full path. Do not change PATH or other environment variables without approval.
- Android SDK: `C:\Users\User\AppData\Local\Android\Sdk`; JDK: Android Studio's bundled `jbr`.
- Known issue: this Windows 10 LTSB 2015 machine cannot load Gradle's native DLL (`gradle-fileevents.dll`), so `flutter build apk` currently fails. Do not repeatedly attempt speculative Gradle fixes; report it and ask the user.
- iOS builds are not possible on Windows.

## 9. Workflow
- Inspect the relevant files before editing.
- Implement only the requested task or block; do not build future features prematurely.
- Preserve working functionality and unrelated files.
- Ask before any destructive or architecture-changing action.
- Stop after the assigned block and wait for user review.

## 10. Communication
- Talk to the user in Karakalpak: questions, progress, warnings, errors, and reports.
- Keep code identifiers, filenames, and technical commands in English. For hard-to-translate technical terms, keep the English term and briefly explain it in Karakalpak.
