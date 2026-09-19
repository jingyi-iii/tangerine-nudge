using Microsoft.Win32;

namespace Nudge
{
    internal static class AutoStart
    {
        private const string RunKey = @"Software\Microsoft\Windows\CurrentVersion\Run";
        private const string ValueName = "Nudge";

        private static string? StoredPath()
        {
            try
            {
                using var rk = Registry.CurrentUser.OpenSubKey(RunKey);
                return rk?.GetValue(ValueName) as string;
            }
            catch (Exception ex)
            {
                Log.Error("Failed to read autostart registry value", ex);
                return null;
            }
        }

        public static bool IsEnabledForCurrentExe()
            => string.Equals(StoredPath()?.Trim('"'), Environment.ProcessPath, StringComparison.OrdinalIgnoreCase);

        // The registered exe no longer exists (e.g. Nudge was moved or deleted).
        public static bool IsBroken()
        {
            var stored = StoredPath()?.Trim('"');
            return stored != null && stored.Length > 0 && !File.Exists(stored);
        }

        public static bool Enable() => Write($"\"{Environment.ProcessPath}\"");

        private static bool Write(string value)
        {
            try
            {
                using var rk = Registry.CurrentUser.CreateSubKey(RunKey);
                rk.SetValue(ValueName, value);
                return true;
            }
            catch (Exception ex)
            {
                Log.Error("Failed to write autostart registry value", ex);
                return false;
            }
        }
    }
}
