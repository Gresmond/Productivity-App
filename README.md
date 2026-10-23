# Eclipse

A desktop habit tracker and to-do planner, built with Flutter.

- **Today**: daily rituals with streaks, plus today / this week / this month to-dos and a journal.
- **Months**: the full ritual-by-day grid for any month, with per-month ritual lists.
- Five colour themes. Everything is stored locally in SQLite
  (`~/.local/share/dev.nicholas.productivity_app/productivity.db` on Linux).

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
Run it again to update after pulling new code.

## Building from source

Only needed to work on the code, not to use the app.

```bash
flutter run -d linux
```

After changing `design/icon/eclipse.svg`, run `tool/make_icons.sh` to redraw
the macOS icon sizes.

New Mac builds are published by pushing a version tag (`git tag v1.0.1 && git push --tags`).
