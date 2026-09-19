# Nudge

A tray app that reminds you to go look at the ticket system — and won't take no for
an answer. No main window, no settings dialog, one job.

Most reminder tools fire a toast and forget about it. Nudge assumes the reminder is
the thing you *skip*, so it behaves differently: the card stays on screen until you
deal with it, and if you don't, it comes back once.

## Features

- **The card stays put.** It never times out or slides away on its own. Dismissing it
  is a deliberate act, which is the whole point.
- **One follow-up, then silence.** An unanswered card returns once, 45 minutes later.
  After that Nudge leaves you alone for the day.
- **Looking is enough.** Any way the card goes away — *Handled*, a successful *Open*,
  even `Alt+F4` — counts as seen. There is no separate "confirm" step to lie to.
- **Launch the thing you're being reminded about.** A card can carry a target: a URL,
  an `.lnk`/`.exe` path, or a protocol (`outlook:inbox`, `mailto:…`). The button
  labels itself from the target, so there is nothing extra to configure.
- **Works out your week.** Only remind on the days you list. Other days the tray stays
  a crescent moon and nothing appears.
- **Pause without opening anything.** "Pause today" lives in the tray menu for the
  days you're not doing tickets.
- **Stacks without clutter.** Multiple due reminders stack up from the bottom-right
  corner, newest at the corner, older ones rising above it.
- **Follows your theme.** The tray glyph ships in a dark-taskbar and a light-taskbar
  flavour and switches with the Windows setting.
- **Starts with Windows, and repairs itself.** Registers under `HKCU` and re-points
  itself if you move the exe.

## Usage

**Tray icon** — an eye. Open = checks still due today. Checkmark = all caught up.
Crescent moon = silent today (rest day, paused, or nothing configured).

| Action | How |
| --- | --- |
| Open the settings file | Double-click the tray icon |
| Menu (Open settings / Pause or Resume today / Exit) | Right-click the tray icon |
| Mark a reminder handled | *Handled* on the card |
| Open the reminder's target | *Open …* on the card |
| Snooze by ignoring it | do nothing — the card waits, and comes back once after 45 minutes |

Hovering a card's buttons explains what they do — *Handled* in particular says that
dismissing the card is what stops it counting for today.

## Configuration

Settings live in `%APPDATA%\Nudge\settings.json`. The file is seeded on first run and
**reloads within a second of a save** — no restart, no UI to click through.

```json
{
  "_comment": "Nudge settings. Changes apply within seconds; no restart needed.",
  "windows": [
    { "at": "11:30", "label": "Morning sweep" },
    { "at": "17:30", "label": "Afternoon sweep", "open": "https://tickets.example.com" }
  ],
  "_windows_help": "…",
  "workDays": [1, 2, 3, 4, 5],
  "_workdays_help": "Monday = 1 ... Sunday = 7. Days not listed stay silent."
}
```

- `at` — 24-hour local time, `"HH:mm"`, minute resolution.
- `label` — what the card calls it. Optional; the time is shown if you leave it out.
- `open` — optional launch target for the card's main button: a URL, a shortcut or
  `.exe` path, or a protocol such as `outlook:inbox` or `mailto:boss@acme.com`. Leave
  it out and the card offers only *Handled*.
- `workDays` — `1` = Monday … `7` = Sunday.

The `_`-prefixed keys are inert documentation for whoever edits the file next; Nudge
ignores anything it doesn't recognise. Entries with an unparseable time are skipped
with a log line rather than breaking the whole file.

Other state (`state.json`, `nudge.log`) sits beside it in the same folder. The log
rotates at 512 KB.

### Things that are deliberately not configurable

The 45-minute follow-up interval is the app's character, not a preference. Neither is
the card's refusal to auto-dismiss. If either is wrong for you, this is the wrong tool —
which is a fair outcome.

## Requirements

- Windows 10 19041 or newer
- [.NET 10 SDK](https://dotnet.microsoft.com/) to build from source

## Build

```powershell
dotnet build nudge.slnx
dotnet run --project nudge
```

## Publish a single executable

`tools\publish.ps1` produces one self-contained `nudge.exe` with the .NET runtime and
every managed and native library packed inside it — the output folder holds that file
and nothing else, so it can be copied to a machine that has never seen .NET.

```powershell
nudge\tools\publish.ps1 -Verify
```

`-Verify` doesn't just check the file exists: it runs the published exe, waits for it to
exit on its own, and requires exit code `0` with a clean startup line in the log. The
debug paths return before the autostart code, so the check writes nothing to the registry.

Reasoning behind the pinned build properties (why `IncludeNativeLibrariesForSelfExtract`
is load-bearing, and why the trimmer must stay off) is in the script's header.

Other scripts:

```powershell
nudge\tools\clean.ps1 -WhatIf    # preview: remove build output (bin, obj, dist, .vs)
nudge\tools\reset.ps1 -WhatIf    # preview: remove %APPDATA%\Nudge and the HKCU Run entry
nudge\tools\gen-icons.ps1        # regenerate the tray glyphs from code
```

`reset.ps1` moves the settings folder aside as a timestamped backup by default
(`-Purge` deletes it outright) — your configured reminder times are your own work, and
being able to change your mind matters more than a tidy disk.

## Debug flags

Useful when you're changing how the app looks and need it on screen now:

```powershell
nudge.exe --debug-icons                       # icon gallery: both stroke sets, both taskbar shades
nudge.exe --debug-variants                    # one card of each shape it can take, stacked
nudge.exe --debug-reminder --count 4 --hold 20  # N identical cards (stack behaviour)
nudge.exe --debug-menu --hold 10               # open the tray menu at the cursor
nudge.exe --force-state waiting|done|silent    # pin the tray glyph
nudge.exe --force-theme light|dark             # pin the taskbar flavour, without touching Windows
```

## Project layout

```
nudge.slnx
nudge/
  App.xaml(.cs)             entry point, single-instance guard, autostart, debug flags
  Scheduler.cs              15-second tick: is this window due, has it been answered
  Reminders.cs              card stack: positioning, rise animation, overflow
  ReminderWindow.xaml(.cs)  the card itself
  Tray.cs                   tray icon, glyph state, right-click menu
  TrayMenuWindow.xaml(.cs)  the menu, a real window so it can be dismissed
  SettingsStore.cs          settings.json + hot reload
  StateStore.cs             per-day sent/acked/paused state
  AutoStart.cs              HKCU Run registration and repair
  SystemTheme.cs            light/dark taskbar detection
  CardTheme.xaml            single source of truth for the app's palette
  Paths.cs / Log.cs         where files live; rotating log
  Assets/                   generated tray glyphs (dark and light taskbar flavours)
  tools/                    icon generation, publish, clean, reset
```

## License

[MIT](LICENSE)
