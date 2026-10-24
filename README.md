# Eclipse

A desktop habit tracker and to-do planner, built with Flutter.

- **Today**: daily rituals with streaks, plus today / this week / this month to-dos and a journal.
- **Months**: the full ritual-by-day grid for any month, with per-month ritual lists.
- Six colour themes in light/dark pairs. On Hyprland it can follow night
  light, switching to the dark partner while it's on; on a Mac it follows
  Dark mode instead (set Appearance to Auto to have that change at sunset). Everything is stored locally in SQLite
  (`~/.local/share/dev.nicholas.productivity_app/productivity.db` on Linux).
- The journal is also saved as one Markdown file per day in
  `~/Documents/Eclipse Journal/<year>/`, readable without the app. These
  are a copy: the database holds the journal, and edits made to the files
  themselves aren't read back.

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