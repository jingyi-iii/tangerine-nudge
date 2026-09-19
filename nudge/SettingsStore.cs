using System.IO;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using System.Text.Json.Serialization;
using System.Windows.Threading;

namespace Nudge
{
    [JsonConverter(typeof(WindowItemConverter))]
    internal sealed class WindowItem
    {
        public string At { get; set; } = "";
        public string Label { get; set; } = "";

        // Optional target the card's main button launches: a URL ("https://tickets…"),
        // a shortcut/path ("C:\\...\\Outlook.lnk"), or a protocol ("outlook:inbox").
        // Empty means the card only offers "Handled".
        public string Open { get; set; } = "";

        [JsonIgnore]
        public string Display => string.IsNullOrWhiteSpace(Label) ? At : Label;

        // Short friendly name for the "Open …" button, derived from the target itself so
        // no extra config is needed: "https://tickets.acme.com" → "tickets.acme.com",
        // "outlook:inbox" → "Outlook", "C:\...\Outlook.lnk" → "Outlook".
        [JsonIgnore]
        public string OpenName => DeriveOpenName(Open);

        // Every derived name is cut to this length. The button it lands on sits beside "Handled"
        // and the pair has to fit inside the card; a name with no ceiling (a long exe path has
        // none) widens the row until the dismiss button is pushed off the panel.
        private const int MaxOpenName = 24;

        private static string DeriveOpenName(string open)
        {
            if (string.IsNullOrWhiteSpace(open)) return "";
            try
            {
                if (Uri.TryCreate(open, UriKind.Absolute, out var uri) && uri.Scheme.Length > 1)
                {
                    switch (uri.Scheme.ToLowerInvariant())
                    {
                        case "http":
                        case "https":
                            var host = uri.Host.StartsWith("www.", StringComparison.OrdinalIgnoreCase)
                                ? uri.Host[4..]
                                : uri.Host;
                            return Cap(host);
                        case "outlook":
                            return "Outlook";
                        case "mailto":
                            return "mail";
                        case "file":
                            return Cap(Friendly(Path.GetFileNameWithoutExtension(uri.LocalPath)));
                    }
                }
            }
            catch
            {
                // fall through to the file-name guess
            }
            try { return Cap(Friendly(Path.GetFileNameWithoutExtension(open))); }
            catch { return "target"; }
        }

        // A hard slice reads as a different name. "tickets.acme-internal.example.com" cut at 24
        // characters ends in ".ex", which looks like some other, wrong domain rather than a short
        // one — so where a dot falls late in the name the cut steps back to it, and every cut is
        // marked. It only ever steps back: the result is never longer than the ceiling.
        private static string Cap(string name)
        {
            if (name.Length <= MaxOpenName) return name;
            int dot = name.LastIndexOf('.', MaxOpenName);
            int cut = dot >= MaxOpenName / 2 ? dot : MaxOpenName;
            return name[..cut].TrimEnd('-', '.') + "\u2026";
        }

        // "notepad" reads better as "Notepad" on a button; deliberate casing is left alone.
        private static string Friendly(string name)
        {
            if (name.Length == 0 || name.Any(char.IsUpper)) return name;
            return char.ToUpperInvariant(name[0]) + name[1..];
        }
    }

    // Accepts either "11:30" or { "at": "11:30", "label": "Morning sweep" }.
    // Values it does not understand are skipped, never fatal.
    internal sealed class WindowItemConverter : JsonConverter<WindowItem>
    {
        public override WindowItem? Read(ref Utf8JsonReader reader, Type typeToConvert, JsonSerializerOptions options)
        {
            if (reader.TokenType == JsonTokenType.String)
                return new WindowItem { At = reader.GetString() ?? "" };
            if (reader.TokenType != JsonTokenType.StartObject)
                throw new JsonException("window entry must be a string or object");

            var item = new WindowItem();
            while (reader.Read() && reader.TokenType != JsonTokenType.EndObject)
            {
                var name = reader.GetString();
                reader.Read();
                var value = ReadStringValue(ref reader);
                if (string.Equals(name, "at", StringComparison.OrdinalIgnoreCase)) item.At = value;
                else if (string.Equals(name, "label", StringComparison.OrdinalIgnoreCase)) item.Label = value;
                else if (string.Equals(name, "open", StringComparison.OrdinalIgnoreCase)) item.Open = value;
            }
            return item;
        }

        private static string ReadStringValue(ref Utf8JsonReader reader)
        {
            switch (reader.TokenType)
            {
                case JsonTokenType.String: return reader.GetString() ?? "";
                case JsonTokenType.Number: return reader.TryGetInt32(out var i) ? i.ToString() : reader.GetDouble().ToString();
                case JsonTokenType.True:
                case JsonTokenType.False: return reader.GetBoolean().ToString();
                case JsonTokenType.Null: return "";
                // Nested container: jump over it entirely.
                case JsonTokenType.StartObject:
                case JsonTokenType.StartArray:
                    reader.Skip();
                    return "";
                default: return "";
            }
        }

        public override void Write(Utf8JsonWriter writer, WindowItem value, JsonSerializerOptions options)
        {
            writer.WriteStartObject();
            writer.WriteString("at", value.At);
            writer.WriteString("label", value.Label);
            if (!string.IsNullOrWhiteSpace(value.Open)) writer.WriteString("open", value.Open);
            writer.WriteEndObject();
        }
    }

    internal sealed class AppSettings
    {
        public List<WindowItem> Windows { get; set; } = new();
        public List<int> WorkDays { get; set; } = new();

        // The second, final reminder fires this long after the first one went unanswered.
        // Not configurable on purpose: it is part of Nudge's character, not a preference.
        public const int EscalateAfterMinutes = 45;

