// snap: keyboard-driven cursor snapping for Windows (port of the macOS tool).
// Tapping Caps sends F13 and starts a session. The Dvorak-labelled keys warp the cursor
// toward clickable UI Automation elements, Space/Enter clicks, and any other key cancels.
//
// Build (C# 5, no SDK needed):
//   C:\Windows\Microsoft.NET\Framework64\v4.0.30319\csc.exe /nologo /target:winexe /optimize+
//     /lib:C:\Windows\Microsoft.NET\Framework64\v4.0.30319\WPF
//     /r:System.Windows.Forms.dll /r:System.Drawing.dll /r:UIAutomationClient.dll
//     /r:UIAutomationTypes.dll /r:WindowsBase.dll /out:snap.exe snap.cs
//
// Usage: snap.exe            F13 hotkey loop (single instance, no console)
//        snap.exe count      print the element count and collection time, then exit
//        snap.exe show-pad   show one session for 3 s, then exit
using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Drawing;
using System.Drawing.Drawing2D;
using System.Drawing.Imaging;
using System.Drawing.Text;
using System.Runtime.InteropServices;
using System.Threading;
using System.Threading.Tasks;
using System.Windows.Automation;
using System.Windows.Forms;

static class Native
{
    public const int WM_HOTKEY = 0x0312, WM_KEYDOWN = 0x0100, WM_SYSKEYDOWN = 0x0104, WH_KEYBOARD_LL = 13;
    public const int VK_RETURN = 0x0D, VK_SHIFT = 0x10, VK_SPACE = 0x20, VK_F13 = 0x7C, VK_LSHIFT = 0xA0, VK_RSHIFT = 0xA1;
    public const uint MOD_NOREPEAT = 0x4000, GA_ROOT = 2;
    public const int WS_POPUP = unchecked((int)0x80000000);
    public const int WS_EX_TOPMOST = 0x8, WS_EX_TRANSPARENT = 0x20, WS_EX_TOOLWINDOW = 0x80, WS_EX_LAYERED = 0x80000, WS_EX_NOACTIVATE = 0x08000000;
    public const int GWL_EXSTYLE = -20, DWMWA_EXTENDED_FRAME_BOUNDS = 9, DWMWA_CLOAKED = 14;

    [StructLayout(LayoutKind.Sequential)] public struct RECT { public int Left, Top, Right, Bottom; }
    [StructLayout(LayoutKind.Sequential)] public struct POINT { public int X, Y; }
    [StructLayout(LayoutKind.Sequential)] public struct SIZE { public int Cx, Cy; }
    [StructLayout(LayoutKind.Sequential)] public struct BLENDFUNCTION { public byte BlendOp, BlendFlags, SourceConstantAlpha, AlphaFormat; }
    [StructLayout(LayoutKind.Sequential)]
    public struct BITMAPINFOHEADER
    {
        public int biSize, biWidth, biHeight;
        public short biPlanes, biBitCount;
        public int biCompression, biSizeImage, biXPelsPerMeter, biYPelsPerMeter, biClrUsed, biClrImportant;
    }
    [StructLayout(LayoutKind.Sequential)] public struct MOUSEINPUT { public int dx, dy; public uint mouseData, dwFlags, time; public IntPtr dwExtraInfo; }
    [StructLayout(LayoutKind.Sequential)] public struct INPUT { public uint type; public MOUSEINPUT mi; }

    public delegate IntPtr LowLevelProc(int code, IntPtr wParam, IntPtr lParam);
    public delegate bool EnumWindowsProc(IntPtr hwnd, IntPtr lParam);

