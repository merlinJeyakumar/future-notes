# AntiGravity Notes - Project Summary

## 1. Project Overview & Motivation
**Project Name:** AntiGravity Notes (Flutter Application 1)
**Technology:** Flutter (Dart)
**Platforms:** Windows (Desktop), Android (Mobile), Web (Architecture ready)

**Motivation:**
The primary goal was to architect a **secure, local-first, high-performance note-taking application** that bridges the gap between casual mobile usage and power-user desktop workflows. The "AntiGravity" design philosophy emphasizes a fluid, distraction-free interface where controls float into view only when needed, maintaining focus on content.

**Core Values:**
- **Privacy First:** All data is stored locally. Sensitive notes are encrypted.
- **Fluid UX:** Seamless transition between device form factors (Mobile vs. Desktop).
- **Power & Simplicity:** Rich text for general users, raw HTML/Code access for technical users.

---

## 2. Key Features & Usages

### A. Dual-Mode Editor
The application features a sophisticated hybrid editing engine:
- **Rich Text Mode:** WYSIWYG editing (Bold, Italic, Lists, Headers) powered by `flutter_quill`.
- **HTML/Developer Mode:** Direct source code editing with syntax highlighting (`code_text_field`) and an Atom One Dark theme.
- **Synchronization:** Real-time, lossless syncing between the rich text Delta format and raw HTML.

### B. Security & Encryption
- **File Locking:** Ability to lock individual files with a custom password.
- **Encryption:** Content is AES-encrypted (via `EncryptionService`) before storage.
- **Secure UX:** Masked previews in the sidebar for locked files. Password dialogs support Unlocking, Setting, and Updating credentials.

### C. File Management System
- **Local Storage:** Files are stored in a dedicated `UserData` directory for easy backup and access.
- **Background Discovery:** A dedicated `BackgroundService` uses **Dart Isolates** to scan, decrypt headers, and sort thousands of files without blocking the main UI thread.
- **Import/Export:** Support for importing external text/HTML files into the workspace.
- **Auto-Save:** Smart auto-saving logic that prevents data loss but avoids cluttering storage with empty files.

### E. Attachments & Media Support
- **Rich Media Embedding:** The editor architecture supports embedding images and rich media directly within notes (via `flutter_quill` standards).
- **External Imports:** Users can seamlessly import existing `.txt`, `.html`, and `.json` files, which are automatically converted and sanitized for the AntiGravity workspace.
- **Future-Proofing:** The background service is designed to handle binary assets (images/videos) alongside text content for future expansion.

### F. Responsive "AntiGravity" UI
- **Adaptive Layout:** 
  - **Desktop:** Persistent Sidebar with hover effects and keyboard shortcuts (`Ctrl+S`, `Ctrl+N`).
  - **Mobile:** Collapsible Drawer with touch-optimized touch targets.
- **Floating Toolbar:** Editing tools appear contextually, maximizing screen real estate.
- **Master Settings:** Centralized configuration for Theme and App info (Architecture in place).

---

## 3. Technical "Mountains" (Challenges & Milestones)

These define the robust engineering behind the simple UI:

1.  **Hybrid State Management (MVVM):**
    - usage of `ContentViewModel` to decouple UI from business logic.
    - Handling complex state transitions between `isLocked`, `isHtmlMode`, and `isEditing`.

2.  **Isolate-Based Performance:**
    - Offloading file system crawling and heavy JSON parsing to a background thread (`Isolate`).
    - Ensures the UI remains at 60fps even when loading large workspaces.

3.  **Cross-Platform Input Handling:**
    - Custom `CallbackShortcuts` implementation to handle desktop shortcuts (`Ctrl+S`) naturally while preserving mobile gestures.
    - Solving focus trapping issues between the Editor and UI elements.

4.  **Robust Error Handling:**
    - Graceful degradation for corrupted files or legacy formats.
    - Async password verification flows with UI feedback loops (Loading states, error toasts).

---

## 4. How to Explain to Other AI

**Context Prompt:**
> "This is a Flutter-based note-taking app using `flutter_quill` for the editor and `path_provider` for local file storage. It implements a custom MVVM architecture where `ContentViewModel` manages the editor state and file I/O. Key unique features include a custom encryption layer for locked notes and a background isolate service for file discovery. Usage involves switching between a Visual Editor and an HTML Source View."

**Key Files to Reference:**
- `lib/features/dashboard/viewmodels/content_viewmodel.dart`: The brain of the application.
- `lib/features/dashboard/widgets/content_area.dart`: The main editor UI and toolbar logic.
- `lib/features/dashboard/services/file_service.dart` & `background_service.dart`: The I/O backbone.
- `lib/features/dashboard/widgets/password_dialog.dart`: Security UI interaction.
