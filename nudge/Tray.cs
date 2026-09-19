using System.Diagnostics;
using System.Drawing;
using System.Windows.Forms;
using Microsoft.Win32;

namespace Nudge
{
    internal sealed class Tray : IDisposable
    {
        private readonly SettingsStore settings;
        private readonly StateStore state;
        private readonly NotifyIcon icon;
        private readonly string? forceState;

        // Which of the two glyph sets the tray is wearing, and whether the OS is allowed to change
        // that. --force-theme pins it for eyeballing both sets without touching the registry.
        private readonly bool? forcedLightTaskbar;
        private bool onLightTaskbar;

        // Setting NotifyIcon.Icon makes the shell rebuild the tray button, so a fast scheduler
        // tick must not push identical state.
        private string lastTip = "";
        private Icon? lastGlyph;

        // The taskbar is the one surface Nudge does not own, so the glyph is drawn twice: light
        // strokes for a dark taskbar, dark strokes for a light one. Same eye, same orange pupil.
        // See tools/gen-icons.ps1.
        private static readonly Icon WaitingOnDark = LoadIcon("nudge-waiting");
        private static readonly Icon DoneOnDark = LoadIcon("nudge-done");
        private static readonly Icon SilentOnDark = LoadIcon("nudge-silent");
        private static readonly Icon WaitingOnLight = LoadIcon("nudge-waiting-light");
        private static readonly Icon DoneOnLight = LoadIcon("nudge-done-light");
        private static readonly Icon SilentOnLight = LoadIcon("nudge-silent-light");

        // The glyph is an eye: Nudge's whole job is "take one glance at the tickets".
        // waiting = open eye with an orange pupil, done = eye with an orange check,
        // silent = crescent moon. See tools/gen-icons.ps1.
        private static Icon LoadIcon(string name)
        {
            var uri = new Uri($"pack://application:,,,/Assets/{name}.ico");
            var info = System.Windows.Application.GetResourceStream(uri)
                ?? throw new InvalidOperationException($"Missing icon asset: {name}.ico");
            using var stream = info.Stream;
            return new Icon(stream);
        }

        private (Icon Waiting, Icon Done, Icon Silent) Current() =>
            onLightTaskbar
                ? (WaitingOnLight, DoneOnLight, SilentOnLight)
                : (WaitingOnDark, DoneOnDark, SilentOnDark);

        public Tray(SettingsStore settings, StateStore state, string? forceState = null,
            bool? forceLightTaskbar = null)
        {
            this.settings = settings;
            this.state = state;
            this.forceState = forceState;
            this.forcedLightTaskbar = forceLightTaskbar;
            onLightTaskbar = forceLightTaskbar ?? SystemTheme.TaskbarIsLight();
            Log.Info($"Tray glyph: {(onLightTaskbar ? "dark strokes (light taskbar)" : "light strokes (dark taskbar)")}"
                + (forceLightTaskbar == null ? "" : " [forced]"));

            icon = new NotifyIcon
            {
                Visible = true,
                Icon = Current().Waiting,
                Text = "Nudge",
            };
            // No ContextMenuStrip here: its classic renderer cannot be talked out of its Windows 7
            // looks, and a WPF ContextMenu has no window to be deactivated. ShowMenu builds
            // TrayMenuWindow instead — the card's skin on something that can be dismissed.
            icon.MouseUp += (_, e) =>
            {
                if (e.Button == MouseButtons.Right) ShowMenu();
            };
            icon.DoubleClick += (_, _) => Launch(Paths.Settings);

            if (forcedLightTaskbar == null)
            {
                // Switching Windows between light and dark repaints the taskbar underneath us and
                // can leave the glyph invisible. SystemEvents raises this on its own thread, and
                // the icon belongs to the UI thread — so everything changes back over there.
                try
                {
                    SystemEvents.UserPreferenceChanged += OnUserPreferenceChanged;
                }
                catch (Exception ex)
                {
                    Log.Error("Could not listen for system theme changes; the glyph will not follow", ex);
                }
            }
            Refresh();
        }