    [DllImport("user32.dll")] public static extern bool SetProcessDpiAwarenessContext(IntPtr context);
    [DllImport("user32.dll")] public static extern bool RegisterHotKey(IntPtr hwnd, int id, uint modifiers, uint vk);
    [DllImport("user32.dll")] public static extern IntPtr SetWindowsHookEx(int idHook, LowLevelProc proc, IntPtr module, uint threadId);
    [DllImport("user32.dll")] public static extern bool UnhookWindowsHookEx(IntPtr hook);
    [DllImport("user32.dll")] public static extern IntPtr CallNextHookEx(IntPtr hook, int code, IntPtr wParam, IntPtr lParam);
    [DllImport("user32.dll")] public static extern short GetAsyncKeyState(int vk);
    [DllImport("user32.dll")] public static extern bool GetCursorPos(out POINT point);
    [DllImport("user32.dll")] public static extern bool SetCursorPos(int x, int y);
    [DllImport("user32.dll")] public static extern uint SendInput(uint count, INPUT[] inputs, int size);
    [DllImport("user32.dll")] public static extern bool EnumWindows(EnumWindowsProc proc, IntPtr lParam);
    [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr hwnd);
    [DllImport("user32.dll")] public static extern bool IsIconic(IntPtr hwnd);
    [DllImport("user32.dll")] public static extern int GetWindowLong(IntPtr hwnd, int index);
    [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr hwnd, out uint pid);
    [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr hwnd, out RECT rect);
    [DllImport("user32.dll")] public static extern IntPtr WindowFromPoint(POINT point);
    [DllImport("user32.dll")] public static extern IntPtr GetAncestor(IntPtr hwnd, uint flags);
    [DllImport("user32.dll")] public static extern bool SetWindowPos(IntPtr hwnd, IntPtr after, int x, int y, int cx, int cy, uint flags);
    [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr hwnd, int command);
    [DllImport("user32.dll")]
    public static extern bool UpdateLayeredWindow(IntPtr hwnd, IntPtr hdcDst, ref POINT dst, ref SIZE size, IntPtr hdcSrc, ref POINT src, int key, ref BLENDFUNCTION blend, int flags);
    [DllImport("user32.dll")] public static extern IntPtr MonitorFromPoint(POINT point, uint flags);
    [DllImport("shcore.dll")] public static extern int GetDpiForMonitor(IntPtr monitor, int type, out uint dpiX, out uint dpiY);
    [DllImport("dwmapi.dll")] public static extern int DwmGetWindowAttribute(IntPtr hwnd, int attribute, out int value, int size);
    [DllImport("dwmapi.dll")] public static extern int DwmGetWindowAttribute(IntPtr hwnd, int attribute, out RECT value, int size);
    [DllImport("gdi32.dll")] public static extern IntPtr CreateCompatibleDC(IntPtr hdc);
    [DllImport("gdi32.dll")] public static extern IntPtr CreateDIBSection(IntPtr hdc, ref BITMAPINFOHEADER info, uint usage, out IntPtr bits, IntPtr section, uint offset);
    [DllImport("gdi32.dll")] public static extern IntPtr SelectObject(IntPtr hdc, IntPtr obj);
    [DllImport("gdi32.dll")] public static extern bool DeleteObject(IntPtr obj);
    [DllImport("gdi32.dll")] public static extern bool DeleteDC(IntPtr hdc);
    [DllImport("kernel32.dll")] public static extern IntPtr GetModuleHandle(string name);
    [DllImport("kernel32.dll")] public static extern IntPtr GetStdHandle(int which);
    [DllImport("kernel32.dll")] public static extern bool AttachConsole(int pid);
}

// The 3x10 key grid. Windows runs the US layout while the firmware emits Dvorak, so each key is
// matched by the US virtual-key code of the character it types.
static class KeyMap
{
    static readonly string[] Rows = { "',.pyfgcrl", "aoeuidhtns", ";qjkxbmwvz" };
    public const int Columns = 10;
    public static readonly int Count = Rows.Length * Columns;

    public static char Char(int key) { return Rows[key / Columns][key % Columns]; }

    public static int IndexOfVk(int vk)
    {
        for (int key = 0; key < Count; key++)
            if (Vk(Char(key)) == vk) return key;
        return -1;
    }

    static int Vk(char ch)
    {
        switch (ch)
        {
            case '\'': return 0xDE; // VK_OEM_7
            case ',': return 0xBC;  // VK_OEM_COMMA
            case '.': return 0xBE;  // VK_OEM_PERIOD
            case ';': return 0xBA;  // VK_OEM_1
            default: return char.ToUpperInvariant(ch); // VK_A..VK_Z equal ASCII 'A'..'Z'
        }
    }
}

