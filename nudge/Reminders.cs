using System.Windows;
using System.Windows.Media.Animation;

namespace Nudge
{
    // Nudge draws its own reminder cards. Windows toast banners are unreliable exactly where
    // this app is needed most: they are suppressed over full-screen apps, and the ticket check
    // is meant to interrupt someone who is buried in one.
    internal sealed class Reminders
    {
        private const double ScreenMargin = 12;
        private const double Gap = 10;

        // Cards rest against the bottom-right corner and rise into place, so a new reminder
        // bubbles up from below and pushes the older ones further up the column.
        private static readonly TimeSpan RiseDuration = TimeSpan.FromMilliseconds(220);
        private const double RiseFrom = 18;

        private readonly List<ReminderWindow> open = new();

        // Where the stack lives. Refreshed whenever a reminder fires, so cards land on the screen
        // the user is working on rather than always on the primary one.
        private Rect anchor = SystemParameters.WorkArea;

        public void Show(WindowItem window, int attempt, Action onAck)
        {
            string title, body;
            if (attempt == 1)
            {
                title = "Ticket check";
                body = $"{window.Display} ({window.At}) — open the ticket system and take one look.";
            }
            else
            {
                title = $"{window.Display}: still unchecked";
                body = $"Last reminder for the {window.At} window today. After this, Nudge stays silent until the next one.";
            }

            anchor = TargetWorkArea();

            var card = new ReminderWindow();
            bool hasOpen = !string.IsNullOrWhiteSpace(window.Open);
            card.Populate(title, body, onAck,
                hasOpen ? window.Open : null,
                hasOpen ? window.OpenName : null);
            card.ClosedExternally += () => Remove(card);

            // Position before showing: ActualWidth is still 0 until the first layout pass, and
            // placing from that would park the card mostly off the right edge.
            open.Add(card);
            Arrange(animate: true);
            FadeIn(card);
            card.Show();

            // A second pass with the real measured height. That is a correction, not a bubble, so
            // it lands instantly rather than animating a second time.
            card.ContentRendered += (_, _) =>
            {
                Arrange(animate: false);
                Log.Info($"Reminder card at {card.Left:F0},{card.Top:F0} {card.ActualWidth:F0}x{card.ActualHeight:F0}");
            };
        }

        private void Remove(ReminderWindow card)
        {
            // No unsubscription needed: the handler hangs off the card itself, so dropping the
            // card from `open` makes both collectable.
            open.Remove(card);
            Arrange(animate: true);
        }

        // Cards stack upwards from the bottom-right corner of the anchor screen: the newest
        // reminder owns the corner and every earlier one sits above it. A card arriving pushes
        // the column up; a card leaving lets it settle back down.
        private void Arrange(bool animate)
        {
            var area = anchor;

            // The reminder that just fired is the one worth seeing, so when the stack outgrows
            // the screen the oldest cards are dropped instead of pushed past the top edge.
            while (open.Count > 1 && StackHeight() > area.Height - 2 * ScreenMargin)
            {
                Log.Info("No room left on screen, dropping the oldest reminder card");
                open[0].CloseWithoutAck(); // ClosedExternally removes it and re-enters Arrange
            }

            double bottom = area.Bottom - ScreenMargin;
            for (int i = open.Count - 1; i >= 0; i--)
            {
                var card = open[i];
                double height = CardHeight(card);
                MoveTo(card,
                    area.Right - Fallback(card.ActualWidth, card.Width) - ScreenMargin,
                    bottom - height, animate);
                bottom -= height + Gap;
            }
        }

        // An animation outranks a local value, so the resting position is assigned first and the
        // animation is told to stop at the end: a card is never left parked mid-flight.
        private static void MoveTo(ReminderWindow card, double left, double top, bool animate)
        {
            double from = card.Top;
            card.Left = left;
            card.Top = top;
            if (!animate) return;

            // A card with no position yet has just arrived: it bubbles up from below instead of
            // sliding in from wherever the last one happened to be.
            if (double.IsNaN(from) || double.IsInfinity(from)) from = top + RiseFrom;
            if (Math.Abs(from - top) < 1) return;

            card.BeginAnimation(Window.TopProperty, new DoubleAnimation(from, top, RiseDuration)
            {
                FillBehavior = FillBehavior.Stop,
                EasingFunction = new CubicEase { EasingMode = EasingMode.EaseOut },
            });
        }

        // Resting opacity is 1; the animation plays 0 -> 1 and then hands the value back.
        private static void FadeIn(ReminderWindow card)
        {
            card.Opacity = 1;
            card.BeginAnimation(UIElement.OpacityProperty,
                new DoubleAnimation(0, 1, RiseDuration) { FillBehavior = FillBehavior.Stop });
        }

        private double StackHeight()
        {
            double total = 0;
            foreach (var card in open) total += CardHeight(card) + Gap;
            return total - Gap;
        }

        // Until the first layout pass ActualHeight is 0, which would let an overfull stack slip
        // past the bottom edge unpruned.
        private static double CardHeight(ReminderWindow card) => Fallback(card.ActualHeight, 140);

        private static double Fallback(double measured, double declared) =>
            measured > 1 && !double.IsNaN(measured) && !double.IsInfinity(measured) ? measured : declared;

        // The reminder belongs on the screen the user is actually looking at. SystemParameters
        // only ever reports the primary display, so ask the cursor where it is instead.
        // WinForms reports screen rectangles in device pixels while WPF lays out in DIPs; the
        // primary display is the one rectangle both APIs describe, so the ratio between them
        // gives the scale without any DPI plumbing. (The process is system-DPI aware, so one
        // ratio holds for every monitor.)
        private static Rect TargetWorkArea()
        {
            try
            {
                var area = System.Windows.Forms.Screen
                    .FromPoint(System.Windows.Forms.Cursor.Position).WorkingArea;
                var primary = System.Windows.Forms.Screen.PrimaryScreen;
                double scale = 1.0;
                if (primary != null && primary.WorkingArea.Width > 0
                    && SystemParameters.WorkArea.Width > 0)
                {
                    scale = primary.WorkingArea.Width / SystemParameters.WorkArea.Width;
                }
                return new Rect(area.Left / scale, area.Top / scale,
                    area.Width / scale, area.Height / scale);
            }
            catch (Exception ex)
            {
                Log.Error("Could not locate the cursor's screen, using the primary one", ex);
                return SystemParameters.WorkArea;
            }
        }

        public void CloseAll()
        {
            // Shutdown is not the user saying "seen".
            foreach (var card in open.ToList()) card.CloseWithoutAck();
            open.Clear();
        }
    }
}
