param(
    [switch]$ResetPosition,
    [switch]$TestMode
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase, System.Xaml

Add-Type -TypeDefinition @'
using System;
using System.Diagnostics;
using System.Runtime.InteropServices;

public static class GlobalKeyboardCounter
{
    public static event Action KeyPressed;

    private const int WH_KEYBOARD_LL = 13;
    private const int WM_KEYDOWN = 0x0100;
    private const int WM_SYSKEYDOWN = 0x0104;
    private const int LLKHF_INJECTED = 0x10;
    private static readonly LowLevelKeyboardProc Proc = HookCallback;
    private static IntPtr hookId = IntPtr.Zero;

    public static void Start()
    {
        if (hookId != IntPtr.Zero) return;
        using (Process process = Process.GetCurrentProcess())
        using (ProcessModule module = process.MainModule)
        {
            hookId = SetWindowsHookEx(WH_KEYBOARD_LL, Proc,
                GetModuleHandle(module.ModuleName), 0);
        }
        if (hookId == IntPtr.Zero)
            throw new System.ComponentModel.Win32Exception(Marshal.GetLastWin32Error());
    }

    public static void Stop()
    {
        if (hookId == IntPtr.Zero) return;
        UnhookWindowsHookEx(hookId);
        hookId = IntPtr.Zero;
    }

    private static bool IsTypingKey(int vk)
    {
        if (vk >= 0x30 && vk <= 0x5A) return true; // 0-9, A-Z
        if (vk >= 0x60 && vk <= 0x6F) return true; // numpad
        if (vk >= 0xBA && vk <= 0xE2) return true; // OEM punctuation
        switch (vk)
        {
            case 0x08: // Backspace
            case 0x09: // Tab
            case 0x0D: // Enter
            case 0x20: // Space
            case 0x2E: // Delete
                return true;
            default:
                return false;
        }
    }

    private static IntPtr HookCallback(int nCode, IntPtr wParam, IntPtr lParam)
    {
        if (nCode >= 0 && (wParam == (IntPtr)WM_KEYDOWN || wParam == (IntPtr)WM_SYSKEYDOWN))
        {
            KBDLLHOOKSTRUCT data = Marshal.PtrToStructure<KBDLLHOOKSTRUCT>(lParam);
            if ((data.flags & LLKHF_INJECTED) == 0 && IsTypingKey((int)data.vkCode))
            {
                Action handler = KeyPressed;
                if (handler != null) handler();
            }
        }
        return CallNextHookEx(hookId, nCode, wParam, lParam);
    }

    private delegate IntPtr LowLevelKeyboardProc(int nCode, IntPtr wParam, IntPtr lParam);

    [StructLayout(LayoutKind.Sequential)]
    private struct KBDLLHOOKSTRUCT
    {
        public uint vkCode;
        public uint scanCode;
        public int flags;
        public uint time;
        public UIntPtr dwExtraInfo;
    }

    [DllImport("user32.dll", SetLastError = true)]
    private static extern IntPtr SetWindowsHookEx(int idHook, LowLevelKeyboardProc callback, IntPtr module, uint threadId);

    [DllImport("user32.dll", SetLastError = true)]
    private static extern bool UnhookWindowsHookEx(IntPtr hook);

    [DllImport("user32.dll")]
    private static extern IntPtr CallNextHookEx(IntPtr hook, int nCode, IntPtr wParam, IntPtr lParam);

    [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
    private static extern IntPtr GetModuleHandle(string moduleName);
}
'@

$wpfCompilerReferences = @(
    [System.Windows.Media.Imaging.BitmapSource].Assembly.Location,
    [System.Windows.DependencyObject].Assembly.Location,
    [System.Windows.Markup.IUriContext].Assembly.Location
)
Add-Type -ReferencedAssemblies $wpfCompilerReferences -TypeDefinition @'
using System;
using System.IO;
using System.Windows;
using System.Windows.Media;
using System.Windows.Media.Imaging;

public static class PetImageProcessor
{
    public static void Process(string inputPath, string outputPath, bool removeBackground, int canvasSize)
    {
        BitmapImage source = new BitmapImage();
        source.BeginInit();
        source.CacheOption = BitmapCacheOption.OnLoad;
        source.CreateOptions = BitmapCreateOptions.IgnoreImageCache;
        source.UriSource = new Uri(inputPath, UriKind.Absolute);
        source.EndInit();
        source.Freeze();

        int padding = Math.Max(12, canvasSize / 24);
        double scale = Math.Min(
            (double)(canvasSize - padding * 2) / source.PixelWidth,
            (double)(canvasSize - padding * 2) / source.PixelHeight);
        int width = Math.Max(1, (int)Math.Round(source.PixelWidth * scale));
        int height = Math.Max(1, (int)Math.Round(source.PixelHeight * scale));

        DrawingVisual visual = new DrawingVisual();
        using (DrawingContext context = visual.RenderOpen())
        {
            context.DrawImage(source, new Rect(0, 0, width, height));
        }
        RenderTargetBitmap rendered = new RenderTargetBitmap(width, height, 96, 96, PixelFormats.Pbgra32);
        rendered.Render(visual);
        FormatConvertedBitmap converted = new FormatConvertedBitmap(rendered, PixelFormats.Bgra32, null, 0);

        int stride = width * 4;
        byte[] pixels = new byte[stride * height];
        converted.CopyPixels(pixels, stride, 0);
        if (removeBackground) RemoveEdgeConnectedBackground(pixels, width, height, stride);

        int canvasStride = canvasSize * 4;
        byte[] canvas = new byte[canvasStride * canvasSize];
        int offsetX = (canvasSize - width) / 2;
        int offsetY = canvasSize - padding - height;
        if (offsetY < 0) offsetY = 0;
        for (int y = 0; y < height; y++)
        {
            Buffer.BlockCopy(pixels, y * stride, canvas, (offsetY + y) * canvasStride + offsetX * 4, stride);
        }

        BitmapSource result = BitmapSource.Create(
            canvasSize, canvasSize, 96, 96, PixelFormats.Bgra32, null, canvas, canvasStride);
        PngBitmapEncoder encoder = new PngBitmapEncoder();
        encoder.Frames.Add(BitmapFrame.Create(result));
        using (FileStream stream = new FileStream(outputPath, FileMode.Create, FileAccess.Write, FileShare.None))
        {
            encoder.Save(stream);
        }
    }

    private static void RemoveEdgeConnectedBackground(byte[] pixels, int width, int height, int stride)
    {
        int[][] corners = new int[4][];
        corners[0] = SampleCorner(pixels, width, height, stride, 0, 0);
        corners[1] = SampleCorner(pixels, width, height, stride, width - 1, 0);
        corners[2] = SampleCorner(pixels, width, height, stride, 0, height - 1);
        corners[3] = SampleCorner(pixels, width, height, stride, width - 1, height - 1);

        bool[] background = new bool[width * height];
        int[] queue = new int[width * height];
        int head = 0;
        int tail = 0;

        for (int x = 0; x < width; x++)
        {
            TryEnqueue(x, 0, pixels, width, height, stride, corners, background, queue, ref tail);
            TryEnqueue(x, height - 1, pixels, width, height, stride, corners, background, queue, ref tail);
        }
        for (int y = 1; y < height - 1; y++)
        {
            TryEnqueue(0, y, pixels, width, height, stride, corners, background, queue, ref tail);
            TryEnqueue(width - 1, y, pixels, width, height, stride, corners, background, queue, ref tail);
        }

        while (head < tail)
        {
            int position = queue[head++];
            int x = position % width;
            int y = position / width;
            if (x > 0) TryEnqueue(x - 1, y, pixels, width, height, stride, corners, background, queue, ref tail);
            if (x + 1 < width) TryEnqueue(x + 1, y, pixels, width, height, stride, corners, background, queue, ref tail);
            if (y > 0) TryEnqueue(x, y - 1, pixels, width, height, stride, corners, background, queue, ref tail);
            if (y + 1 < height) TryEnqueue(x, y + 1, pixels, width, height, stride, corners, background, queue, ref tail);
        }

        for (int i = 0; i < background.Length; i++)
        {
            if (background[i])
            {
                pixels[i * 4] = 0;
                pixels[i * 4 + 1] = 0;
                pixels[i * 4 + 2] = 0;
                pixels[i * 4 + 3] = 0;
            }
        }

        // Soften only the immediate boundary to reduce light-colored halos.
        byte[] alpha = new byte[background.Length];
        for (int i = 0; i < background.Length; i++) alpha[i] = pixels[i * 4 + 3];
        for (int y = 1; y < height - 1; y++)
        {
            for (int x = 1; x < width - 1; x++)
            {
                int position = y * width + x;
                if (background[position]) continue;
                bool edge = background[position - 1] || background[position + 1] ||
                            background[position - width] || background[position + width];
                if (!edge) continue;
                int colorDistance = NearestCornerDistance(pixels, position * 4, corners);
                if (colorDistance < 105)
                {
                    double factor = Math.Max(0.18, Math.Min(1.0, (colorDistance - 45) / 60.0));
                    alpha[position] = (byte)(alpha[position] * factor);
                }
            }
        }
        for (int i = 0; i < alpha.Length; i++) pixels[i * 4 + 3] = alpha[i];
    }

    private static int[] SampleCorner(byte[] pixels, int width, int height, int stride, int cornerX, int cornerY)
    {
        int radius = Math.Max(1, Math.Min(width, height) / 80);
        long b = 0, g = 0, r = 0, count = 0;
        int startX = cornerX == 0 ? 0 : Math.Max(0, width - radius - 1);
        int startY = cornerY == 0 ? 0 : Math.Max(0, height - radius - 1);
        int endX = Math.Min(width, startX + radius + 1);
        int endY = Math.Min(height, startY + radius + 1);
        for (int y = startY; y < endY; y++)
        {
            for (int x = startX; x < endX; x++)
            {
                int index = y * stride + x * 4;
                b += pixels[index]; g += pixels[index + 1]; r += pixels[index + 2]; count++;
            }
        }
        return new int[] { (int)(b / count), (int)(g / count), (int)(r / count) };
    }

    private static void TryEnqueue(int x, int y, byte[] pixels, int width, int height, int stride,
        int[][] corners, bool[] background, int[] queue, ref int tail)
    {
        int position = y * width + x;
        if (background[position]) return;
        int index = y * stride + x * 4;
        if (pixels[index + 3] < 12 || NearestCornerDistance(pixels, index, corners) <= 82)
        {
            background[position] = true;
            queue[tail++] = position;
        }
    }

    private static int NearestCornerDistance(byte[] pixels, int index, int[][] corners)
    {
        int nearestSquared = Int32.MaxValue;
        for (int i = 0; i < corners.Length; i++)
        {
            int db = pixels[index] - corners[i][0];
            int dg = pixels[index + 1] - corners[i][1];
            int dr = pixels[index + 2] - corners[i][2];
            int squared = db * db + dg * dg + dr * dr;
            if (squared < nearestSquared) nearestSquared = squared;
        }
        return (int)Math.Sqrt(nearestSquared);
    }
}
'@

$scriptRoot = if ($env:TYPING_PET_ROOT) {
    $env:TYPING_PET_ROOT.TrimEnd('\')
} else {
    Split-Path -Parent $MyInvocation.MyCommand.Path
}
$assetPath = Join-Path $scriptRoot 'assets\pet.png'
$dataDirectory = if ($TestMode) { $scriptRoot } else { Join-Path $env:LOCALAPPDATA 'TypingPet' }
$dataPath = if ($TestMode) {
    Join-Path $scriptRoot '.typingpet-test.json'
} else {
    Join-Path $dataDirectory 'stats.json'
}
$today = [DateTime]::Today.ToString('yyyy-MM-dd')

function New-DefaultStats {
    [pscustomobject]@{
        date = $today
        todayCount = [long]0
        totalCount = [long]0
        lastCelebrated = [long]0
        customImagePath = $null
        left = $null
        top = $null
    }
}

function Read-Stats {
    if (-not (Test-Path -LiteralPath $dataPath)) { return New-DefaultStats }
    try {
        $loaded = Get-Content -LiteralPath $dataPath -Raw -Encoding UTF8 | ConvertFrom-Json
        $stats = New-DefaultStats
        if ($null -ne $loaded.PSObject.Properties['totalCount']) { $stats.totalCount = [long]$loaded.totalCount }
        if ($null -ne $loaded.PSObject.Properties['todayCount']) { $stats.todayCount = [long]$loaded.todayCount }
        if ($null -ne $loaded.PSObject.Properties['date']) { $stats.date = [string]$loaded.date }
        if ($null -ne $loaded.PSObject.Properties['left'] -and $null -ne $loaded.left) { $stats.left = [double]$loaded.left }
        if ($null -ne $loaded.PSObject.Properties['top'] -and $null -ne $loaded.top) { $stats.top = [double]$loaded.top }
        if ($null -ne $loaded.PSObject.Properties['lastCelebrated']) {
            $stats.lastCelebrated = [long]$loaded.lastCelebrated
        } else {
            # Existing users should only celebrate milestones reached after this feature was installed.
            $stats.lastCelebrated = [long][Math]::Floor($stats.totalCount / 10000)
        }
        if ($null -ne $loaded.PSObject.Properties['customImagePath'] -and $null -ne $loaded.customImagePath) {
            $stats.customImagePath = [string]$loaded.customImagePath
        }
        if ($stats.date -ne $today) {
            $stats.date = $today
            $stats.todayCount = 0
        }
        return $stats
    }
    catch {
        # Corrupt data never prevents the pet from starting. Preserve the bad file for diagnosis.
        return New-DefaultStats
    }
}

$stats = Read-Stats
$script:isDirty = $false
$script:lastSaved = [DateTime]::MinValue
$script:celebrationWindow = $null
$script:celebrationTimer = $null

function Save-Stats {
    if (-not (Test-Path -LiteralPath $dataDirectory)) {
        New-Item -ItemType Directory -Path $dataDirectory | Out-Null
    }
    $payload = [ordered]@{
        date = $stats.date
        todayCount = [long]$stats.todayCount
        totalCount = [long]$stats.totalCount
        lastCelebrated = [long]$stats.lastCelebrated
        customImagePath = $stats.customImagePath
        left = if ([double]::IsNaN($window.Left)) { $null } else { [Math]::Round($window.Left, 1) }
        top = if ([double]::IsNaN($window.Top)) { $null } else { [Math]::Round($window.Top, 1) }
    }
    $temporaryPath = "$dataPath.tmp"
    $payload | ConvertTo-Json | Set-Content -LiteralPath $temporaryPath -Encoding UTF8
    Move-Item -LiteralPath $temporaryPath -Destination $dataPath -Force
    $script:isDirty = $false
    $script:lastSaved = [DateTime]::Now
}

function Update-Day {
    $currentDate = [DateTime]::Today.ToString('yyyy-MM-dd')
    if ($stats.date -ne $currentDate) {
        $stats.date = $currentDate
        $stats.todayCount = [long]0
        $script:isDirty = $true
        Update-Display
        Save-Stats
    }
}

function Format-Count([long]$value) {
    return $value.ToString('N0')
}

function Update-Display {
    $todayText.Text = "今日  $(Format-Count $stats.todayCount)"
    $totalText.Text = "累计  $(Format-Count $stats.totalCount)"
}

function Get-LoadedBitmap([string]$path) {
    $loadedBitmap = [System.Windows.Media.Imaging.BitmapImage]::new()
    $loadedBitmap.BeginInit()
    $loadedBitmap.CacheOption = [System.Windows.Media.Imaging.BitmapCacheOption]::OnLoad
    $loadedBitmap.CreateOptions = [System.Windows.Media.Imaging.BitmapCreateOptions]::IgnoreImageCache
    $loadedBitmap.UriSource = [Uri]::new($path)
    $loadedBitmap.EndInit()
    $loadedBitmap.Freeze()
    return $loadedBitmap
}

function Save-CustomPetImage([string]$sourcePath, [bool]$removeBackground) {
    if (-not (Test-Path -LiteralPath $dataDirectory)) {
        New-Item -ItemType Directory -Path $dataDirectory | Out-Null
    }
    $version = [DateTime]::Now.ToString('yyyyMMdd-HHmmss-fff') + '-' + [Guid]::NewGuid().ToString('N').Substring(0, 8)
    $destinationPath = Join-Path $dataDirectory "custom-pet-$version.png"
    [PetImageProcessor]::Process($sourcePath, $destinationPath, $removeBackground, 512)
    return $destinationPath
}

function Remove-SavedCustomImage([string]$pathToRemove) {
    if ([string]::IsNullOrWhiteSpace($pathToRemove)) { return }
    try {
        $fullPath = [System.IO.Path]::GetFullPath($pathToRemove)
        $customRoot = [System.IO.Path]::GetFullPath($dataDirectory).TrimEnd('\') + '\'
        $fileName = [System.IO.Path]::GetFileName($fullPath)
        if ($fullPath.StartsWith($customRoot, [StringComparison]::OrdinalIgnoreCase) -and
            $fileName.StartsWith('custom-pet', [StringComparison]::OrdinalIgnoreCase) -and
            $fileName.EndsWith('.png', [StringComparison]::OrdinalIgnoreCase) -and
            [System.IO.File]::Exists($fullPath)) {
            [System.IO.File]::Delete($fullPath)
        }
    }
    catch {
        # A stale custom image is harmless; never fail a successful character change because cleanup was blocked.
    }
}

function Show-Celebration([long]$tenThousands) {
    if ($null -ne $script:celebrationWindow) {
        try { $script:celebrationWindow.Close() } catch { }
    }

    $script:celebrationWindow = [System.Windows.Window]::new()
    $celebration = $script:celebrationWindow
    $celebration.Title = '打字里程碑'
    $celebration.Width = 520
    $celebration.Height = 330
    $celebration.WindowStyle = [System.Windows.WindowStyle]::None
    $celebration.AllowsTransparency = $true
    $celebration.Background = [System.Windows.Media.Brushes]::Transparent
    $celebration.Topmost = $true
    $celebration.ShowInTaskbar = $false
    $celebration.ResizeMode = [System.Windows.ResizeMode]::NoResize
    $celebration.WindowStartupLocation = [System.Windows.WindowStartupLocation]::CenterScreen

    $celebrationRoot = [System.Windows.Controls.Grid]::new()
    $celebrationRoot.Background = [System.Windows.Media.Brushes]::Transparent
    $celebration.Content = $celebrationRoot

    $card = [System.Windows.Controls.Border]::new()
    $card.Margin = [System.Windows.Thickness]::new(18)
    $card.CornerRadius = [System.Windows.CornerRadius]::new(28)
    $card.BorderThickness = [System.Windows.Thickness]::new(2)
    $card.BorderBrush = [System.Windows.Media.SolidColorBrush]::new([System.Windows.Media.Color]::FromRgb(255, 215, 125))
    $card.Padding = [System.Windows.Thickness]::new(36, 28, 36, 24)
    $gradient = [System.Windows.Media.LinearGradientBrush]::new()
    $gradient.StartPoint = [System.Windows.Point]::new(0, 0)
    $gradient.EndPoint = [System.Windows.Point]::new(1, 1)
    $gradient.GradientStops.Add([System.Windows.Media.GradientStop]::new([System.Windows.Media.Color]::FromRgb(35, 42, 67), 0))
    $gradient.GradientStops.Add([System.Windows.Media.GradientStop]::new([System.Windows.Media.Color]::FromRgb(80, 45, 70), 1))
    $card.Background = $gradient
    $shadow = [System.Windows.Media.Effects.DropShadowEffect]::new()
    $shadow.BlurRadius = 25
    $shadow.ShadowDepth = 5
    $shadow.Opacity = 0.45
    $card.Effect = $shadow
    $celebrationRoot.Children.Add($card) | Out-Null

    $content = [System.Windows.Controls.StackPanel]::new()
    $content.HorizontalAlignment = [System.Windows.HorizontalAlignment]::Center
    $content.VerticalAlignment = [System.Windows.VerticalAlignment]::Center
    $card.Child = $content

    $title = [System.Windows.Controls.TextBlock]::new()
    $title.Text = '✦  里程碑达成  ✦'
    $title.Foreground = [System.Windows.Media.SolidColorBrush]::new([System.Windows.Media.Color]::FromRgb(255, 221, 145))
    $title.FontFamily = [System.Windows.Media.FontFamily]::new('Microsoft YaHei UI')
    $title.FontSize = 22
    $title.FontWeight = [System.Windows.FontWeights]::SemiBold
    $title.HorizontalAlignment = [System.Windows.HorizontalAlignment]::Center
    $content.Children.Add($title) | Out-Null

    $milestoneText = [System.Windows.Controls.TextBlock]::new()
    $milestoneText.Text = "$tenThousands 万字"
    $milestoneText.Foreground = [System.Windows.Media.Brushes]::White
    $milestoneText.FontFamily = [System.Windows.Media.FontFamily]::new('Microsoft YaHei UI')
    $milestoneText.FontSize = 48
    $milestoneText.FontWeight = [System.Windows.FontWeights]::Bold
    $milestoneText.Margin = [System.Windows.Thickness]::new(0, 8, 0, 2)
    $milestoneText.HorizontalAlignment = [System.Windows.HorizontalAlignment]::Center
    $content.Children.Add($milestoneText) | Out-Null

    $message = [System.Windows.Controls.TextBlock]::new()
    $message.Text = "太棒了，已经累计 $tenThousands 万字了！"
    $message.Foreground = [System.Windows.Media.SolidColorBrush]::new([System.Windows.Media.Color]::FromRgb(230, 226, 235))
    $message.FontFamily = [System.Windows.Media.FontFamily]::new('Microsoft YaHei UI')
    $message.FontSize = 17
    $message.Margin = [System.Windows.Thickness]::new(0, 0, 0, 20)
    $message.HorizontalAlignment = [System.Windows.HorizontalAlignment]::Center
    $content.Children.Add($message) | Out-Null

    $continueButton = [System.Windows.Controls.Button]::new()
    $continueButton.Content = '继续加油'
    $continueButton.Width = 118
    $continueButton.Height = 36
    $continueButton.FontFamily = [System.Windows.Media.FontFamily]::new('Microsoft YaHei UI')
    $continueButton.FontSize = 15
    $continueButton.FontWeight = [System.Windows.FontWeights]::SemiBold
    $continueButton.Foreground = [System.Windows.Media.SolidColorBrush]::new([System.Windows.Media.Color]::FromRgb(48, 42, 51))
    $continueButton.Background = [System.Windows.Media.SolidColorBrush]::new([System.Windows.Media.Color]::FromRgb(255, 217, 135))
    $continueButton.BorderThickness = [System.Windows.Thickness]::new(0)
    $continueButton.Cursor = [System.Windows.Input.Cursors]::Hand
    $continueButton.Add_Click({ $script:celebrationWindow.Close() })
    $content.Children.Add($continueButton) | Out-Null

    $celebration.Add_MouseLeftButtonDown({
        if ($_.ClickCount -eq 2) { $script:celebrationWindow.Close() }
    })
    $celebration.Add_Closed({
        if ($null -ne $script:celebrationTimer) {
            $script:celebrationTimer.Stop()
            $script:celebrationTimer = $null
        }
        $script:celebrationWindow = $null
    })

    $script:celebrationTimer = [System.Windows.Threading.DispatcherTimer]::new()
    $script:celebrationTimer.Interval = [TimeSpan]::FromSeconds(8)
    $script:celebrationTimer.Add_Tick({
        $script:celebrationTimer.Stop()
        if ($null -ne $script:celebrationWindow) { $script:celebrationWindow.Close() }
    })
    $script:celebrationTimer.Start()
    $celebration.Show()
}

$window = [System.Windows.Window]::new()
$window.Title = '打字桌宠'
$window.Width = 292
$window.Height = 365
$window.WindowStyle = [System.Windows.WindowStyle]::None
$window.AllowsTransparency = $true
$window.Background = [System.Windows.Media.Brushes]::Transparent
$window.Topmost = $true
$window.ShowInTaskbar = $false
$window.ResizeMode = [System.Windows.ResizeMode]::NoResize
$window.SnapsToDevicePixels = $true
if ($TestMode) { $window.Opacity = 0 }

$root = [System.Windows.Controls.Grid]::new()
$root.Background = [System.Windows.Media.Brushes]::Transparent
$window.Content = $root

$petImage = [System.Windows.Controls.Image]::new()
$petImage.Width = 270
$petImage.Height = 320
$petImage.Stretch = [System.Windows.Media.Stretch]::Uniform
$petImage.VerticalAlignment = [System.Windows.VerticalAlignment]::Bottom
$petImage.HorizontalAlignment = [System.Windows.HorizontalAlignment]::Center
$petImage.IsHitTestVisible = $false

if (-not (Test-Path -LiteralPath $assetPath)) {
    [System.Windows.MessageBox]::Show("找不到桌宠素材：`n$assetPath", '打字桌宠') | Out-Null
    exit 1
}
$initialImagePath = $assetPath
if ($null -ne $stats.customImagePath -and (Test-Path -LiteralPath $stats.customImagePath)) {
    $initialImagePath = $stats.customImagePath
}
try {
    $bitmap = Get-LoadedBitmap $initialImagePath
}
catch {
    $stats.customImagePath = $null
    $bitmap = Get-LoadedBitmap $assetPath
    $script:isDirty = $true
}
$petImage.Source = $bitmap
$root.Children.Add($petImage) | Out-Null

$counter = [System.Windows.Controls.Border]::new()
$counter.CornerRadius = [System.Windows.CornerRadius]::new(15)
$counter.Padding = [System.Windows.Thickness]::new(14, 8, 14, 8)
$counter.Background = [System.Windows.Media.SolidColorBrush]::new([System.Windows.Media.Color]::FromArgb(222, 30, 36, 49))
$counter.BorderBrush = [System.Windows.Media.SolidColorBrush]::new([System.Windows.Media.Color]::FromArgb(120, 255, 255, 255))
$counter.BorderThickness = [System.Windows.Thickness]::new(1)
$counter.HorizontalAlignment = [System.Windows.HorizontalAlignment]::Center
$counter.VerticalAlignment = [System.Windows.VerticalAlignment]::Top
$counter.Margin = [System.Windows.Thickness]::new(0, 14, 0, 0)

$counterPanel = [System.Windows.Controls.StackPanel]::new()
$counterPanel.Orientation = [System.Windows.Controls.Orientation]::Horizontal
$counter.Child = $counterPanel

$todayText = [System.Windows.Controls.TextBlock]::new()
$todayText.Foreground = [System.Windows.Media.Brushes]::White
$todayText.FontFamily = [System.Windows.Media.FontFamily]::new('Microsoft YaHei UI')
$todayText.FontSize = 14
$todayText.FontWeight = [System.Windows.FontWeights]::SemiBold
$counterPanel.Children.Add($todayText) | Out-Null

$divider = [System.Windows.Controls.TextBlock]::new()
$divider.Text = '   ·   '
$divider.Foreground = [System.Windows.Media.SolidColorBrush]::new([System.Windows.Media.Color]::FromRgb(150, 160, 175))
$divider.FontSize = 14
$counterPanel.Children.Add($divider) | Out-Null

$totalText = [System.Windows.Controls.TextBlock]::new()
$totalText.Foreground = [System.Windows.Media.SolidColorBrush]::new([System.Windows.Media.Color]::FromRgb(255, 215, 130))
$totalText.FontFamily = [System.Windows.Media.FontFamily]::new('Microsoft YaHei UI')
$totalText.FontSize = 14
$totalText.FontWeight = [System.Windows.FontWeights]::SemiBold
$counterPanel.Children.Add($totalText) | Out-Null

$root.Children.Add($counter) | Out-Null
Update-Display

$menu = [System.Windows.Controls.ContextMenu]::new()
$menu.FontFamily = [System.Windows.Media.FontFamily]::new('Microsoft YaHei UI')

$changeImageItem = [System.Windows.Controls.MenuItem]::new()
$changeImageItem.Header = '更换角色图片…'
$changeImageItem.Add_Click({
    $dialog = [Microsoft.Win32.OpenFileDialog]::new()
    $dialog.Title = '选择桌宠角色图片'
    $dialog.Filter = '图片文件|*.png;*.jpg;*.jpeg;*.bmp;*.gif|PNG 图片|*.png|JPEG 图片|*.jpg;*.jpeg|所有文件|*.*'
    $dialog.CheckFileExists = $true
    $dialog.Multiselect = $false
    if ($dialog.ShowDialog() -eq $true) {
        try {
            # Decode before replacing the saved image so invalid files cannot damage the current character.
            $null = Get-LoadedBitmap $dialog.FileName
            $choice = [System.Windows.MessageBox]::Show(
                '是否自动抠出图片主体并将背景变为透明？' + "`n`n" +
                '选择“是”：自动识别并移除背景。' + "`n" +
                '选择“否”：保留原图背景，只统一调整尺寸。',
                '处理角色图片',
                [System.Windows.MessageBoxButton]::YesNoCancel,
                [System.Windows.MessageBoxImage]::Question)
            if ($choice -eq [System.Windows.MessageBoxResult]::Cancel) { return }
            $removeBackground = $choice -eq [System.Windows.MessageBoxResult]::Yes
            $previousCustomImagePath = $stats.customImagePath
            $savedImagePath = Save-CustomPetImage $dialog.FileName $removeBackground
            $petImage.Source = Get-LoadedBitmap $savedImagePath
            $stats.customImagePath = $savedImagePath
            $script:isDirty = $true
            Save-Stats
            Remove-SavedCustomImage $previousCustomImagePath
        }
        catch {
            [System.Windows.MessageBox]::Show("无法使用这张图片：`n$($_.Exception.Message)", '打字桌宠') | Out-Null
        }
    }
})
$menu.Items.Add($changeImageItem) | Out-Null

$restoreImageItem = [System.Windows.Controls.MenuItem]::new()
$restoreImageItem.Header = '恢复默认角色'
$restoreImageItem.Add_Click({
    try {
        $previousCustomImagePath = $stats.customImagePath
        $petImage.Source = Get-LoadedBitmap $assetPath
        $stats.customImagePath = $null
        $script:isDirty = $true
        Save-Stats
        Remove-SavedCustomImage $previousCustomImagePath
    }
    catch {
        [System.Windows.MessageBox]::Show("无法恢复默认角色：`n$($_.Exception.Message)", '打字桌宠') | Out-Null
    }
})
$menu.Items.Add($restoreImageItem) | Out-Null
$menu.Items.Add([System.Windows.Controls.Separator]::new()) | Out-Null

$resetTodayItem = [System.Windows.Controls.MenuItem]::new()
$resetTodayItem.Header = '清零今日计数'
$resetTodayItem.Add_Click({
    $answer = [System.Windows.MessageBox]::Show('确定清零今日计数吗？历史累计不会改变。', '打字桌宠', 'YesNo', 'Question')
    if ($answer -eq [System.Windows.MessageBoxResult]::Yes) {
        $stats.todayCount = [long]0
        $script:isDirty = $true
        Update-Display
        Save-Stats
    }
})
$menu.Items.Add($resetTodayItem) | Out-Null

$exitItem = [System.Windows.Controls.MenuItem]::new()
$exitItem.Header = '退出桌宠'
$exitItem.Add_Click({ $window.Close() })
$menu.Items.Add($exitItem) | Out-Null
$root.ContextMenu = $menu

$window.Add_MouseLeftButtonDown({
    try { $window.DragMove() } catch { }
})
$window.Add_LocationChanged({ $script:isDirty = $true })

$window.Add_SourceInitialized({
    $workArea = [System.Windows.SystemParameters]::WorkArea
    if (-not $ResetPosition -and $null -ne $stats.left -and $null -ne $stats.top) {
        $window.Left = [Math]::Max($workArea.Left, [Math]::Min([double]$stats.left, $workArea.Right - $window.Width))
        $window.Top = [Math]::Max($workArea.Top, [Math]::Min([double]$stats.top, $workArea.Bottom - $window.Height))
    }
    else {
        $window.Left = $workArea.Right - $window.Width - 24
        $window.Top = $workArea.Bottom - $window.Height - 24
    }
})

$keyHandler = [Action]{
    $window.Dispatcher.BeginInvoke([Action]{
        Update-Day
        $stats.todayCount = [long]$stats.todayCount + 1
        $stats.totalCount = [long]$stats.totalCount + 1
        $script:isDirty = $true
        Update-Display
        $reachedMilestone = [long][Math]::Floor($stats.totalCount / 10000)
        if ($reachedMilestone -ge 1 -and $reachedMilestone -gt $stats.lastCelebrated) {
            $stats.lastCelebrated = $reachedMilestone
            Save-Stats
            Show-Celebration $reachedMilestone
        }
    }, [System.Windows.Threading.DispatcherPriority]::Background) | Out-Null
}
[GlobalKeyboardCounter]::add_KeyPressed($keyHandler)

$timer = [System.Windows.Threading.DispatcherTimer]::new()
$timer.Interval = [TimeSpan]::FromSeconds(1)
$timer.Add_Tick({
    Update-Day
    if ($script:isDirty -and ([DateTime]::Now - $script:lastSaved).TotalSeconds -ge 3) {
        Save-Stats
    }
})

$window.Add_Loaded({
    try {
        [GlobalKeyboardCounter]::Start()
        $timer.Start()
        if ($TestMode) {
            Write-Output 'TEST_HOOK_OK'
            $testImageInput = if ($env:TYPING_PET_TEST_IMAGE) { $env:TYPING_PET_TEST_IMAGE } else { $assetPath }
            [PetImageProcessor]::Process(
                $testImageInput,
                (Join-Path $scriptRoot '.image-processor-test.png'),
                $true,
                512)
            $firstChange = Save-CustomPetImage $testImageInput $true
            $petImage.Source = Get-LoadedBitmap $firstChange
            $secondChange = Save-CustomPetImage $testImageInput $false
            $petImage.Source = Get-LoadedBitmap $secondChange
            Remove-SavedCustomImage $firstChange
            Remove-SavedCustomImage $secondChange
            Show-Celebration 1
            $script:testTimer = [System.Windows.Threading.DispatcherTimer]::new()
            $script:testTimer.Interval = [TimeSpan]::FromMilliseconds(500)
            $script:testTimer.Add_Tick({
                $script:testTimer.Stop()
                $window.Close()
            })
            $script:testTimer.Start()
        }
    }
    catch {
        [System.Windows.MessageBox]::Show("无法启动全局键盘计数：`n$($_.Exception.Message)", '打字桌宠') | Out-Null
        $window.Close()
    }
})

$window.Add_Closing({
    $timer.Stop()
    [GlobalKeyboardCounter]::Stop()
    [GlobalKeyboardCounter]::remove_KeyPressed($keyHandler)
    try {
        Save-Stats
        if ($TestMode) { Write-Output 'TEST_SAVE_OK' }
    }
    catch {
        if ($TestMode) { throw }
    }
})

$application = [System.Windows.Application]::new()
$application.ShutdownMode = [System.Windows.ShutdownMode]::OnMainWindowClose
$application.Run($window) | Out-Null