sealed class Targets
{
    public readonly List<Point> Elements = new List<Point>();
    public readonly List<Point> Windows = new List<Point>();
}

static class Collector
{
    const int BudgetMs = 300;
    const int MinSize = 6;

    static readonly Condition Interactive = new AndCondition(
        new PropertyCondition(AutomationElement.IsOffscreenProperty, false),
        new OrCondition(
            Type(ControlType.Button), Type(ControlType.Hyperlink), Type(ControlType.Edit),
            Type(ControlType.CheckBox), Type(ControlType.RadioButton), Type(ControlType.ComboBox),
            Type(ControlType.MenuItem), Type(ControlType.TabItem), Type(ControlType.ListItem),
            Type(ControlType.TreeItem), Type(ControlType.Slider), Type(ControlType.SplitButton),
            Type(ControlType.DataItem)));

    static PropertyCondition Type(ControlType type) { return new PropertyCondition(AutomationElement.ControlTypeProperty, type); }

    // Collects window centers and unoccluded element centers on the monitor. Each window is queried
    // on its own thread; windows that miss the budget contribute no elements instead of stalling.
    public static Targets Collect(Rectangle monitor)
    {
        var clock = Stopwatch.StartNew();
        var targets = new Targets();
        var windows = VisibleWindows(monitor);

        var windowCells = new HashSet<long>();
        foreach (var window in windows)
        {
            var center = new Point(window.Value.X + window.Value.Width / 2, window.Value.Y + window.Value.Height / 2);
            if (windowCells.Add(Cell(center))) targets.Windows.Add(center);
        }

        var queries = new Task<List<Point>>[windows.Count];
        for (int i = 0; i < windows.Count; i++)
        {
            IntPtr hwnd = windows[i].Key;
            queries[i] = Task.Factory.StartNew(() => Query(hwnd, monitor), TaskCreationOptions.LongRunning);
        }
        Task.WaitAll(queries, Math.Max(0, BudgetMs - (int)clock.ElapsedMilliseconds));

        var elementCells = new HashSet<long>();
        for (int i = 0; i < queries.Length; i++)
        {
            if (queries[i].Status != TaskStatus.RanToCompletion) continue;
            foreach (var center in queries[i].Result)
                if (OwnedBy(center, windows[i].Key) && elementCells.Add(Cell(center))) targets.Elements.Add(center);
        }
        return targets;
    }

    static List<Point> Query(IntPtr hwnd, Rectangle monitor)
    {
        var centers = new List<Point>();
        try
        {
            var root = AutomationElement.FromHandle(hwnd);
            var request = new CacheRequest { AutomationElementMode = AutomationElementMode.None };
            request.Add(AutomationElement.BoundingRectangleProperty);
            request.Add(AutomationElement.ControlTypeProperty);
            request.Add(AutomationElement.IsOffscreenProperty);
            using (request.Activate())
            {
                foreach (AutomationElement element in root.FindAll(TreeScope.Descendants, Interactive))
                {
                    object offscreen = element.GetCachedPropertyValue(AutomationElement.IsOffscreenProperty);
                    object bounds = element.GetCachedPropertyValue(AutomationElement.BoundingRectangleProperty);
                    if (offscreen is bool && (bool)offscreen || !(bounds is System.Windows.Rect)) continue;
                    var rect = (System.Windows.Rect)bounds;
                    if (rect.IsEmpty || rect.Width < MinSize || rect.Height < MinSize) continue;
                    var center = new Point((int)(rect.X + rect.Width / 2), (int)(rect.Y + rect.Height / 2));
                    if (monitor.Contains(center)) centers.Add(center);
                }
            }
        }
        catch (Exception) { } // window closed or its provider failed mid-query: it contributes no elements
        return centers;
    }

