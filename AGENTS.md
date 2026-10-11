# tangerine-nudge

A Windows tray reminder.  The card stays on screen until it is dealt with, follows up once after 45 minutes, then stays quiet for the rest of the day.  No main window and no settings dialog: a tray icon, a card and one JSON file.

## Layout

| Path | Purpose |
| --- | --- |
| `nudge/App.xaml(.cs)` | Entry point, single-instance guard, autostart, debug flags |
| `nudge/Scheduler.cs` | 15-second tick: is a window due, has it been answered |
| `nudge/Reminders.cs` | The card stack: positioning, rise animation, overflow |
| `nudge/ReminderWindow.xaml(.cs)` | The card itself |
| `nudge/Tray.cs` | Tray icon, glyph state, right-click menu |
| `nudge/TrayMenuWindow.xaml(.cs)` | The menu, a real window so it can be dismissed |
| `nudge/SettingsStore.cs` | `settings.json` and its hot reload |
| `nudge/StateStore.cs` | Per-day sent, acked and paused state |
| `nudge/AutoStart.cs` | `HKCU` Run registration and repair |
| `nudge/SystemTheme.cs` | Light/dark taskbar detection |
| `nudge/CardTheme.xaml` | Single source of truth for the palette |
| `nudge/tools/` | Publish, clean, reset, icon generation, QA scripts |

## Language conventions

- Conversation with the user: Chinese.
- All generated artifacts and files (including this `AGENTS.md`): English.

## README style

`README.md` follows the house style of the other `jingyi-iii` repositories
(`begonia-os`, `begonia-pciesim`, `tangerine-github-access`, `tangerine-screenshot`):

- the title is `# <repo-name>` alone, with no tagline on the same line;
- two or three short prose paragraphs open it: what it is, what works today, what is unusual
  about it. No bullet list and no bold `**Status:**` line up front;
- one table follows, here the layout table;
- then `## Install`, `## Use`, `## Notes`, `## License`, in that order. `## How it
  works` may be inserted between `Use` and `Notes` when there is something worth
  explaining;
- commands in a block carry `#` comments that state their cost (size, minutes);
- `## Notes` states the limitations, why the large artefacts are untracked, the licences of
  the dependencies, and the development environment, in the first person and plainly;
- `## License` is that heading followed by `MIT` and nothing else;
- no badges, no emoji, no table of contents, hard wrap at 100 columns.

## Commit messages

[Conventional Commits](https://www.conventionalcommits.org/), in English, with the subsystem as
the scope:

```
<type>(<scope>): <imperative summary, <= 50 chars, no trailing period>

<body: why the change is needed, not what the diff already shows; wrap at 72>

<footer: BREAKING CHANGE: ..., Closes #12, Refs: ...>
```

- `type`: `feat`, `fix`, `build`, `docs`, `refactor`, `perf`, `test`, `chore`,
  `ci`, `style`, `revert`
- `scope`: `app`, `card`, `tray`, `settings`, `theme`, `tools`, `docs`, `repo`
- One logical change per commit.
- Mark incompatible changes with `!` after the scope, or with a `BREAKING CHANGE:` footer.
- `.gitmessage` holds the template; `git config commit.template .gitmessage` makes
  `git commit` open the editor with it.