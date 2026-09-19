using System.Runtime.InteropServices;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;
using System.Windows.Interop;

namespace Nudge
{
    // The tray menu, built as a real window rather than a WPF ContextMenu. A ContextMenu opened
    // without an owner sits in its own popup and never learns that the user clicked somewhere
    // else — it stays on screen until an item is picked, which is not what a menu does. A window
    // can be activated, and activation is withdrawn the moment the user turns to anything else.
    public partial class TrayMenuWindow : Window
    {
        [DllImport("user32.dll")]
        private static extern bool SetForegroundWindow(IntPtr hwnd);

        [DllImport("user32.dll")]
        private static extern IntPtr GetForegroundWindow();

        private IntPtr handle;
        private bool dismissing;

        public TrayMenuWindow() => InitializeComponent();

        public void AddRow(string label, Action action)
        {
            var row = new Button { Content = label, Style = (Style)FindResource("MenuRow") };
            row.Click += (_, _) =>
            {
                Dismiss();
                // An action that fails must not take the tray icon down with it: the menu is gone
                // either way, and the log is the only place this can ever be reported.
                try
                {
                    action();
                }
                catch (Exception ex)
                {
                    Log.Error("Tray menu action failed", ex);
                }
            };
            Rows.Children.Add(row);
        }

        public void AddDivider() =>
            Rows.Children.Add(new Border { Style = (Style)FindResource("MenuDivider") });

        // Opens with its top-left at the cursor and flips back inside the work area when the
        // cursor sits near an edge — which is the normal case for a tray icon.
        public void ShowAtCursor()
        {
            var cursor = System.Windows.Forms.Cursor.Position;
            double scale = DevicePixelScale();
            double x = cursor.X / scale;
            double y = cursor.Y / scale;

            Left = x;
            Top = y;
            Show();
            UpdateLayout();

            var area = CursorWorkArea();
            if (x + ActualWidth > area.Right) Left = Math.Max(area.Left, x - ActualWidth);
            if (y + ActualHeight > area.Bottom) Top = Math.Max(area.Top, y - ActualHeight);

            // Best effort: a background process is not allowed to steal the foreground, so this
            // can quietly do nothing. Esc and dismissal do not depend on it succeeding.
            bool foreground = SetForegroundWindow(handle) && GetForegroundWindow() == handle;
            Log.Info($"Tray menu at {Left:F0},{Top:F0} (foreground: {foreground})");
        }

        protected override void OnSourceInitialized(EventArgs e)
        {
            base.OnSourceInitialized(e);
            handle = new WindowInteropHelper(this).Handle;
        }

        // Turning to anything else — another app, the desktop, the taskbar — withdraws the
        // activation, and a menu the user has moved on from is a menu that should be gone.
        protected override void OnDeactivated(EventArgs e)
        {
            base.OnDeactivated(e);
            Dismiss();
        }

        protected override void OnPreviewKeyDown(KeyEventArgs e)
        {
            base.OnPreviewKeyDown(e);
            if (e.Key == Key.Escape)
            {
                e.Handled = true;
                Dismiss();
            }
        }

        // The only way out of this menu, whichever door was used. Closing the window raises
        // Deactivated, which asks to close it again — and a second Close while the first is still
        // in flight throws "while a Window is closing", straight out of the window procedure,
        // which takes the whole process down instead of just the menu. One guarded door.
        private void Dismiss()
        {
            if (dismissing) return;
            dismissing = true;
            try
            {
                Close();
            }
            catch (Exception ex)
            {
                Log.Error("Could not close the tray menu", ex);
            }
        }

        // WinForms reports screen rectangles in device pixels while WPF lays out in DIPs; the
        // primary display is the one rectangle both APIs describe, so the ratio between them is
        // the scale, no DPI plumbing needed. (The process is system-DPI aware.) Same trick
        // Reminders.cs uses to place the cards.
        private static double DevicePixelScale()
        {
            var primary = System.Windows.Forms.Screen.PrimaryScreen;
            if (primary != null && primary.WorkingArea.Width > 0 && SystemParameters.WorkArea.Width > 0)
                return primary.WorkingArea.Width / SystemParameters.WorkArea.Width;
            return 1.0;
        }

        private static Rect CursorWorkArea()
        {
            try
            {
                var area = System.Windows.Forms.Screen
                    .FromPoint(System.Windows.Forms.Cursor.Position).WorkingArea;
                double scale = DevicePixelScale();
                return new Rect(area.Left / scale, area.Top / scale,
                    area.Width / scale, area.Height / scale);
            }
            catch (Exception ex)
            {
                Log.Error("Could not locate the cursor's screen, using the primary one", ex);
                return SystemParameters.WorkArea;
            }
        }
    }
}
