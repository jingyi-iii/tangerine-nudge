using System.Windows;

namespace Nudge
{
    // Mutex and event use the "Local\" namespace: one instance per logon session
    // (console and RDP sessions each get their own tray).
    public partial class App : Application
    {
        private Mutex? instanceMutex;
        private EventWaitHandle? wakeHandle;
        private SettingsStore? settings;
        private StateStore? state;
        private Reminders? reminders;
        private Scheduler? scheduler;
        private Tray? tray;

        protected override void OnStartup(StartupEventArgs e)
        {
            base.OnStartup(e);

            // A tray app has no window to show a crash in. Without this, an exception on the UI
            // thread takes the process down and leaves nothing but an event-log entry behind.
            DispatcherUnhandledException += (_, args) =>
            {
                Log.Error("Unhandled exception on the UI thread", args.Exception);
            };
            AppDomain.CurrentDomain.UnhandledException += (_, args) =>
                Log.Error("Unhandled exception", args.ExceptionObject as Exception);

            if (e.Args.Contains("--debug-icons"))
            {
                ShutdownMode = ShutdownMode.OnMainWindowClose;
                new MainWindow().Show();
                return;
            }

            // One card of each shape the real world produces: a normal one, one with no target
            // (the narrow card), one with a label long enough to need trimming, and the second,
            // escalating reminder. Stacked together they also exercise the column maths against
            // cards of four different heights — identical cards never did.
            if (e.Args.Contains("--debug-variants"))
            {
                ShutdownMode = ShutdownMode.OnExplicitShutdown;
                Paths.Ensure();
                reminders = new Reminders();
                var shapes = new (WindowItem Item, int Attempt)[]
                {
                    (new WindowItem { At = "11:30", Label = "Morning sweep",
                        Open = "https://tickets.acme.com" }, 1),
                    (new WindowItem { At = "17:30", Label = "Afternoon sweep" }, 1),
                    (new WindowItem { At = "09:00",
                        Label = "Quarterly compliance review backlog sweep (APAC region)",
                        Open = "https://tickets.acme-internal.example.com/queues/compliance" }, 1),
                    (new WindowItem { At = "17:30", Label = "Afternoon sweep",
                        Open = "outlook:inbox" }, 2),
                    // A path-derived button name has no length cap (only http(s) hosts are cut),
                    // so this is the widest "Open ..." the card can ever be asked to wear. It is
                    // also the escalating reminder, whose title is the only one that can outgrow
                    // the card: "<label>: still unchecked".
                    (new WindowItem { At = "10:00",
                        Label = "Quarterly compliance review backlog sweep (APAC region)",
                        Open = @"C:\Tools\GovernanceComplianceReviewBacklogSweep.exe" }, 2),
                };
                foreach (var (item, attempt) in shapes)
                {
                    reminders.Show(item, attempt, () => { });
                }
                Log.Info($"Debug variants shown ({shapes.Length})");
                HoldThenShutdown(e.Args, 20);
                return;
            }

            if (e.Args.Contains("--debug-reminder"))
            {
                ShutdownMode = ShutdownMode.OnExplicitShutdown;
                Paths.Ensure();
                reminders = new Reminders();
                // Several cards at once exercise the stack: how they bubble up and, past the
                // bottom of the screen, which ones get dropped.
                int count = ReadFlagValue(e.Args, "--count") is { } c && int.TryParse(c, out int k)
                    ? Math.Clamp(k, 1, 12) : 1;
                for (int i = 0; i < count; i++)
                {
                    // The open target exercises the "Open …" primary button in debug runs.
                    reminders.Show(
                        new WindowItem { At = "now", Label = $"Debug reminder {i + 1}", Open = "https://example.com" },
                        attempt: 1, onAck: () => { });
                }
                Log.Info($"Debug reminder shown ({count})");
                HoldThenShutdown(e.Args, 20);
                return;
            }

            if (e.Args.Contains("--debug-menu"))
            {
                // The tray menu is normally reached by right-clicking the icon, which nothing
                // automated can do. This opens it at the cursor so its looks can be checked.
                ShutdownMode = ShutdownMode.OnExplicitShutdown;
                Paths.Ensure();
                settings = new SettingsStore();
                state = new StateStore();
                tray = new Tray(settings, state);
                Dispatcher.BeginInvoke(System.Windows.Threading.DispatcherPriority.ApplicationIdle,
                    new Action(() => tray?.ShowMenu()));
                Log.Info("Debug tray menu opened");
                HoldThenShutdown(e.Args, 20);
                return;
            }

            Paths.Ensure();
            string? forceState = ReadFlagValue(e.Args, "--force-state");
            if (forceState is not (null or "waiting" or "done" or "silent"))
            {
                Log.Error($"Unknown --force-state value: {forceState}, ignoring");
                forceState = null;
            }

            // The tray glyph exists in a dark-taskbar flavour and a light-taskbar flavour. This
            // pins the choice so both can be looked at in the real tray without flipping the
            // actual system theme back and forth.
            string? themeArg = ReadFlagValue(e.Args, "--force-theme");
            bool? forceLightTaskbar = themeArg switch { "light" => true, "dark" => false, _ => null };
            if (themeArg != null && forceLightTaskbar == null)
            {
                Log.Error($"Unknown --force-theme value: {themeArg}, ignoring");
            }

            instanceMutex = new Mutex(true, @"Local\Nudge.SingleInstance", out bool isNew);
            if (!isNew)
            {
                WakeFirstInstanceAndExit();
                return;
            }
            ListenForWake();

            Log.Info("Nudge starting");

            settings = new SettingsStore();
            state = new StateStore();
            reminders = new Reminders();

            scheduler = new Scheduler(settings, state, reminders);
            tray = new Tray(settings, state, forceState, forceLightTaskbar);
            settings.Reloaded += _ => tray.Refresh();
            scheduler.Start(() => tray.Refresh());

            EnsureAutoStart();

            Log.Info($"Ready: {settings.Current.Windows.Count} window(s), workdays {string.Join(",", settings.Current.WorkDays)}");
        }

