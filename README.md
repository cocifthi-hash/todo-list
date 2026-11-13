# To-Do List

A minimal, offline-first Flutter task manager with Today, Upcoming, All Tasks and Completed views.

## Features in this starter release

- Local task storage with `shared_preferences` (no account/server required)
- Quick task entry: type and press Enter
- Optional date/time deadlines
- Upcoming tasks sorted by deadline
- Automatic visibility of unfinished tasks across days
- Overdue task styling and late-completion timestamps
- Completion history, edit, swipe-to-delete and undo
- Dark/light mode and five accent palettes
- Configurable local deadline reminders
- Backup data view for manual copying

## Build

1. Install Flutter stable and Android Studio / Android SDK.
2. From this directory run:

   ```bash
   flutter pub get
   flutter analyze
   flutter test
   flutter build apk --release
   ```

3. APK output: `build/app/outputs/flutter-apk/app-release.apk`.

## GitHub

Create a GitHub repository, upload the contents of this folder, then use the Flutter build commands above locally or in a GitHub Actions workflow.

## Important release notes

- This is a functional first implementation, not yet a fully QA-tested Play Store release.
- Android notification permission is requested at startup. Exact delivery can vary by Android version, battery optimisation and device manufacturer.
- Reminder scheduling currently supports selected intervals before a task deadline. Overdue follow-up notifications and recurring reminders are not implemented yet.
- The backup screen displays JSON for manual copying; automated file export/import is a follow-up improvement.
- AdMob is intentionally not enabled in this starter build. Add your own AdMob application/ad-unit IDs and consent/privacy handling before monetising.
- Task data is stored locally on the device. Uninstalling the app or clearing app data may remove it; export your backup first.

## Suggested next QA pass

Test task creation, deadline editing, late completion, midnight carry-forward, notification permission, device reboot, backup/restore, and screen sizes on at least one physical Android device.

## Build APK with GitHub Actions

1. Create a repository named `todo-list` on GitHub.
2. Upload all files and folders from this project to the repository root.
3. Open the repository's **Actions** tab.
4. Run **Build Android APK** (or push to the `main` branch).
5. When the workflow finishes, download the `todo-list-release-apk` artifact.

The workflow generates the standard Android platform scaffolding, runs `flutter analyze`, and builds a release APK. If analysis reports issues, fix them before distributing the APK.