        public static AppSettings Defaults() => new()
        {
            Windows = new List<WindowItem>
            {
                new() { At = "11:30", Label = "Morning sweep" },
                new() { At = "17:30", Label = "Afternoon sweep" },
            },
            WorkDays = new List<int> { 1, 2, 3, 4, 5 },
        };

        public bool IsWorkDay(DateTime day)
        {
            int dow = (int)day.DayOfWeek;
            return WorkDays.Contains(dow == 0 ? 7 : dow);
        }

        // "HH:mm", 24-hour local time, minute resolution.
        public static bool TryParseTime(string value, out TimeOnly time) =>
            TimeOnly.TryParseExact(value, "HH:mm",
                System.Globalization.CultureInfo.InvariantCulture,
                System.Globalization.DateTimeStyles.None, out time);
    }

    // Raw shape: nulls distinguish "field missing" from "explicitly empty".
    internal sealed class SettingsDto
    {
        public List<WindowItem>? Windows { get; set; }
        public List<int>? WorkDays { get; set; }
    }

    internal sealed class SettingsStore : IDisposable
    {
        private static readonly JsonSerializerOptions JsonOpts = new()
        {
            PropertyNameCaseInsensitive = true,
            WriteIndented = true,
        };

        private readonly DispatcherTimer debounce;
        private FileSystemWatcher? watcher;
        private string contentHash = "";
        private int readRetries;

        public AppSettings Current { get; private set; } = AppSettings.Defaults();

        public event Action<AppSettings>? Reloaded;

        public SettingsStore()
        {
            debounce = new DispatcherTimer { Interval = TimeSpan.FromMilliseconds(300) };
            debounce.Tick += (_, _) =>
            {
                debounce.Stop();
                TryReload();
            };

            if (!File.Exists(Paths.Settings))
                Seed();
            Load();

            watcher = new FileSystemWatcher(Paths.Root, "settings.json")
            {
                NotifyFilter = NotifyFilters.LastWrite | NotifyFilters.Size | NotifyFilters.FileName,
            };
            // Changed covers in-place saves; Created/Renamed cover editors that save via rename.
            watcher.Changed += (_, _) => ScheduleReload();
            watcher.Created += (_, _) => ScheduleReload();
            watcher.Renamed += (_, _) => ScheduleReload();
            watcher.EnableRaisingEvents = true;
        }

        private void Seed()
        {
            // _* keys are inert documentation for whoever edits the file.
            var doc = """
            {
              "_comment": "Nudge settings. Changes apply within seconds; no restart needed.",
              "windows": [
                { "at": "11:30", "label": "Morning sweep" },
                { "at": "17:30", "label": "Afternoon sweep" }
              ],
              "_windows_help": "24-hour local times (\"HH:mm\") to nudge you to check the ticket system. 'label' shows in the reminder; 'at' alone is fine too. 'open' (optional) makes the card's main button launch it: a website (\"https://tickets.example.com\"), a shortcut or exe path, or a protocol (\"outlook:inbox\", \"mailto:boss@acme.com\"). An empty list means: never remind.",
              "workDays": [1, 2, 3, 4, 5],
              "_workdays_help": "Monday = 1 ... Sunday = 7. Days not listed stay silent."
            }
            """;
            File.WriteAllText(Paths.Settings, doc);
        }

        private void ScheduleReload()
        {
            System.Windows.Application.Current.Dispatcher.BeginInvoke(() =>
            {
                readRetries = 0;
                debounce.Stop();
                debounce.Start();
            });
        }

        private void TryReload()
        {
            string text;
            try
            {
                text = File.ReadAllText(Paths.Settings);
            }
            catch (IOException) when (readRetries++ < 8)
            {
                debounce.Start(); // editor still mid-write
                return;
            }
            catch (Exception ex)
            {
                Log.Error("settings.json could not be read, keeping previous settings", ex);
                return;
            }

            if (Hash(text) == contentHash) return;
            try
            {
                Apply(text);
            }
            catch (Exception ex)
            {
                Log.Error("settings.json could not be parsed, keeping previous settings", ex);
            }
        }

        private void Load()
        {
            try
            {
                Apply(File.ReadAllText(Paths.Settings));
            }
            catch (Exception ex)
            {
                Log.Error("Failed to load settings.json, using defaults", ex);
                Current = AppSettings.Defaults();
            }
        }

        private void Apply(string text)
        {
            var dto = JsonSerializer.Deserialize<SettingsDto>(text, JsonOpts)
                ?? throw new InvalidDataException("empty settings");
            var defaults = AppSettings.Defaults();
            var parsed = new AppSettings
            {
                WorkDays = dto.WorkDays ?? defaults.WorkDays,
            };

            var windows = new List<WindowItem>();
            foreach (var w in dto.Windows ?? defaults.Windows)
            {
                if (!AppSettings.TryParseTime(w.At, out var time))
                {
                    Log.Error($"Ignoring window with invalid time \"{w.At}\" (expected HH:mm, 24-hour)");
                    continue;
                }
                // Canonical text so reformatting a window does not reset its saved state.
                w.At = time.ToString("HH:mm");
                if (!windows.Any(p => p.At == w.At)) windows.Add(w);
            }
            parsed.Windows = windows;

            contentHash = Hash(text);
            Current = parsed;
            Log.Info($"Settings reloaded: {parsed.Windows.Count} window(s)");
            Reloaded?.Invoke(parsed);
        }

        private static string Hash(string text) =>
            Convert.ToHexString(SHA256.HashData(Encoding.UTF8.GetBytes(text)));

        public void Dispose() => watcher?.Dispose();
    }
}
