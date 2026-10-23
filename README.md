# Eclipse

A desktop habit tracker and to-do planner, built with Flutter.

- **Today**: daily rituals with streaks, plus today / this week / this month to-dos and a journal.
- **Months**: the full ritual-by-day grid for any month, with per-month ritual lists.
- Eight colour themes in light/dark pairs. On Hyprland it can follow night
  light, switching to the dark partner while it's on. Everything is stored locally in SQLite
  (`~/.local/share/dev.nicholas.productivity_app/productivity.db` on Linux).
- The journal is saved as one Markdown file per day in
  `~/Documents/Eclipse Journal/<year>/`, readable without the app. (The
  database keeps a copy for backups, but restoring a backup leaves these
  files alone.)

## Installing on a Mac

The fonts are built into the app, so there is nothing else to install.

1. Open the [latest release](https://github.com/Gresmond/Productivity-App/releases/latest)
   and download `Eclipse.dmg`.
2. Open the downloaded file and drag **Eclipse** onto the **Applications** folder.
3. Open Eclipse from Applications. The first time, macOS says it can't
   verify the app: click **Done**, then go to **System Settings → Privacy &
   Security**, scroll down and click **Open Anyway**. After that it opens normally.

## Installing on Linux

```bash
linux/install.sh
```

This builds the app and adds **Eclipse** to your app launcher, with its icon.

**Updating:** the app remembers which commit of this folder it was built
from. When the folder has newer commits, a card in the bottom-right corner
offers **Update and reopen**, which runs `linux/install.sh` again and
restarts Eclipse. It checks on launch and every two minutes, and only looks at
this folder: pull first if the new code is on GitHub.

## Building from source

Only needed to work on the code, not to use the app.

```bash
flutter run -d linux
```

After changing `design/icon/eclipse.svg`, run `tool/make_icons.sh` to redraw
the macOS icon sizes.

New Mac builds are published by pushing a version tag (`git tag v1.0.1 && git push --tags`).