        // Fires for wallpaper, accent colour and taskbar size as well as the light/dark switch.
        // Re-reading one DWORD costs less than working out which of those matter, and Refresh()
        // is a no-op when nothing it looks at actually moved.
        private void OnUserPreferenceChanged(object sender, UserPreferenceChangedEventArgs e)
        {
            bool light = SystemTheme.TaskbarIsLight();
            var dispatcher = System.Windows.Application.Current?.Dispatcher;
            if (dispatcher == null) return;
            dispatcher.BeginInvoke(new Action(() =>
            {
                if (light == onLightTaskbar) return;
                onLightTaskbar = light;
                Log.Info($"The taskbar is now {(light ? "light" : "dark")}; switching the tray glyph");
                Refresh();
            }));
        }

        public void Refresh()
        {
            var s = settings.Current;
            var now = DateTime.Now;
            var (waiting, done, silent) = Current();
            string tip;
            Icon glyph;
            if (forceState != null)
            {
                (tip, glyph) = forceState switch
                {
                    "waiting" => ("[debug] waiting", waiting),
                    "done" => ("[debug] done", done),
                    _ => ("[debug] silent", silent),
                };
            }
            else if (!s.IsWorkDay(now))
            {
                tip = "rest day, silent today";
                glyph = silent;
            }
            else if (s.Windows.Count == 0)
            {
                tip = "no windows configured";
                glyph = silent;
            }
            else if (state.IsPausedToday)
            {
                tip = "paused for today";
                glyph = done;
            }
            else
            {
                int left = s.Windows.Count(w => state.Today.For(w.At).Acked == null);
                if (left == 0)
                {
                    tip = "all caught up";
                    glyph = done;
                }
                else
                {
                    tip = $"{left} check(s) left today";
                    glyph = waiting;
                }
            }
            if (tip == lastTip && ReferenceEquals(glyph, lastGlyph)) return;
            icon.Text = "Nudge - " + tip;
            icon.Icon = glyph;
            lastTip = tip;
            lastGlyph = glyph;
        }

        public void NotifyAlreadyRunning()
        {
            icon.ShowBalloonTip(4000, "Nudge is already running",
                "The eye icon is in the tray, possibly under the ^ chevron.",
                ToolTipIcon.Info);
        }

        // Built fresh on every right click: the pause row states today's truth, and the tray can
        // be clicked at any hour. Public so the --debug-menu run can open it without a mouse.
        public void ShowMenu()
        {
            var menu = new TrayMenuWindow();
            menu.AddRow("Open settings", () => Launch(Paths.Settings));

            // Silencing the whole day is a deliberate decision, so it lives here — not on a
            // reminder card that happens to be in the way.
            menu.AddRow(state.IsPausedToday ? "Resume today" : "Pause today", TogglePause);

            menu.AddDivider();
            menu.AddRow("Exit", () => System.Windows.Application.Current.Shutdown());

            menu.ShowAtCursor();
        }

        private void TogglePause()
        {
            if (state.IsPausedToday)
            {
                state.ResumeToday();
                Log.Info("Resumed reminders for today (tray)");
            }
            else
            {
                state.PauseToday();
                Log.Info("Paused for today (tray)");
            }
            Refresh();
        }

        private static void Launch(string path)
        {
            try
            {
                Process.Start(new ProcessStartInfo(path) { UseShellExecute = true });
            }
            catch (Exception ex)
            {
                Log.Error($"Could not open {path}", ex);
            }
        }

        public void Dispose()
        {
            // SystemEvents is static: an unsubscribed handler outlives the tray and keeps a dead
            // window-less app alive on every preference change.
            if (forcedLightTaskbar == null)
            {
                SystemEvents.UserPreferenceChanged -= OnUserPreferenceChanged;
            }
            icon.Visible = false;
            icon.Dispose();
        }
    }
}