    static List<KeyValuePair<IntPtr, Rectangle>> VisibleWindows(Rectangle monitor)
    {
        var windows = new List<KeyValuePair<IntPtr, Rectangle>>();
        uint self = (uint)Process.GetCurrentProcess().Id;
        Native.EnumWindows((hwnd, _) =>
        {
            if (!Native.IsWindowVisible(hwnd) || Native.IsIconic(hwnd)) return true;
            int cloaked;
            if (Native.DwmGetWindowAttribute(hwnd, Native.DWMWA_CLOAKED, out cloaked, 4) == 0 && cloaked != 0) return true;
            const int clickThrough = Native.WS_EX_LAYERED | Native.WS_EX_TRANSPARENT;
            if ((Native.GetWindowLong(hwnd, Native.GWL_EXSTYLE) & clickThrough) == clickThrough) return true;
            uint pid;
            Native.GetWindowThreadProcessId(hwnd, out pid);
            if (pid == self) return true; // querying our own UI thread through UIA could deadlock
            Native.RECT r;
            if (Native.DwmGetWindowAttribute(hwnd, Native.DWMWA_EXTENDED_FRAME_BOUNDS, out r, Marshal.SizeOf(typeof(Native.RECT))) != 0)
                Native.GetWindowRect(hwnd, out r);
            var bounds = Rectangle.Intersect(monitor, Rectangle.FromLTRB(r.Left, r.Top, r.Right, r.Bottom));
            if (bounds.Width >= MinSize && bounds.Height >= MinSize) windows.Add(new KeyValuePair<IntPtr, Rectangle>(hwnd, bounds));
            return true;
        }, IntPtr.Zero);
        return windows;
    }

    // An element counts only if the window under its center belongs to its own top-level window.
    static bool OwnedBy(Point center, IntPtr topLevel)
    {
        var point = new Native.POINT { X = center.X, Y = center.Y };
        return Native.GetAncestor(Native.WindowFromPoint(point), Native.GA_ROOT) == topLevel;
    }

    static long Cell(Point p) { return ((long)(p.X >> 3) << 32) | (uint)(p.Y >> 3); } // 8 px grid
}

// Topmost, click-through, per-pixel-alpha window over one monitor. GDI+ draws straight into a
// premultiplied DIB that UpdateLayeredWindow presents, so no copy happens per frame.
sealed class Overlay : NativeWindow
{
    Rectangle bounds;
    IntPtr memDC, dib, previous;
    Bitmap surface;
    public Graphics Canvas { get; private set; }

    public Overlay()
    {
        CreateHandle(new CreateParams
        {
            Style = Native.WS_POPUP,
            ExStyle = Native.WS_EX_LAYERED | Native.WS_EX_TRANSPARENT | Native.WS_EX_TOPMOST | Native.WS_EX_TOOLWINDOW | Native.WS_EX_NOACTIVATE,
        });
    }

    public void Open(Rectangle monitor)
    {
        bounds = monitor;
        var header = new Native.BITMAPINFOHEADER { biSize = 40, biWidth = monitor.Width, biHeight = -monitor.Height, biPlanes = 1, biBitCount = 32 };
        IntPtr bits;
        memDC = Native.CreateCompatibleDC(IntPtr.Zero);
        dib = Native.CreateDIBSection(memDC, ref header, 0, out bits, IntPtr.Zero, 0);
        previous = Native.SelectObject(memDC, dib);
        surface = new Bitmap(monitor.Width, monitor.Height, monitor.Width * 4, PixelFormat.Format32bppPArgb, bits);
        Canvas = Graphics.FromImage(surface);
        Canvas.SmoothingMode = SmoothingMode.AntiAlias;
        Canvas.TextRenderingHint = TextRenderingHint.AntiAliasGridFit;
    }

    public void Present()
    {
        var dst = new Native.POINT { X = bounds.X, Y = bounds.Y };
        var size = new Native.SIZE { Cx = bounds.Width, Cy = bounds.Height };
        var src = new Native.POINT();
        var blend = new Native.BLENDFUNCTION { SourceConstantAlpha = 255, AlphaFormat = 1 }; // AC_SRC_ALPHA
        Native.UpdateLayeredWindow(Handle, IntPtr.Zero, ref dst, ref size, memDC, ref src, 0, ref blend, 2); // ULW_ALPHA
        Native.SetWindowPos(Handle, new IntPtr(-1), 0, 0, 0, 0, 0x0001 | 0x0002 | 0x0010 | 0x0040); // HWND_TOPMOST, NOSIZE|NOMOVE|NOACTIVATE|SHOWWINDOW
    }

