using System.Diagnostics;
using System.Windows;
using System.Windows.Media;
using System.Windows.Media.Imaging;

namespace Nudge
{
    // One reminder card. It stays up until you act on it, because a reminder that quietly times
    // out is not a reminder. There is deliberately no close box and no "dismiss": the only way
    // off the screen is to say "Handled" or to go do the thing, so putting the card away is
    // always a claim the user made, never a shrug. The card leaving is the only signal Nudge gets.
    public partial class ReminderWindow : Window
    {
        private Action? onAck;
        private string? openTarget;

        // Putting the card away is the user saying "handled". Closes the user did not ask for —
        // a card dropped because the screen is full, or the app shutting down — clear this.
        private bool ackOnClose = true;

        public event Action? ClosedExternally;

        public ReminderWindow()
        {
            InitializeComponent();
            Glyph.Source = LoadGlyph();
        }

        public void Populate(string title, string body, Action onAck,
            string? openTarget = null, string? openName = null)
        {
            TitleText.Text = title;
            BodyText.Text = body;
            this.onAck = onAck;
            this.openTarget = openTarget;

            // "Handled" is always there — with no close box it is the only way to put the card
            // away, and it is the one that makes the user state the claim out loud.
            AckButton.Visibility = Visibility.Visible;
            OpenButton.Visibility = openTarget == null ? Visibility.Collapsed : Visibility.Visible;

            // Roughly the line length of the body text: wide enough that the buttons never
            // crowd each other, narrow enough that the sentence stays readable.
            Width = openTarget == null ? 320 : 400;
            if (openTarget != null)
            {
                OpenButtonText.Text = string.IsNullOrEmpty(openName) ? "Open" : $"Open {openName}";
                OpenButton.ToolTip = openTarget;
            }
        }

        // The card always uses the dark-taskbar (light-stroke) glyph, alongside the tray's own
        // choice — the card is a dark surface whatever the system theme is, so unlike the tray
        // glyph this one must NOT follow the theme. See CardTheme.xaml.
        private static ImageSource? LoadGlyph()
        {
            try
            {
                var info = Application.GetResourceStream(
                    new Uri("pack://application:,,,/Assets/nudge-waiting.ico"));
                if (info == null) return null;
                using var stream = info.Stream;
                using var icon = new System.Drawing.Icon(stream, new System.Drawing.Size(32, 32));
                var src = System.Windows.Interop.Imaging.CreateBitmapSourceFromHIcon(
                    icon.Handle, new Int32Rect(0, 0, 32, 32), BitmapSizeOptions.FromEmptyOptions());
                src.Freeze();
                return src;
            }
            catch
            {
                return null; // a missing glyph must never stop a reminder from appearing
            }
        }

        // "Handled" only closes the window. The ack itself happens once, in OnClosed, so this
        // route and a successful open cannot quietly drift apart.
        private void AckButton_Click(object sender, RoutedEventArgs e) => Close();

        // The primary action: launch the target and mark the window as seen in one step.
        // If the launch fails the card stays up — the user is still being reminded.
        private void OpenButton_Click(object sender, RoutedEventArgs e)
        {
            if (!TryLaunch(openTarget)) return;
            Close();
        }

        private static bool TryLaunch(string? target)
        {
            if (string.IsNullOrWhiteSpace(target)) return true;
            try
            {
                Process.Start(new ProcessStartInfo(target) { UseShellExecute = true });
                return true;
            }
            catch (Exception ex)
            {
                Log.Error($"Could not open \"{target}\", keeping the reminder up", ex);
                return false;
            }
        }

        // For closes the user did not ask for: a card dropped off a full screen, or the app
        // shutting down. Those are not a decision about the reminder.
        public void CloseWithoutAck()
        {
            ackOnClose = false;
            Close();
        }

        protected override void OnClosed(EventArgs e)
        {
            base.OnClosed(e);
            if (ackOnClose)
            {
                var handler = onAck;
                onAck = null;
                handler?.Invoke();
            }
            ClosedExternally?.Invoke();
        }
    }
}
