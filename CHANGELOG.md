# Changelog

All notable changes to this project are documented in this file.

## v6.6.0 - 2026-02-13

### Added
- Segmented file recording pipeline for recording mode (`180s` chunks + `10s` overlap) with rolling transcription during capture.
- Persistent checkpoint/recovery manifests for file recording so interrupted runs can auto-resume on launch.
- Segment-level failure tracking and retry entry points in Dashboard and recording indicator.

### Changed
- File recording now defaults to segmented pipeline path across configured duration limits, with optional rollback via hidden `segmentedFilePipelineEnabled` setting.
- Overlap stitching logic is now shared by lecture import and file segmented pipeline (`OverlapTextMerger`).

### Fixed
- Prevented long-recording end-stage data loss when stop-time conversion fails or times out by persisting and surfacing intermediate segment results.

## v6.5.0 - 2026-02-11

### Added
- Session lifecycle governance: archive/unarchive, batch delete/archive/export, group assignment and default target group for new sessions.
- Policy-based session cleanup with day threshold and optional inclusion of archived sessions.
- Markdown-mode preference switch to keep workflow in Dashboard without forcing floating window popup.
- Expanded advanced settings section for session and cleanup strategy controls.

### Fixed
- Prompt settings page now correctly switches and displays/edit prompts per mode/profile.
- Floating recording window text editor now receives focus and supports direct editing.
- Dashboard visibility state now synchronizes with indicator presentation policy.

### Improved
- Faithful-mode prompt constraints to reduce semantic drift and preserve original meaning.
- Deep-mode Markdown rendering strategy for richer, structured, and more readable outputs.

## v6.4.0

- Lecture long-audio pipeline upgraded to `180s` chunking with `10s` overlap stitching.
- Recording indicator switched to elapsed timer; per-mode duration caps configurable (up to 3 hours).
- Floating window and Dashboard feature parity improved across lecture workflows.
- Prompt robustness improved for mixed-language, numeric conflicts, and repeated self-corrections.