    public void Close()
    {
        Native.ShowWindow(Handle, 0); // SW_HIDE
        Canvas.Dispose();
        surface.Dispose();
        Native.SelectObject(memDC, previous);
        Native.DeleteObject(dib);
        Native.DeleteDC(memDC);
        Canvas = null;
    }
}

sealed class Session
{
    static readonly Brush LabelBrush = new SolidBrush(Color.FromArgb(255, 214, 0));
    static readonly Brush DotBrush = new SolidBrush(Color.FromArgb(255, 140, 0));
    static readonly StringFormat Centered = new StringFormat { Alignment = StringAlignment.Center, LineAlignment = StringAlignment.Center };
    const float FontSize = 14f, LabelWidth = 18f, LabelHeight = 20f, LabelGap = 2f, LabelRadius = 5f, DotSize = 10f; // in 96-dpi pixels, like macOS points

    readonly SynchronizationContext ui;
    readonly Overlay overlay = new Overlay();
    readonly Native.LowLevelProc hookProc; // held in a field so the GC cannot collect it while Windows calls it
    readonly Queue<KeyValuePair<int, bool>> pending = new Queue<KeyValuePair<int, bool>>(); // keys typed before targets arrive
    IntPtr hook;
    int generation;
    bool shiftDown;
    float scale; // monitor DPI / 96: sizes stay physically constant across scaling factors
    Font labelFont;
    Rectangle monitor;
    Point cursor;
    Targets targets;

    public event Action Ended;
    public bool Active { get; private set; }

    public Session(SynchronizationContext ui)
    {
        this.ui = ui;
        hookProc = OnHook;
    }

    public void Toggle()
    {
        if (Active) Finish(false); else Start();
    }

    public void Stop() { Finish(false); }

    // The hook goes in first so no key leaks to the foreground app; targets arrive asynchronously
    // because a UI thread blocked inside a low-level hook gets the hook silently removed.
    public bool Start()
    {
        Native.POINT p;
        Native.GetCursorPos(out p);
        hook = Native.SetWindowsHookEx(Native.WH_KEYBOARD_LL, hookProc, Native.GetModuleHandle(null), 0);
        if (hook == IntPtr.Zero) return false;
        Active = true;
        cursor = new Point(p.X, p.Y);
        monitor = Screen.FromPoint(cursor).Bounds;
        uint dpiX, dpiY;
        Native.GetDpiForMonitor(Native.MonitorFromPoint(p, 2), 0, out dpiX, out dpiY); // MONITOR_DEFAULTTONEAREST, MDT_EFFECTIVE_DPI
        scale = dpiX / 96f;
        labelFont = new Font("Consolas", FontSize * scale, FontStyle.Bold, GraphicsUnit.Pixel);
        shiftDown = Native.GetAsyncKeyState(Native.VK_SHIFT) < 0;
        overlay.Open(monitor);
        Redraw();
        int session = ++generation;
        Rectangle area = monitor;
        Task.Factory.StartNew(() =>
        {
            Targets found = Collector.Collect(area);
            ui.Post(_ => OnTargets(session, found), null);
        }, TaskCreationOptions.LongRunning);
        return true;
    }

    void OnTargets(int session, Targets found)
    {
        if (!Active || session != generation) return;
        targets = found;
        Redraw();
        while (Active && pending.Count > 0)
        {
            var key = pending.Dequeue();
            OnKey(key.Key, key.Value);
        }
    }

    IntPtr OnHook(int code, IntPtr wParam, IntPtr lParam)
    {
        if (code < 0 || !Active) return Native.CallNextHookEx(IntPtr.Zero, code, wParam, lParam);
        int vk = Marshal.ReadInt32(lParam); // KBDLLHOOKSTRUCT.vkCode
        int message = wParam.ToInt32();
        bool down = message == Native.WM_KEYDOWN || message == Native.WM_SYSKEYDOWN;
        if (vk == Native.VK_LSHIFT || vk == Native.VK_RSHIFT || vk == Native.VK_SHIFT) shiftDown = down;
        else if (down)
        {
            bool shift = shiftDown;
            ui.Post(_ => OnKey(vk, shift), null); // act after returning: Windows drops slow low-level hooks
        }
        return new IntPtr(1); // swallow every key while the session is active
    }

