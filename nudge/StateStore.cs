using System.Text.Json;
using System.Text.Json.Serialization;

namespace Nudge
{
    internal sealed class WindowState
    {
        public int Sent { get; set; }
        public DateTime? LastSent { get; set; }
        public DateTime? Acked { get; set; }
    }

    internal sealed class DayState
    {
        public Dictionary<string, WindowState> Windows { get; set; } = new();
        public string? PausedOn { get; set; }

        public WindowState For(string windowKey)
        {
            if (!Windows.TryGetValue(windowKey, out var ws))
                Windows[windowKey] = ws = new WindowState();
            return ws;
        }
    }

    internal sealed class StateStore
    {
        private static readonly JsonSerializerOptions JsonOpts = new()
        {
            WriteIndented = true,
        };

        private readonly Dictionary<string, DayState> days = new();

        public DayState Today => For(DateTime.Today);

        public DayState For(DateTime day)
        {
            var key = day.ToString("yyyy-MM-dd");
            if (!days.TryGetValue(key, out var d))
                days[key] = d = new DayState();
            return d;
        }

        public bool IsPausedToday => Today.PausedOn == DateTime.Today.ToString("yyyy-MM-dd");

        public void PauseToday()
        {
            Today.PausedOn = DateTime.Today.ToString("yyyy-MM-dd");
            Save();
        }

        public void ResumeToday()
        {
            Today.PausedOn = null;
            Save();
        }

        public void AckWindow(string windowKey)
        {
            Today.For(windowKey).Acked = DateTime.Now;
            Save();
        }

        public void MarkSent(string windowKey)
        {
            var ws = Today.For(windowKey);
            ws.Sent++;
            ws.LastSent = DateTime.Now;
            Save();
        }

        // By design only today's state is ever read, so old days are dropped on save.
        public void PruneOld()
        {
            foreach (var key in days.Keys.Where(k => k != DateTime.Today.ToString("yyyy-MM-dd")).ToList())
                days.Remove(key);
        }

        public StateStore()
        {
            try
            {
                if (File.Exists(Paths.State))
                {
                    var loaded = JsonSerializer.Deserialize<Dictionary<string, DayState>>(
                        File.ReadAllText(Paths.State), JsonOpts);
                    if (loaded != null)
                        foreach (var kv in loaded)
                            days[kv.Key] = kv.Value;
                }
            }
            catch (Exception ex)
            {
                Log.Error("state.json unreadable, starting fresh", ex);
            }
        }

        public void Save()
        {
            try
            {
                PruneOld();
                var tmp = Paths.State + ".tmp";
                File.WriteAllText(tmp, JsonSerializer.Serialize(days, JsonOpts));
                File.Move(tmp, Paths.State, true);
            }
            catch (Exception ex)
            {
                Log.Error("Failed to save state.json", ex);
            }
        }
    }
}
