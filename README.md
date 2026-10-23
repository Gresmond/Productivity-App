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

## Installing on a Mac

1. Open the [latest release](https://github.com/Gresmond/Productivity-App/releases/latest)
   and download `Productivity.dmg`.
2. Open the downloaded file and drag **Productivity** onto the **Applications** folder.
3. Open Productivity from Applications. The first time, macOS says it can't
   verify the app: click **Done**, then go to **System Settings → Privacy &
   Security**, scroll down and click **Open Anyway**. After that it opens normally.

New Mac builds are published by pushing a version tag (`git tag v1.0.1 && git push --tags`).

The fonts (Gellix, Matter, Reckless) are trial licences and are only in the repo
encrypted, as `fonts.tar.gz.gpg`. Unpack them with the password in `fonts.passphrase`
(not committed; also stored as the `FONTS_PASSPHRASE` GitHub secret):

```bash
gpg --batch --passphrase-file fonts.passphrase -d fonts.tar.gz.gpg | tar -xzf -
```

After changing the fonts, re-create the archive from the paths in `pubspec.yaml`:

```bash
grep -o "assets/fonts/[^ ]*" pubspec.yaml | sort -u | tar -czf - -T - | gpg --batch --yes --symmetric --cipher-algo AES256 --passphrase-file fonts.passphrase -o fonts.tar.gz.gpg
```