    void OnKey(int vk, bool shift)
    {
        if (!Active) return;
        if (targets == null)
        {
            pending.Enqueue(new KeyValuePair<int, bool>(vk, shift));
            return;
        }
        if (vk == Native.VK_SPACE || vk == Native.VK_RETURN)
        {
            Finish(true);
            return;
        }
        int key = KeyMap.IndexOfVk(vk);
        if (key < 0)
        {
            Finish(false);
            return;
        }
        Point? landing = Landing(key);
        if (landing == null) return;
        cursor = landing.Value;
        Native.SetCursorPos(cursor.X, cursor.Y);
        if (shift) Finish(true); else Redraw();
    }

    void Finish(bool click)
    {
        if (!Active) return;
        Active = false;
        Native.UnhookWindowsHookEx(hook);
        overlay.Close();
        labelFont.Dispose();
        targets = null;
        pending.Clear();
        if (click) Click();
        if (Ended != null) Ended();
    }

    // Key (r, c) aims at cursor + ((c-4.5)/4.5 * 0.45 W, (r-1) * 0.35 H). The landing is the element
    // center, else the window center, within the aim's cone that lies closest to the aim point.
    Point? Landing(int key)
    {
        double dx = (key % KeyMap.Columns - 4.5) / 4.5, dy = key / KeyMap.Columns - 1;
        double ox = dx * 0.45 * monitor.Width, oy = dy * 0.35 * monitor.Height;
        return Nearest(targets.Elements, ox, oy) ?? Nearest(targets.Windows, ox, oy);
    }

    Point? Nearest(List<Point> candidates, double ox, double oy)
    {
        double length = Math.Sqrt(ox * ox + oy * oy), gx = cursor.X + ox, gy = cursor.Y + oy, best = double.MaxValue;
        Point? nearest = null;
        foreach (var p in candidates)
        {
            double vx = p.X - cursor.X, vy = p.Y - cursor.Y, distance = Math.Sqrt(vx * vx + vy * vy);
            if (distance <= 4 || (vx * ox + vy * oy) / (distance * length) <= 0.64) continue;
            double toGoal = (p.X - gx) * (p.X - gx) + (p.Y - gy) * (p.Y - gy);
            if (toGoal < best)
            {
                best = toGoal;
                nearest = p;
            }
        }
        return nearest;
    }

    void Redraw()
    {
        Graphics g = overlay.Canvas;
        g.Clear(Color.Transparent);
        if (targets != null)
        {
            var labels = new Dictionary<Point, List<char>>(); // keys sharing a landing sit side by side
            for (int key = 0; key < KeyMap.Count; key++)
            {
                Point? at = Landing(key);
                if (at == null) continue;
                List<char> chars;
                if (!labels.TryGetValue(at.Value, out chars)) labels.Add(at.Value, chars = new List<char>());
                chars.Add(KeyMap.Char(key));
            }
            foreach (var label in labels) DrawLabels(g, label.Key, label.Value);
        }
        float dot = DotSize * scale;
        g.FillEllipse(DotBrush, cursor.X - monitor.X - dot / 2, cursor.Y - monitor.Y - dot / 2, dot, dot);
        overlay.Present();
    }

    void DrawLabels(Graphics g, Point at, List<char> chars)
    {
        float w = LabelWidth * scale, h = LabelHeight * scale, gap = LabelGap * scale;
        float width = chars.Count * w + (chars.Count - 1) * gap;
        float x = Clamp(at.X - monitor.X - width / 2, 0, monitor.Width - width);
        float y = Clamp(at.Y - monitor.Y - h / 2, 0, monitor.Height - h);
        foreach (char ch in chars)
        {
            var box = new RectangleF(x, y, w, h);
            using (var path = RoundedRect(box, LabelRadius * scale)) g.FillPath(LabelBrush, path);
            g.DrawString(ch.ToString(), labelFont, Brushes.Black, box, Centered);
            x += w + gap;
        }
    }

    static float Clamp(float value, float min, float max) { return Math.Max(min, Math.Min(max, value)); }

