# Eclipse

A desktop habit tracker and to-do planner, built with Flutter.

- **Today**: daily rituals with streaks, plus today / this week / this month to-dos and a journal.
- **Months**: the full ritual-by-day grid for any month, with per-month ritual lists.
- Six colour themes in light/dark pairs. On Hyprland it can follow night
  light, switching to the dark partner while it's on; on a Mac it follows
  Dark mode instead (set Appearance to Auto to have that change at sunset). Everything is stored locally in SQLite
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

**Updating:** Eclipse checks GitHub for a newer release every few hours.
When there is one, a card in the bottom-right corner names it; **Download**
fetches the new `Eclipse.dmg`, to install the same way.

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

## Versions

Versions read `<year since 2025>.<month>.<release that month>`: 1.10.1 is
October 2026's first, and January 2027 starts again at 2.1.1. Each commit
bumps the version in `pubspec.yaml` by itself, once the hook is turned on
(once per clone):

```bash
git config core.hooksPath .githooks
```

Every push to `main` with a version that has no release yet builds
`Eclipse.dmg` on GitHub and publishes it as release `v<version>`.
