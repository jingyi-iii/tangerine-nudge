namespace Nudge
{
    internal static class Paths
    {
        public static readonly string Root = Path.Combine(
            Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData), "Nudge");

        public static string Settings => Path.Combine(Root, "settings.json");
        public static string State => Path.Combine(Root, "state.json");
        public static string LogFile => Path.Combine(Root, "nudge.log");

        public static void Ensure() => Directory.CreateDirectory(Root);
    }
}