    static GraphicsPath RoundedRect(RectangleF r, float radius)
    {
        float d = radius * 2;
        var path = new GraphicsPath();
        path.AddArc(r.X, r.Y, d, d, 180, 90);
        path.AddArc(r.Right - d, r.Y, d, d, 270, 90);
        path.AddArc(r.Right - d, r.Bottom - d, d, d, 0, 90);
        path.AddArc(r.X, r.Bottom - d, d, d, 90, 90);
        path.CloseFigure();
        return path;
    }

    static void Click()
    {
        var inputs = new[] { MouseInput(0x0002), MouseInput(0x0004) }; // MOUSEEVENTF_LEFTDOWN, MOUSEEVENTF_LEFTUP
        Native.SendInput((uint)inputs.Length, inputs, Marshal.SizeOf(typeof(Native.INPUT)));
    }

    static Native.INPUT MouseInput(uint flags)
    {
        return new Native.INPUT { type = 0, mi = new Native.MOUSEINPUT { dwFlags = flags } }; // INPUT_MOUSE at the current cursor
    }
}

// Message-only window that receives WM_HOTKEY.
sealed class HotkeyWindow : NativeWindow
{
    readonly Action pressed;

    public HotkeyWindow(Action pressed)
    {
        this.pressed = pressed;
        CreateHandle(new CreateParams { Parent = new IntPtr(-3) }); // HWND_MESSAGE
    }

    protected override void WndProc(ref Message m)
    {
        if (m.Msg == Native.WM_HOTKEY) pressed();
        base.WndProc(ref m);
    }
}

static class Program
{
    [STAThread]
    static int Main(string[] args)
    {
        Native.SetProcessDpiAwarenessContext(new IntPtr(-4)); // PER_MONITOR_AWARE_V2: UIA, cursor and windows share physical pixels
        string mode = args.Length > 0 ? args[0] : "";
        if (mode == "") return RunHotkeyLoop();
        if (mode == "count") return RunCount();
        if (mode == "show-pad") return RunShowPad();
        UseConsole();
        Console.Error.WriteLine("usage: snap.exe [count|show-pad]");
        return 2;
    }

    static int RunHotkeyLoop()
    {
        bool first;
        using (new Mutex(true, @"Local\nuphy-tools.snap", out first))
        {
            if (!first) return 0;
            var session = new Session(InstallUiContext());
            var hotkey = new HotkeyWindow(session.Toggle);
            if (!Native.RegisterHotKey(hotkey.Handle, 1, Native.MOD_NOREPEAT, Native.VK_F13))
            {
                MessageBox.Show("F13 is already registered as a hotkey by another program.", "snap", MessageBoxButtons.OK, MessageBoxIcon.Error);
                return 1;
            }
            Task.Factory.StartNew(() => Collector.Collect(Screen.PrimaryScreen.Bounds)); // warm UIA so the first session is not cold
            Application.Run();
            return 0;
        }
    }

    static int RunShowPad()
    {
        var session = new Session(InstallUiContext());
        session.Ended += Application.ExitThread;
        if (!session.Start()) return 1;
        var timer = new System.Windows.Forms.Timer { Interval = 3000 };
        timer.Tick += delegate { session.Stop(); };
        timer.Start();
        Application.Run();
        return 0;
    }

    static int RunCount()
    {
        UseConsole();
        var clock = Stopwatch.StartNew();
        Native.POINT p;
        Native.GetCursorPos(out p);
        Targets targets = Collector.Collect(Screen.FromPoint(new Point(p.X, p.Y)).Bounds);
        Console.WriteLine("{0} elements in {1} ms", targets.Elements.Count, clock.ElapsedMilliseconds);
        return 0;
    }

    static SynchronizationContext InstallUiContext()
    {
        var context = new WindowsFormsSynchronizationContext();
        SynchronizationContext.SetSynchronizationContext(context);
        return context;
    }

    // A winexe has no console; borrow the parent's unless stdout is already redirected to a pipe or file.
    static void UseConsole()
    {
        if (Native.GetStdHandle(-11) == IntPtr.Zero) Native.AttachConsole(-1); // STD_OUTPUT_HANDLE, ATTACH_PARENT_PROCESS
    }
}
