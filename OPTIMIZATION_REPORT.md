# FlashASR Project Optimization Report

**Date:** 2026-02-09
**Project:** FlashASR (macOS)
**Analysis Scope:** Architecture, Code Quality, Performance, Security, and Scalability.

## 1. Executive Summary

FlashASR is a functional and feature-rich macOS menu bar application for ASR (Automatic Speech Recognition) and text processing. It successfully integrates audio capture, WebSocket/HTTP ASR services (Aliyun Dashscope), and LLM-based post-processing (Markdown generation).

However, the codebase currently exhibits symptoms of rapid prototyping:
- **"God Class" Architecture:** `AppController` is overly complex and handles too many responsibilities.
- **Concurrency Risks:** Heavy reliance on manual `DispatchQueue` management instead of modern Swift Concurrency.
- **Security Vulnerabilities:** API keys are hardcoded in the source code.
- **Scalability Issues:** Synchronous file I/O in session management and potential main-thread blocking.

This report outlines specific, prioritized recommendations to transition the project from a prototype to a production-ready application.

---

## 2. Critical Security Issues (High Priority)

### \u{26A0}\u{FE0F} 1. Hardcoded API Keys
**Location:** `Sources/SettingsManager.swift`
- **Issue:** Default API keys for Aliyun (Dashscope) and other providers are hardcoded in the `SettingsManager`.
- **Risk:** If this code is pushed to a public repository (even historically), these keys are compromised and can be abused, incurring costs.
- **Recommendation:**
  1.  **Revoke** existing keys immediately.
  2.  Remove default keys from the code. Use empty strings.
  3.  Implement a build-time configuration (e.g., `.xcconfig` or environment variables) for development keys, or require the user to input them on first launch.

### \u{26A0}\u{FE0F} 2. Insecure Key Storage
**Location:** `Sources/SettingsManager.swift`
- **Issue:** API keys are stored in `UserDefaults` via `@AppStorage`.
- **Risk:** `UserDefaults` is unencrypted and easily readable by any app or user with access to the file system.
- **Recommendation:** Store sensitive keys in the **macOS Keychain**. Create a `KeychainWrapper` property wrapper to replace `@AppStorage` for these specific fields.

---

## 3. Architectural Improvements

### 1. Decompose `AppController` (Refactoring)
**Current State:** `AppController` manages UI state, Audio recording, ASR WebSocket connection, File uploading, LLM interactions, and Hotkeys. It is approx. 800+ lines of mixed responsibility.
**Recommendation:** Split into dedicated services managed by a dependency injection container or a lightweight coordinator.

-   **`AudioService`**: Manages `AVAudioEngine`, VAD, and raw data streams.
-   **`ASRService`**: An actor responsible for the ASR state machine (Connecting, Streaming, Retrying).
-   **`LLMService`**: Handles interaction with MiMo/GLM APIs for Markdown generation.
-   **`SessionRepository`**: Manages persistence of `TranscriptionSession`.
-   **`AppCoordinator`**: The "glue" that listens to services and updates the `AppStatePublisher`.

### 2. Adopt Modern Swift Concurrency
**Current State:** Usage of `DispatchQueue`, `DispatchWorkItem`, and completion handlers (callback hell).
**Recommendation:** Migrate to **Async/Await** and **Actors**.
-   Convert `AppController` (or its split services) into `Actor`s to guarantee thread safety without manual queue management.
-   Replace `completion: @escaping` closures with `async throws` functions.
-   Use `Task` for firing background operations.

---

## 4. Performance & Stability

### 1. Audio Processing (VAD)
**Location:** `Sources/AudioCapture.swift`
-   **Issue:** `kSilenceThreshold = 220` is a fixed "magic number".
-   **Impact:** Poor performance in noisy environments (fails to detect silence) or quiet environments (cuts off speech).
-   **Recommendation:** Implement **Adaptive VAD**. Calculate the noise floor during the first few seconds or continuously, and trigger speech based on a dynamic threshold (e.g., `noiseFloor * 1.5`).

### 2. Synchronous File I/O
**Location:** `Sources/SessionManager.swift`
-   **Issue:** `save()` encodes and writes the entire session list to disk on the calling thread.
-   **Impact:** As the session history grows, this will cause UI stutters (hitches) if called from the main thread or `AppController` logic flow.
-   **Recommendation:** Perform file I/O on a background `Task` (detached) or a dedicated IO Actor.

### 3. Audio Engine Re-creation
**Location:** `Sources/AudioCapture.swift`
-   **Issue:** `start()` creates a new `AVAudioConverter` every time.
-   **Impact:** Unnecessary allocation overhead.
-   **Recommendation:** Initialize the audio engine and converter once; separate `start/stop` logic from `setup/teardown`.

---

## 5. Code Quality & Maintainability

### 1. Configuration Management
-   **Issue:** Magic numbers scattered throughout (e.g., `90.0` timeout, `300.0` max duration, `2.0` finalize timeout).
-   **Recommendation:** Centralize these in a `AppConfig` struct or extend `SettingsManager` to allow (advanced) user configuration or at least named constants.

### 2. Error Handling
-   **Issue:** Errors are passed as strings.
-   **Recommendation:** Define a proper `AppError: Error, LocalizedError` enum. This allows better error recovery logic (e.g., distinguishing "Network Timeout" from "Invalid API Key") and localized user messages.

---

## 6. Action Plan (Prioritized)

### Phase 1: Security & Stability (Immediate)
1.  **[Security]** Remove hardcoded API keys and implement Keychain storage.
2.  **[Stability]** Fix `SessionManager` synchronous I/O.
3.  **[Testing]** Add Unit Tests for `TranscriptBuffer` (logic) and `SessionManager` (persistence).

### Phase 2: Refactoring (High Value)
1.  **[Refactor]** Extract `LLMService` from `AppController`.
2.  **[Refactor]** Extract `ASRService` from `AppController`.
3.  **[Concurrency]** Convert `ASRService` to use `async/await`.

### Phase 3: Enhancement (Long Term)
1.  **[Audio]** Implement Adaptive VAD.
2.  **[UX]** Add visual feedback for "Network Reconnecting" vs "Processing".
3.  **[Feature]** Add "Export All Sessions" feature.

---

**Generated by Gemini CLI**
