param([string]$Match = 'Nudge', [string]$Out = "$env:TEMP\shot.png")
Add-Type @"
using System;
using System.Text;
using System.Drawing;
using System.Runtime.InteropServices;
public static class Shot {
  public delegate bool EnumProc(IntPtr h, IntPtr l);
  [DllImport("user32.dll")] static extern bool EnumWindows(EnumProc cb, IntPtr l);
  [DllImport("user32.dll")] static extern int GetWindowTextLength(IntPtr h);
  [DllImport("user32.dll")] static extern int GetWindowText(IntPtr h, StringBuilder s, int n);
  [DllImport("user32.dll")] static extern bool IsWindowVisible(IntPtr h);
  [DllImport("user32.dll")] static extern bool SetForegroundWindow(IntPtr h);
  [DllImport("user32.dll")] static extern bool MoveWindow(IntPtr h, int x, int y, int w, int ht, bool repaint);
  [StructLayout(LayoutKind.Sequential)] struct R { public int L, T, Rt, B; }
  [DllImport("user32.dll")] static extern bool GetWindowRect(IntPtr h, out R r);
  public static void Rect(IntPtr h, out int l, out int t, out int w, out int ht) {
    R r; GetWindowRect(h, out r); l = r.L; t = r.T; w = r.Rt - r.L; ht = r.B - r.T;
  }

  public static string Find(string needle, out IntPtr handle) {
    IntPtr hit = IntPtr.Zero; string title = null;
    EnumWindows((h, l) => {
      int len = GetWindowTextLength(h);
      if (len > 0 && IsWindowVisible(h)) {
        var sb = new StringBuilder(len + 2);
        GetWindowText(h, sb, sb.Capacity);
        string t = sb.ToString();
        if (t.StartsWith(needle)) { hit = h; title = t; return false; }
      }
      return true;
    }, IntPtr.Zero);
    handle = hit;
    return title ?? "";
  }

  public static bool Capture(IntPtr h, string outPath) {
    SetForegroundWindow(h);
    int l, t, w, ht; Rect(h, out l, out t, out w, out ht);
    MoveWindow(h, 40, 40, w, ht, true);
    System.Threading.Thread.Sleep(700);
    Rect(h, out l, out t, out w, out ht);
    using (var b = new Bitmap(w, ht)) {
      using (var g = Graphics.FromImage(b)) g.CopyFromScreen(l, t, 0, 0, new Size(w, ht));
      b.Save(outPath);
    }
    return true;
  }
}
"@ -ReferencedAssemblies System.Drawing
$ptr = [IntPtr]::Zero
$title = [Shot]::Find($Match, [ref]$ptr)
if ($ptr -eq [IntPtr]::Zero) { "no window starting with '$Match'"; exit 1 }
[void][Shot]::Capture($ptr, $Out)
"captured [$title] -> $Out"
