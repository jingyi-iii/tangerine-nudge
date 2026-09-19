using System.Windows.Threading;

namespace Nudge
{
    internal sealed class Scheduler : IDisposable
    {
        private readonly SettingsStore settings;
        private readonly StateStore state;
        private readonly Reminders reminders;
        private readonly DispatcherTimer timer;
        private Action refreshTray = () => { };

        public Scheduler(SettingsStore settings, StateStore state, Reminders reminders)
        {
            this.settings = settings;
            this.state = state;
            this.reminders = reminders;
            timer = new DispatcherTimer { Interval = TimeSpan.FromSeconds(15) };
            timer.Tick += (_, _) => Tick();
        }

        public void Start(Action refreshTray)
        {
            this.refreshTray = refreshTray;
            timer.Start();
            Tick();
        }

        private void Tick()
        {
            try
            {
                Run();
            }
            catch (Exception ex)
            {
                Log.Error("Scheduler tick failed", ex);
            }
            finally
            {
                refreshTray();
            }
        }

        private void Run()
        {
            var s = settings.Current;
            var now = DateTime.Now;
            var today = state.Today;

            if (!s.IsWorkDay(now)) return;
            if (state.IsPausedToday) return;

            foreach (var window in s.Windows)
            {
                if (!AppSettings.TryParseTime(window.At, out var time)) continue;
                var due = now.Date.Add(time.ToTimeSpan());
                var ws = today.For(window.At);

                if (ws.Acked != null) continue;
                if (now < due) continue;

                // The second reminder is timed from when the first one actually went out,
                // so a late app start never fires both back to back.
                if (ws.Sent == 0)
                {
                    Fire(window, attempt: 1);
                }
                else if (ws.Sent == 1
                         && ws.LastSent != null
                         && now >= ws.LastSent.Value.AddMinutes(AppSettings.EscalateAfterMinutes))
                {
                    Fire(window, attempt: 2);
                }
            }
        }

        private void Fire(WindowItem window, int attempt)
        {
            var firedDay = DateTime.Today;
            state.MarkSent(window.At);

            // A card can sit on screen past midnight, so acting on it the next day must not
            // mutate the new day's state.
            bool IsFresh()
            {
                if (firedDay == DateTime.Today) return true;
                Log.Info($"Ignoring action on a leftover reminder from {firedDay:yyyy-MM-dd}");
                return false;
            }

            reminders.Show(window, attempt,
                onAck: () =>
                {
                    if (!IsFresh()) return;
                    state.AckWindow(window.At);
                    Log.Info($"Acknowledged: {window.Display}");
                    refreshTray();
                });
            Log.Info($"Reminder: {window.Display} ({window.At}) attempt {attempt}");
        }

        public void Dispose() => timer.Stop();
    }
}
