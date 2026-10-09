# tangerine-nudge

A Windows tray reminder that won't take no for an answer.

The card stays on screen until you deal with it. Ignore it and it comes back once, 45 minutes
later, then stays quiet for the rest of the day. No main window, no settings dialog.

## Install

Windows 10 19041 or newer. Build with the [.NET 10 SDK](https://dotnet.microsoft.com/):

```powershell
dotnet build nudge.slnx
dotnet run --project nudge
```

`nudge\tools\publish.ps1 -Verify` packs a single self-contained `nudge.exe`. Nudge registers
under `HKCU` and starts with Windows.

## Use

Any way out of a card counts as seen: *Handled*, a successful *Open*, even `Alt+F4`. A card can
carry a launch target, a URL, a `.lnk` or `.exe` path, or a protocol such as `outlook:inbox`,
and the button labels itself from it. Cards stack up from the bottom-right corner.

The tray icon is an eye while reminders are due, a checkmark when you're caught up, and a
crescent moon when Nudge is silent for the day. Double-click opens the settings file;
right-click gives you *Pause today* and *Exit*.

Settings live in `%APPDATA%\Nudge\settings.json` and reload within a second of a save. Keys
starting with `_` are ignored, so the file can carry notes.

```json
{
  "windows": [
    { "at": "11:30", "label": "Morning sweep" },
    { "at": "17:30", "label": "Afternoon sweep", "open": "https://reports.example.com" }
  ],
  "workDays": [1, 2, 3, 4, 5]
}
```

`at` is local time as `"HH:mm"`. `label` is optional and falls back to the time. `open` is an
optional launch target. `workDays` is `1` for Monday through `7` for Sunday, and unlisted days
stay silent.

Debug flags, for when you are changing how the card looks: `--debug-variants`, `--debug-icons`,
`--debug-reminder`, `--force-state waiting|done|silent`, `--force-theme light|dark`.

## Notes

The 45-minute follow-up and the card's refusal to auto-dismiss are not in the settings file.
They are what the app is, so if either is wrong for you, this is the wrong tool.

There are no unit tests. I check changes by running the scripts in `nudge\tools\`, which drive
the real windows and the real tray menu.

## License

MIT
