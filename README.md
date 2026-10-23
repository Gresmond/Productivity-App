# Productivity App

A desktop habit tracker and to-do planner, built with Flutter for Linux.

- **Today**: daily rituals with streaks, plus today / this week / this month to-dos and a journal.
- **Months**: the full ritual-by-day grid for any month, with per-month ritual lists.
- Five colour themes. Everything is stored locally in SQLite
  (`~/.local/share/dev.nicholas.productivity_app/productivity.db`).

## Running

```bash
flutter run -d linux
```

The fonts (Gellix, Matter, Reckless) are trial licences and are not in the repo.
Copy them into `assets/fonts/<family>/` using the paths listed in `pubspec.yaml`
before building.
