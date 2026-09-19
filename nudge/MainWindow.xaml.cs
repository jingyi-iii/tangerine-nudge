using System.Windows.Media;
using System.Windows.Media.Imaging;

namespace Nudge
{
    /// <summary>
    /// Debug gallery shown by `nudge.exe --debug-icons`: the tray glyph in both stroke sets, each
    /// rendered on the taskbar it was drawn for, at the sizes the shell actually asks for.
    /// </summary>
    public partial class MainWindow : System.Windows.Window
    {
        public MainWindow()
        {
            InitializeComponent();
            foreach (var state in new[] { "waiting", "done", "silent" })
            {
                var name = char.ToUpper(state[0]) + state[1..];
                // Dark taskbar: the plain files, drawn with light strokes.
                Fill("Dark" + name, "nudge-" + state);
                // Light taskbar: the -light files, drawn with dark strokes.
                Fill("Light" + name, "nudge-" + state + "-light");
            }
        }

        private void Fill(string prefix, string asset)
        {
            FindImage(prefix + "16").Source = LoadIconFrame(asset, 16);
            FindImage(prefix + "32").Source = LoadIconFrame(asset, 32);
            // same 16px frame shown at 3x; the Image element's NearestNeighbor keeps it crisp
            FindImage(prefix + "3x").Source = FindImage(prefix + "16").Source;
        }

        private System.Windows.Controls.Image FindImage(string name)
            => (System.Windows.Controls.Image)FindName(name)!;

        private static ImageSource LoadIconFrame(string asset, int size)
        {
            var uri = new Uri($"pack://application:,,,/Assets/{asset}.ico");
            var info = System.Windows.Application.GetResourceStream(uri)
                ?? throw new InvalidOperationException($"Missing icon asset: {asset}.ico");
            using var stream = info.Stream;
            using var icon = new System.Drawing.Icon(stream, new System.Drawing.Size(size, size));
            var src = System.Windows.Interop.Imaging.CreateBitmapSourceFromHIcon(
                icon.Handle, new System.Windows.Int32Rect(0, 0, size, size), BitmapSizeOptions.FromEmptyOptions());
            src.Freeze();
            return src;
        }
    }
}