        // Debug runs park for a few seconds so the UI can actually be looked at, then quit.
        private void HoldThenShutdown(string[] args, int defaultSeconds)
        {
            int seconds = ReadFlagValue(args, "--hold") is { } s && int.TryParse(s, out int n)
                ? Math.Clamp(n, 1, 600) : defaultSeconds;
            var hold = new System.Windows.Threading.DispatcherTimer { Interval = TimeSpan.FromSeconds(seconds) };
            hold.Tick += (_, _) => { hold.Stop(); Shutdown(); };
            hold.Start();
        }

        private static string? ReadFlagValue(string[] args, string flag)
        {
            int i = Array.IndexOf(args, flag);
            return i >= 0 && i + 1 < args.Length ? args[i + 1].ToLowerInvariant() : null;
        }

        private void WakeFirstInstanceAndExit()
        {
            Paths.Ensure();
            Log.Info("Second launch detected, waking first instance");
            try
            {
                using var wake = EventWaitHandle.OpenExisting(@"Local\Nudge.Wake");
                wake.Set();
                Thread.Sleep(400);
            }
            catch (Exception ex)
            {
                Log.Error("Could not signal running instance", ex);
            }
            Shutdown();
        }

        private void ListenForWake()
        {
            wakeHandle = new EventWaitHandle(false, EventResetMode.AutoReset, @"Local\Nudge.Wake");
            ThreadPool.RegisterWaitForSingleObject(wakeHandle,
                (o, timedOut) => Dispatcher.BeginInvoke(() => tray?.NotifyAlreadyRunning()),
                null, Timeout.Infinite, false);
        }

        private void EnsureAutoStart()
        {
            if (IsDevLocation()) return;
            if (AutoStart.IsBroken())
            {
                Log.Info(AutoStart.Enable()
                    ? "Autostart path was stale, repointed at the current exe"
                    : "Autostart repair failed (registry)");
            }
            else if (!AutoStart.IsEnabledForCurrentExe() && AutoStart.Enable())
            {
                Log.Info("Autostart registered (HKCU Run)");
            }
        }

        private static bool IsDevLocation()
        {
            var path = Environment.ProcessPath ?? "";
            var temp = Path.GetTempPath();
            return path.StartsWith(temp, StringComparison.OrdinalIgnoreCase)
                || path.Contains(@"\obj\", StringComparison.OrdinalIgnoreCase)
                || path.Contains(@"\bin\Debug", StringComparison.OrdinalIgnoreCase)
                || path.Contains(@"\bin\Release", StringComparison.OrdinalIgnoreCase);
        }

        protected override void OnExit(ExitEventArgs e)
        {
            tray?.Dispose();
            scheduler?.Dispose();
            settings?.Dispose();
            instanceMutex?.Dispose();
            base.OnExit(e);
        }
    }
}
