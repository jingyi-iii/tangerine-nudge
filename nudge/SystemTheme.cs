using Microsoft.Win32;

namespace Nudge
{
    /// <summary>
    /// The one thing Nudge asks the OS: what does the taskbar look like right now.
    ///
    /// The tray glyph is the only thing Nudge ever draws onto a surface it does not own, so it is
    /// the only thing that has to follow the theme. The reminder card and the tray menu carry
    /// Nudge's own dark skin and deliberately look the same in either theme.
    /// </summary>
    internal static class SystemTheme
    {
        private const string PersonalizeKey =
            @"Software\Microsoft\Windows\CurrentVersion\Themes\Personalize";

        // SystemUsesLightTheme, not AppsUseLightTheme: the former is the shell's own theme, and
        // the shell is what paints the taskbar. Set under Settings > Personalization > Colors.
        public static bool TaskbarIsLight()
        {
            try
            {
                using var key = Registry.CurrentUser.OpenSubKey(PersonalizeKey);
                if (key?.GetValue("SystemUsesLightTheme") is int v) return v != 0;
            }
            catch (Exception ex)
            {
                Log.Error("Could not read the system theme from the registry", ex);
            }

            // Unreadable: assume light. Windows ships the light theme out of the box, so a machine
            // where we cannot tell is more likely light than dark — and on a light taskbar the
            // dark-stroke glyph is the one that is actually visible.
            return true;
        }
    }
}
