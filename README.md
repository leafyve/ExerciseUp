# ExerciseUp

An Android app that nudges you to do quick bodyweight exercises on schedules you control, and tracks what you actually did.

Built with Flutter. All data stays on the device; there are no accounts, ads, or network calls.

## Features

- **Exercises:** push-ups, squats, sit-ups, planks (timed), lunges, jumping jacks, burpees, plus your own custom exercises.
- **Flexible reminders:** create as many as you like, each with its own exercises and amounts.
  - repeat every N minutes or hours inside an active-hours window (windows can cross midnight)
  - or fire at fixed times of day
  - on the weekdays you choose
  - with sound and vibration options and rotating motivational messages
- **Act from the notification:** Done (logs the amounts), Snooze 10 min, or Skip, without opening the app.
- **Log any day:** step back with the arrow (or pick a date) to add sets for previous days.
- **Progress:** daily goals, streaks, and 7/30-day charts per exercise.
- **Home-screen widget:** today's summary, streak, and a one-tap button to log your most recent exercise.
- Reminders survive reboots and are topped up in the background.

## Build

Requirements: Flutter 3.47+ and the Android SDK.

```bash
flutter pub get
dart run build_runner build      # generates the Drift database code
flutter test
flutter run                      # debug on a device or emulator
flutter build apk --release      # release APK
flutter build appbundle --release  # Play Store bundle
```

Release builds are signed with `android/key.properties` if present (git-ignored); otherwise they fall back to the debug key so a fresh clone still builds. Copy `android/key.properties.example` and point it at your own upload keystore for Play Store builds.

Note: the widget's quick-log button and the notification action buttons start a background Flutter engine. That works in release builds but not from a fully cold start in debug builds, so test those with `flutter build apk --release`.

## Project layout

| Path | What it holds |
| --- | --- |
| `lib/domain/` | Pure Dart logic: schedule calculator, streaks and progress (unit-tested) |
| `lib/data/` | Drift (SQLite) tables and queries |
| `lib/services/` | Notification scheduling, background top-up, widget sync |
| `lib/ui/` | Screens (Today, Reminders, Exercises, Progress) |
| `android/` | Manifest, widget provider and resources, signing config |
| `store_assets/` | Play Store listing assets |
