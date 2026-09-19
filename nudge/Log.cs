namespace Nudge
{
    internal static class Log
    {
        private static readonly object Gate = new();
        private const long MaxBytes = 512 * 1024;

        public static void Info(string message) => Write("INFO", message);

        public static void Error(string message, Exception? ex = null)
            => Write("ERROR", ex == null ? message : $"{message}: {ex.GetType().Name}: {ex.Message}\n{ex.StackTrace}");

        private static void Write(string level, string message)
        {
            try
            {
                lock (Gate)
                {
                    var file = Paths.LogFile;
                    if (File.Exists(file) && new FileInfo(file).Length > MaxBytes)
                        File.Move(file, file + ".old", true);
                    File.AppendAllText(file,
                        $"{DateTime.Now:yyyy-MM-dd HH:mm:ss} {level} {message}{Environment.NewLine}");
                }
            }
            catch
            {
                // Logging must never crash the app.
            }
        }
    }
}
