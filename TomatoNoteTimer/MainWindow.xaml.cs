using System;
using System.Collections.Generic;
using System.ComponentModel;
using System.Diagnostics;
using System.IO;
using System.Linq;
using System.Runtime;
using System.Runtime.InteropServices;
using System.Windows;
using System.Windows.Input;
using System.Windows.Interop;
using System.Windows.Media;
using System.Windows.Media.Effects;
using System.Windows.Media.Imaging;
using System.Windows.Threading;
using Microsoft.Win32;
using TomatoNoteTimer.Dialogs;
using TomatoNoteTimer.Models;
using TomatoNoteTimer.Services;
using Drawing = System.Drawing;
using WinForms = System.Windows.Forms;
using Color = System.Windows.Media.Color;
using FontFamily = System.Windows.Media.FontFamily;
using MediaBrushes = System.Windows.Media.Brushes;
using MediaPoint = System.Windows.Point;
using WpfApplication = System.Windows.Application;
using WpfMessageBox = System.Windows.MessageBox;

namespace TomatoNoteTimer;

public partial class MainWindow : Window
{
    private const string RunKeyPath = @"Software\Microsoft\Windows\CurrentVersion\Run";
    private const string RunValueName = "TomatoNoteTimer";
    private const string DefaultIconFileName = "icon.ico";
    private const string DefaultNoteText = "人生若只如初见，何事秋风悲画扇";
    private const string RepositoryUrl = "https://github.com/xiaoshengyvlin/Zako-Pomodoro-timer";
    private const int WmHotKey = 0x0312;
    private const int HotkeyIdBase = 3000;
    private const uint ModAlt = 0x0001;
    private const uint ModControl = 0x0002;
    private const uint ModShift = 0x0004;
    private const uint ModWin = 0x0008;
    private const long MemoryTrimWorkingSetThresholdBytes = 45L * 1024 * 1024;
    private const long MemoryTrimPrivateThresholdBytes = 130L * 1024 * 1024;

    private static readonly HotkeyAction[] SupportedHotkeyActions =
    {
        HotkeyAction.ToggleTopMost,
        HotkeyAction.ToggleFixedMode,
        HotkeyAction.ToggleVisibility,
        HotkeyAction.NextNote,
        HotkeyAction.PrevNote
    };

    [DllImport("psapi.dll", SetLastError = true)]
    private static extern bool EmptyWorkingSet(IntPtr hProcess);
    [DllImport("user32.dll", SetLastError = true)]
    private static extern bool RegisterHotKey(IntPtr hWnd, int id, uint fsModifiers, uint vk);
    [DllImport("user32.dll", SetLastError = true)]
    private static extern bool UnregisterHotKey(IntPtr hWnd, int id);

    private enum HotkeyAction
    {
        ToggleTopMost = 1,
        ToggleFixedMode = 2,
        ToggleVisibility = 3,
        NextNote = 4,
        PrevNote = 5
    }

    private readonly DispatcherTimer _noteRotationTimer;
    private readonly DispatcherTimer _memoryGuardTimer;
    private readonly ConfigService _configService;

    private AppState _state;
    private WinForms.NotifyIcon? _notifyIcon;
    private Drawing.Icon? _trayIcon;
    private bool _isExiting;

    private WinForms.ToolStripMenuItem? _topMostItem;
    private WinForms.ToolStripMenuItem? _fixedModeItem;
    private WinForms.ToolStripMenuItem? _rotationEnabledItem;
    private WinForms.ToolStripMenuItem? _autoStartItem;
    private WinForms.ToolStripMenuItem? _minimizeToTrayItem;
    private readonly Dictionary<string, WinForms.ToolStripMenuItem> _backgroundModeItems = new(StringComparer.OrdinalIgnoreCase);
    private readonly Dictionary<int, HotkeyAction> _registeredHotkeys = new();
    private double _lastAppliedTransparencyPercent = -1;
    private bool _suppressCheckCallbacks;
    private bool _suspendedForTray;
    private bool _noteRotationRunningBeforeSuspend;
    private DateTime _lastMemoryTrimUtc = DateTime.MinValue;
    private bool _memoryPressureMode;
    private IntPtr _windowHandle;
    private HwndSource? _windowSource;

    public MainWindow()
    {
        InitializeComponent();
        SourceInitialized += MainWindow_SourceInitialized;

        _configService = new ConfigService(AppContext.BaseDirectory);
        _state = _configService.Load();

        _noteRotationTimer = new DispatcherTimer();
        _noteRotationTimer.Tick += NoteRotationTimer_Tick;

        _memoryGuardTimer = new DispatcherTimer
        {
            Interval = TimeSpan.FromSeconds(10)
        };
        _memoryGuardTimer.Tick += MemoryGuardTimer_Tick;
        _memoryGuardTimer.Start();

        LoadWindowIcon();
        ApplyStateToUi();
        ConfigureNoteRotationTimer();
        InitializeTrayIcon();

        _state.App.AutoStart = IsAutoStartEnabled();
        _configService.AppendLog("应用启动");
    }

    private void Window_Loaded(object sender, RoutedEventArgs e)
    {
        ApplyVisualEffects();
        ApplyResponsiveLayout();
        UpdateNotesText();
        Dispatcher.BeginInvoke(DispatcherPriority.ApplicationIdle, new Action(TrimMemoryUsage));
    }

    private void MainWindow_SourceInitialized(object? sender, EventArgs e)
    {
        _windowHandle = new WindowInteropHelper(this).Handle;
        _windowSource = HwndSource.FromHwnd(_windowHandle);
        _windowSource?.AddHook(WindowProc);
        _ = TryApplyConfiguredHotkeys(showDialogOnFailure: false);

        ApplyVisualEffects();
        ApplyResponsiveLayout();
    }

    private void Window_SizeChanged(object sender, SizeChangedEventArgs e)
    {
        ApplyResponsiveLayout();
    }

    private void RootBorder_MouseLeftButtonDown(object sender, MouseButtonEventArgs e)
    {
        if (_state.App.FixedMode)
        {
            return;
        }

        if (e.LeftButton == MouseButtonState.Pressed)
        {
            DragMove();
        }
    }

    private void Window_MouseWheel(object sender, MouseWheelEventArgs e)
    {
        if (_state.App.FixedMode)
        {
            return;
        }

        double factor = e.Delta > 0 ? 1.06 : 0.94;
        int nextWidth = (int)Math.Clamp(Width * factor, 140, 960);
        int nextHeight = (int)Math.Clamp(Height * factor, 88, 720);

        Width = nextWidth;
        Height = nextHeight;

        _state.App.WindowWidth = nextWidth;
        _state.App.WindowHeight = nextHeight;
        SaveState();
    }

    private void Window_Closing(object? sender, CancelEventArgs e)
    {
        if (!_isExiting && _state.App.MinimizeToTrayOnClose)
        {
            e.Cancel = true;
            Hide();
            SuspendWindowForTray();
            _notifyIcon?.ShowBalloonTip(1200, "便签", "已最小化到托盘。", WinForms.ToolTipIcon.Info);
            return;
        }

        UnregisterAllHotkeys();
        if (_windowSource is not null)
        {
            _windowSource.RemoveHook(WindowProc);
            _windowSource = null;
        }

        SaveState();
        DisposeTrayIcon();
    }

    private void InitializeTrayIcon()
    {
        _notifyIcon = new WinForms.NotifyIcon();
        _trayIcon = LoadTrayIcon();

        _notifyIcon.Icon = _trayIcon;
        _notifyIcon.Visible = true;
        _notifyIcon.Text = "便签";
        _notifyIcon.MouseUp += NotifyIcon_MouseUp;
        _notifyIcon.ContextMenuStrip = BuildTrayMenu();
    }

    private void NotifyIcon_MouseUp(object? sender, WinForms.MouseEventArgs e)
    {
        if (e.Button != WinForms.MouseButtons.Left)
        {
            return;
        }

        DispatchToUi(ToggleWindowVisibility);
    }

    private WinForms.ContextMenuStrip BuildTrayMenu()
    {
        var menu = new WinForms.ContextMenuStrip();

        menu.Items.Add(CreateMenuItem("显示/隐藏窗口", ToggleWindowVisibility));
        menu.Items.Add(new WinForms.ToolStripSeparator());

        var notesMenu = new WinForms.ToolStripMenuItem("便签设置");
        notesMenu.DropDownItems.Add(CreateMenuItem("编辑便签段落", EditNotes));
        notesMenu.DropDownItems.Add(CreateMenuItem("上一段便签", ShowPreviousNote));
        notesMenu.DropDownItems.Add(CreateMenuItem("下一段便签", ShowNextNote));
        notesMenu.DropDownItems.Add(new WinForms.ToolStripSeparator());
        _rotationEnabledItem = CreateCheckMenuItem("启用便签定时切换", _state.Notes.EnableRotation, ToggleNoteRotation);
        notesMenu.DropDownItems.Add(_rotationEnabledItem);
        notesMenu.DropDownItems.Add(CreateMenuItem("设置便签切换秒数", ConfigureRotationSeconds));
        notesMenu.DropDownItems.Add(new WinForms.ToolStripSeparator());
        notesMenu.DropDownItems.Add(CreateMenuItem("设置便签字体", ConfigureNoteFont));
        notesMenu.DropDownItems.Add(CreateMenuItem("设置便签字号", ConfigureNoteFontSize));
        notesMenu.DropDownItems.Add(CreateMenuItem("设置便签文字颜色", ConfigureNotesTextColor));
        menu.Items.Add(notesMenu);

        var appearanceMenu = new WinForms.ToolStripMenuItem("外观设置");
        appearanceMenu.DropDownItems.Add(CreateMenuItem("设置背景颜色", ConfigureBackgroundColor));
        menu.Items.Add(appearanceMenu);
        menu.Items.Add(BuildBackgroundEffectMenu());
        menu.Items.Add(BuildTransparencyMenu());

        var systemMenu = new WinForms.ToolStripMenuItem("系统设置");
        _topMostItem = CreateCheckMenuItem("窗口置顶", _state.App.TopMost, ToggleTopMost);
        _fixedModeItem = CreateCheckMenuItem("固定模式（不可拖拽）", _state.App.FixedMode, ToggleFixedMode);
        systemMenu.DropDownItems.Add(_topMostItem);
        systemMenu.DropDownItems.Add(_fixedModeItem);
        _autoStartItem = CreateCheckMenuItem("开机自启动", _state.App.AutoStart, ToggleAutoStart);
        _minimizeToTrayItem = CreateCheckMenuItem("关闭时最小化到托盘", _state.App.MinimizeToTrayOnClose, ToggleMinimizeToTrayOnClose);
        systemMenu.DropDownItems.Add(_autoStartItem);
        systemMenu.DropDownItems.Add(_minimizeToTrayItem);
        menu.Items.Add(systemMenu);
        menu.Items.Add(CreateMenuItem("快捷键设置", OpenHotkeySettingsDialog));

        menu.Items.Add(CreateMenuItem("github仓库", OpenGithubRepository));
        menu.Items.Add(CreateMenuItem("打开配置目录", OpenConfigDirectory));
        menu.Items.Add(new WinForms.ToolStripSeparator());
        menu.Items.Add(CreateMenuItem("退出程序", ExitApplication));

        UpdateBackgroundEffectChecks();
        return menu;
    }

    private WinForms.ToolStripMenuItem BuildTransparencyMenu()
    {
        var menu = new WinForms.ToolStripMenuItem("透明度（0~100，越高越透明）");

        foreach (int value in Enumerable.Range(0, 21).Select(i => i * 5))
        {
            var item = new WinForms.ToolStripMenuItem($"{value}%")
            {
                CheckOnClick = true,
                Checked = Math.Abs(_state.App.Transparency - value) < 0.5,
                Tag = value
            };

            item.Click += (_, _) =>
            {
                if (item.Tag is not int selected)
                {
                    return;
                }

                foreach (WinForms.ToolStripItem child in menu.DropDownItems)
                {
                    if (child is WinForms.ToolStripMenuItem menuItem)
                    {
                        menuItem.Checked = ReferenceEquals(menuItem, item);
                    }
                }

                _state.App.Transparency = selected;
                ApplyVisualEffects();
                SaveState();
            };

            menu.DropDownItems.Add(item);
        }

        return menu;
    }

    private WinForms.ToolStripMenuItem BuildBackgroundEffectMenu()
    {
        var menu = new WinForms.ToolStripMenuItem("背景效果");
        AddBackgroundEffectItem(menu, "毛玻璃（增强质感）", "Blur");
        AddBackgroundEffectItem(menu, "磨砂（增强质感）", "Frosted");
        AddBackgroundEffectItem(menu, "苹果风（边缘毛玻璃）", "Apple");
        return menu;
    }

    private void AddBackgroundEffectItem(WinForms.ToolStripMenuItem parent, string text, string mode)
    {
        var item = new WinForms.ToolStripMenuItem(text)
        {
            CheckOnClick = true,
            Tag = mode
        };
        item.Click += (_, _) =>
        {
            _state.App.BackgroundEffect = mode;
            UpdateBackgroundEffectChecks();
            ApplyVisualEffects();
            SaveState();
        };
        _backgroundModeItems[mode] = item;
        parent.DropDownItems.Add(item);
    }

    private void UpdateBackgroundEffectChecks()
    {
        foreach ((string key, WinForms.ToolStripMenuItem item) in _backgroundModeItems)
        {
            item.Checked = string.Equals(_state.App.BackgroundEffect, key, StringComparison.OrdinalIgnoreCase);
        }
    }

    private void OpenHotkeySettingsDialog()
    {
        var dialog = new HotkeySettingsDialog(CloneHotkeySettings(_state.App.Hotkeys));
        if (IsVisible)
        {
            dialog.Owner = this;
        }
        else
        {
            dialog.WindowStartupLocation = WindowStartupLocation.CenterScreen;
        }

        bool? result = dialog.ShowDialog();
        if (result != true)
        {
            return;
        }

        HotkeySettings previous = CloneHotkeySettings(_state.App.Hotkeys);
        _state.App.Hotkeys = CloneHotkeySettings(dialog.Hotkeys);
        _state.App.Hotkeys.Normalize();

        if (!TryApplyConfiguredHotkeys(showDialogOnFailure: true))
        {
            _state.App.Hotkeys = previous;
            _ = TryApplyConfiguredHotkeys(showDialogOnFailure: false);
            return;
        }

        SaveState();
        _configService.AppendLog("快捷键设置已更新");
    }

    private static HotkeySettings CloneHotkeySettings(HotkeySettings? source)
    {
        source ??= new HotkeySettings();
        return new HotkeySettings
        {
            ToggleTopMost = source.ToggleTopMost,
            ToggleFixedMode = source.ToggleFixedMode,
            ToggleVisibility = source.ToggleVisibility,
            NextNote = source.NextNote,
            PrevNote = source.PrevNote
        };
    }

    private bool TryApplyConfiguredHotkeys(bool showDialogOnFailure)
    {
        if (_windowHandle == IntPtr.Zero)
        {
            return true;
        }

        UnregisterAllHotkeys();

        bool changed = false;
        var errors = new List<string>();
        var usedCombinations = new HashSet<string>(StringComparer.OrdinalIgnoreCase);

        foreach (HotkeyAction action in SupportedHotkeyActions)
        {
            string raw = GetConfiguredHotkey(action);
            if (string.IsNullOrWhiteSpace(raw))
            {
                continue;
            }

            if (!TryParseHotkey(raw, out uint modifiers, out uint virtualKey, out string normalized, out string parseError))
            {
                errors.Add($"{GetHotkeyActionTitle(action)}：{parseError}");
                continue;
            }

            if (!string.Equals(raw, normalized, StringComparison.Ordinal))
            {
                SetConfiguredHotkey(action, normalized);
                changed = true;
            }

            if (!usedCombinations.Add(normalized))
            {
                errors.Add($"{GetHotkeyActionTitle(action)}：与其他动作重复 ({normalized})");
                continue;
            }

            int hotkeyId = HotkeyIdBase + (int)action;
            if (!RegisterHotKey(_windowHandle, hotkeyId, modifiers, virtualKey))
            {
                int errorCode = Marshal.GetLastWin32Error();
                errors.Add($"{GetHotkeyActionTitle(action)}：注册失败（错误码 {errorCode}）");
                continue;
            }

            _registeredHotkeys[hotkeyId] = action;
        }

        if (errors.Count > 0)
        {
            UnregisterAllHotkeys();
            string message = string.Join(Environment.NewLine, errors);
            _configService.AppendLog($"快捷键注册失败: {message.Replace(Environment.NewLine, " | ")}");
            if (showDialogOnFailure)
            {
                WpfMessageBox.Show(this, $"快捷键设置未生效：{Environment.NewLine}{message}", "快捷键注册失败", MessageBoxButton.OK, MessageBoxImage.Warning);
            }
            return false;
        }

        if (changed)
        {
            _configService.Save(_state);
        }
        return true;
    }

    private void UnregisterAllHotkeys()
    {
        if (_windowHandle == IntPtr.Zero)
        {
            _registeredHotkeys.Clear();
            return;
        }

        foreach (int id in _registeredHotkeys.Keys.ToList())
        {
            _ = UnregisterHotKey(_windowHandle, id);
        }

        _registeredHotkeys.Clear();
    }

    private IntPtr WindowProc(IntPtr hwnd, int msg, IntPtr wParam, IntPtr lParam, ref bool handled)
    {
        _ = hwnd;
        _ = lParam;
        if (msg != WmHotKey)
        {
            return IntPtr.Zero;
        }

        int id = wParam.ToInt32();
        if (_registeredHotkeys.TryGetValue(id, out HotkeyAction action))
        {
            ExecuteHotkeyAction(action);
            handled = true;
        }

        return IntPtr.Zero;
    }

    private void ExecuteHotkeyAction(HotkeyAction action)
    {
        switch (action)
        {
            case HotkeyAction.ToggleTopMost:
            {
                bool enabled = !_state.App.TopMost;
                ToggleTopMost(enabled);
                if (_topMostItem is not null)
                {
                    SetMenuChecked(_topMostItem, enabled);
                }
                break;
            }
            case HotkeyAction.ToggleFixedMode:
            {
                bool enabled = !_state.App.FixedMode;
                ToggleFixedMode(enabled);
                if (_fixedModeItem is not null)
                {
                    SetMenuChecked(_fixedModeItem, enabled);
                }
                break;
            }
            case HotkeyAction.ToggleVisibility:
                ToggleWindowVisibility();
                break;
            case HotkeyAction.NextNote:
                ShowNextNote();
                break;
            case HotkeyAction.PrevNote:
                ShowPreviousNote();
                break;
        }

        _configService.AppendLog($"快捷键触发: {GetHotkeyActionTitle(action)}");
    }

    private static bool TryParseHotkey(string raw, out uint modifiers, out uint virtualKey, out string normalized, out string error)
    {
        modifiers = 0;
        virtualKey = 0;
        normalized = string.Empty;
        error = string.Empty;

        if (string.IsNullOrWhiteSpace(raw))
        {
            error = "快捷键不能为空。";
            return false;
        }

        string[] tokens = raw.Split('+', StringSplitOptions.TrimEntries | StringSplitOptions.RemoveEmptyEntries);
        if (tokens.Length < 2)
        {
            error = "快捷键至少需要一个修饰键和一个主键，例如 Ctrl+Alt+S。";
            return false;
        }

        string? keyToken = null;
        foreach (string token in tokens)
        {
            if (TryParseModifierToken(token, out uint modifier))
            {
                if ((modifiers & modifier) != 0)
                {
                    error = $"修饰键重复：{token}";
                    return false;
                }

                modifiers |= modifier;
                continue;
            }

            if (keyToken is not null)
            {
                error = "只能设置一个主键。";
                return false;
            }

            keyToken = token;
        }

        if (modifiers == 0)
        {
            error = "必须包含 Ctrl/Alt/Shift/Win 中至少一个修饰键。";
            return false;
        }

        if (string.IsNullOrWhiteSpace(keyToken))
        {
            error = "缺少主键。";
            return false;
        }

        if (!TryParseMainKey(keyToken, out Key key, out string keyName))
        {
            error = $"不支持的主键：{keyToken}";
            return false;
        }

        int vk = KeyInterop.VirtualKeyFromKey(key);
        if (vk == 0)
        {
            error = "无法识别主键。";
            return false;
        }

        virtualKey = (uint)vk;
        normalized = BuildNormalizedHotkey(modifiers, keyName);
        return true;
    }

    private static bool TryParseModifierToken(string token, out uint modifier)
    {
        modifier = 0;
        string normalized = token.Trim().ToLowerInvariant();
        switch (normalized)
        {
            case "ctrl":
            case "control":
            case "ctl":
            case "控制":
            case "控制键":
                modifier = ModControl;
                return true;
            case "alt":
            case "选项":
            case "选项键":
                modifier = ModAlt;
                return true;
            case "shift":
            case "上档":
            case "上档键":
                modifier = ModShift;
                return true;
            case "win":
            case "windows":
            case "meta":
            case "徽标":
            case "徽标键":
                modifier = ModWin;
                return true;
            default:
                return false;
        }
    }

    private static bool TryParseMainKey(string token, out Key key, out string display)
    {
        key = Key.None;
        display = string.Empty;

        string normalized = token.Trim();
        if (normalized.Length == 1)
        {
            char c = char.ToUpperInvariant(normalized[0]);
            if (c is >= 'A' and <= 'Z')
            {
                key = (Key)Enum.Parse(typeof(Key), c.ToString());
                display = c.ToString();
                return true;
            }

            if (c is >= '0' and <= '9')
            {
                key = c switch
                {
                    '0' => Key.D0,
                    '1' => Key.D1,
                    '2' => Key.D2,
                    '3' => Key.D3,
                    '4' => Key.D4,
                    '5' => Key.D5,
                    '6' => Key.D6,
                    '7' => Key.D7,
                    '8' => Key.D8,
                    _ => Key.D9
                };
                display = c.ToString();
                return true;
            }
        }

        string upper = normalized.ToUpperInvariant();
        switch (upper)
        {
            case "ESC":
            case "ESCAPE":
                key = Key.Escape;
                display = "Esc";
                return true;
            case "SPACE":
            case "SPACEBAR":
            case "空格":
                key = Key.Space;
                display = "Space";
                return true;
            case "ENTER":
            case "RETURN":
            case "回车":
                key = Key.Enter;
                display = "Enter";
                return true;
            case "TAB":
                key = Key.Tab;
                display = "Tab";
                return true;
            case "UP":
            case "上":
                key = Key.Up;
                display = "Up";
                return true;
            case "DOWN":
            case "下":
                key = Key.Down;
                display = "Down";
                return true;
            case "LEFT":
            case "左":
                key = Key.Left;
                display = "Left";
                return true;
            case "RIGHT":
            case "右":
                key = Key.Right;
                display = "Right";
                return true;
            case "HOME":
                key = Key.Home;
                display = "Home";
                return true;
            case "END":
                key = Key.End;
                display = "End";
                return true;
            case "PAGEUP":
            case "PGUP":
                key = Key.PageUp;
                display = "PageUp";
                return true;
            case "PAGEDOWN":
            case "PGDN":
                key = Key.PageDown;
                display = "PageDown";
                return true;
            case "INSERT":
            case "INS":
                key = Key.Insert;
                display = "Insert";
                return true;
            case "DELETE":
            case "DEL":
                key = Key.Delete;
                display = "Delete";
                return true;
        }

        if (upper.StartsWith("F", StringComparison.Ordinal) &&
            int.TryParse(upper[1..], out int fIndex) &&
            fIndex is >= 1 and <= 24)
        {
            key = (Key)((int)Key.F1 + (fIndex - 1));
            display = $"F{fIndex}";
            return true;
        }

        if (Enum.TryParse(normalized, ignoreCase: true, out Key parsed) &&
            parsed != Key.None &&
            parsed is not Key.LeftCtrl and not Key.RightCtrl and not Key.LeftAlt and not Key.RightAlt and not Key.LeftShift and not Key.RightShift and not Key.LWin and not Key.RWin)
        {
            key = parsed;
            display = parsed.ToString();
            return true;
        }

        return false;
    }

    private static string BuildNormalizedHotkey(uint modifiers, string keyName)
    {
        var parts = new List<string>();
        if ((modifiers & ModControl) != 0)
        {
            parts.Add("Ctrl");
        }

        if ((modifiers & ModAlt) != 0)
        {
            parts.Add("Alt");
        }

        if ((modifiers & ModShift) != 0)
        {
            parts.Add("Shift");
        }

        if ((modifiers & ModWin) != 0)
        {
            parts.Add("Win");
        }

        parts.Add(keyName);
        return string.Join("+", parts);
    }

    private string GetConfiguredHotkey(HotkeyAction action)
    {
        return action switch
        {
            HotkeyAction.ToggleTopMost => _state.App.Hotkeys.ToggleTopMost,
            HotkeyAction.ToggleFixedMode => _state.App.Hotkeys.ToggleFixedMode,
            HotkeyAction.ToggleVisibility => _state.App.Hotkeys.ToggleVisibility,
            HotkeyAction.NextNote => _state.App.Hotkeys.NextNote,
            HotkeyAction.PrevNote => _state.App.Hotkeys.PrevNote,
            _ => string.Empty
        };
    }

    private void SetConfiguredHotkey(HotkeyAction action, string value)
    {
        string normalized = string.IsNullOrWhiteSpace(value) ? string.Empty : value.Trim();
        switch (action)
        {
            case HotkeyAction.ToggleTopMost:
                _state.App.Hotkeys.ToggleTopMost = normalized;
                break;
            case HotkeyAction.ToggleFixedMode:
                _state.App.Hotkeys.ToggleFixedMode = normalized;
                break;
            case HotkeyAction.ToggleVisibility:
                _state.App.Hotkeys.ToggleVisibility = normalized;
                break;
            case HotkeyAction.NextNote:
                _state.App.Hotkeys.NextNote = normalized;
                break;
            case HotkeyAction.PrevNote:
                _state.App.Hotkeys.PrevNote = normalized;
                break;
        }
    }

    private static string GetHotkeyActionTitle(HotkeyAction action)
    {
        return action switch
        {
            HotkeyAction.ToggleTopMost => "窗口置顶开关",
            HotkeyAction.ToggleFixedMode => "窗口固定开关",
            HotkeyAction.ToggleVisibility => "显示/隐藏窗口",
            HotkeyAction.NextNote => "下一段便签",
            HotkeyAction.PrevNote => "上一段便签",
            _ => action.ToString()
        };
    }

    private WinForms.ToolStripMenuItem CreateMenuItem(string text, Action action)
    {
        var item = new WinForms.ToolStripMenuItem(text);
        item.Click += (_, _) => DispatchToUi(action);
        return item;
    }

    private WinForms.ToolStripMenuItem CreateCheckMenuItem(string text, bool initialValue, Action<bool> onChanged)
    {
        var item = new WinForms.ToolStripMenuItem(text)
        {
            CheckOnClick = true,
            Checked = initialValue
        };
        item.CheckedChanged += (_, _) =>
        {
            if (_suppressCheckCallbacks)
            {
                return;
            }

            DispatchToUi(() => onChanged(item.Checked));
        };
        return item;
    }

    private void ToggleWindowVisibility()
    {
        if (IsVisible)
        {
            Hide();
            SuspendWindowForTray();
            return;
        }

        Show();
        ResumeWindowFromTray();
        ApplyVisualEffects();
        ApplyResponsiveLayout();
        Activate();
    }

    private void ShowNextNote()
    {
        if (_state.NotesContent.Segments.Count <= 1)
        {
            return;
        }

        _state.NotesContent.CurrentIndex =
            (_state.NotesContent.CurrentIndex + 1) % _state.NotesContent.Segments.Count;
        UpdateNotesText();
        SaveState();
    }

    private void ShowPreviousNote()
    {
        int count = _state.NotesContent.Segments.Count;
        if (count <= 1)
        {
            return;
        }

        _state.NotesContent.CurrentIndex =
            (_state.NotesContent.CurrentIndex - 1 + count) % count;
        UpdateNotesText();
        SaveState();
    }

    private void EditNotes()
    {
        var dialog = new NotesEditorDialog(_state.NotesContent.Segments)
        {
            Owner = this
        };

        bool? result = dialog.ShowDialog();
        if (result != true)
        {
            return;
        }

        _state.NotesContent.Segments = dialog.Segments;
        _state.NotesContent.CurrentIndex = 0;
        UpdateNotesText();
        ConfigureNoteRotationTimer();
        SaveState();
    }

    private void ConfigureNoteFont()
    {
        using var dialog = new WinForms.FontDialog
        {
            ShowColor = false,
            ShowEffects = false
        };

        dialog.Font = new Drawing.Font(_state.Notes.FontFamily, (float)_state.Notes.FontSize);

        if (dialog.ShowDialog() != WinForms.DialogResult.OK)
        {
            return;
        }

        _state.Notes.FontFamily = dialog.Font.FontFamily.Name;
        _state.Notes.FontSize = dialog.Font.Size;

        UpdateNotesText();
        SaveState();
    }

    private void ConfigureNoteFontSize()
    {
        if (!TryPrompt("便签字号", "请输入便签字号（10~132）", _state.Notes.FontSize.ToString("0"), out string value))
        {
            return;
        }

        if (!double.TryParse(value, out double fontSize) || fontSize < 10 || fontSize > 132)
        {
            WpfMessageBox.Show(this, "请输入 10~132 的数字。", "输入无效", MessageBoxButton.OK, MessageBoxImage.Warning);
            return;
        }

        _state.Notes.FontSize = fontSize;
        UpdateNotesText();
        SaveState();
    }

    private void ConfigureNotesTextColor()
    {
        if (!TrySelectColor("选择便签文字颜色", _state.App.NotesTextColor, out string colorHex))
        {
            return;
        }

        _state.App.NotesTextColor = colorHex;
        ApplyTextAppearance();
        SaveState();
    }

    private void ConfigureBackgroundColor()
    {
        if (!TrySelectColor("选择背景主色", _state.App.BackgroundColor, out string colorHex))
        {
            return;
        }

        _state.App.BackgroundColor = colorHex;
        ApplyVisualEffects();
        SaveState();
    }

    private void ToggleNoteRotation(bool enabled)
    {
        _state.Notes.EnableRotation = enabled;
        ConfigureNoteRotationTimer();
        SaveState();
    }

    private void ConfigureRotationSeconds()
    {
        if (!TryPrompt("便签切换", "请输入切换间隔秒数（>=2）", _state.Notes.RotationSeconds.ToString(), out string value))
        {
            return;
        }

        if (!int.TryParse(value, out int seconds) || seconds < 2)
        {
            WpfMessageBox.Show(this, "请输入大于等于 2 的整数秒数。", "输入无效", MessageBoxButton.OK, MessageBoxImage.Warning);
            return;
        }

        _state.Notes.RotationSeconds = seconds;
        ConfigureNoteRotationTimer();
        SaveState();
    }

    private void ToggleTopMost(bool enabled)
    {
        _state.App.TopMost = enabled;
        Topmost = enabled;
        SaveState();
    }

    private void ToggleFixedMode(bool enabled)
    {
        _state.App.FixedMode = enabled;
        ResizeMode = enabled ? ResizeMode.NoResize : ResizeMode.CanResizeWithGrip;
        ApplyVisualEffects();
        ApplyResponsiveLayout();
        SaveState();
    }

    private void ToggleAutoStart(bool enabled)
    {
        try
        {
            SetAutoStart(enabled);
            _state.App.AutoStart = enabled;
            SaveState();
        }
        catch (UnauthorizedAccessException ex)
        {
            if (_autoStartItem is not null)
            {
                SetMenuChecked(_autoStartItem, !enabled);
            }
            _configService.AppendLog($"开机自启动设置失败: {ex.Message}");
            WpfMessageBox.Show(this, "当前权限不足，无法设置开机自启动。", "权限不足", MessageBoxButton.OK, MessageBoxImage.Warning);
        }
    }

    private void ToggleMinimizeToTrayOnClose(bool enabled)
    {
        _state.App.MinimizeToTrayOnClose = enabled;
        SaveState();
    }

    private void OpenConfigDirectory()
    {
        _ = Process.Start(new ProcessStartInfo
        {
            FileName = _configService.ConfigDirectory,
            UseShellExecute = true
        });
    }

    private void OpenGithubRepository()
    {
        try
        {
            _ = Process.Start(new ProcessStartInfo
            {
                FileName = RepositoryUrl,
                UseShellExecute = true
            });
            _configService.AppendLog($"已打开仓库: {RepositoryUrl}");
        }
        catch (Win32Exception ex)
        {
            _configService.AppendLog($"打开仓库失败: {ex.Message}");
        }
        catch (InvalidOperationException ex)
        {
            _configService.AppendLog($"打开仓库失败: {ex.Message}");
        }
    }

    private void ExitApplication()
    {
        _isExiting = true;
        SaveState();
        Close();
        WpfApplication.Current.Shutdown();
    }

    private void NoteRotationTimer_Tick(object? sender, EventArgs e)
    {
        if (!_state.Notes.EnableRotation || _state.NotesContent.Segments.Count <= 1)
        {
            return;
        }

        _state.NotesContent.CurrentIndex = (_state.NotesContent.CurrentIndex + 1) % _state.NotesContent.Segments.Count;
        UpdateNotesText();
        SaveState();
    }

    private void ConfigureNoteRotationTimer()
    {
        _noteRotationTimer.Stop();
        _noteRotationTimer.Interval = TimeSpan.FromSeconds(Math.Max(2, _state.Notes.RotationSeconds));

        if (_state.Notes.EnableRotation && _state.NotesContent.Segments.Count > 1)
        {
            _noteRotationTimer.Start();
        }
    }

    private void MemoryGuardTimer_Tick(object? sender, EventArgs e)
    {
        if (_isExiting)
        {
            return;
        }

        Process process = Process.GetCurrentProcess();
        long workingSet = process.WorkingSet64;
        long privateBytes = process.PrivateMemorySize64;
        if (workingSet < MemoryTrimWorkingSetThresholdBytes && privateBytes < MemoryTrimPrivateThresholdBytes)
        {
            return;
        }

        if ((DateTime.UtcNow - _lastMemoryTrimUtc) < TimeSpan.FromSeconds(12))
        {
            return;
        }

        _lastMemoryTrimUtc = DateTime.UtcNow;
        if (!_memoryPressureMode)
        {
            _memoryPressureMode = true;
            ApplyVisualEffects();
        }

        TrimMemoryUsage();
    }

    private void LoadWindowIcon()
    {
        try
        {
            Stream? embeddedStream = TryOpenEmbeddedResource(DefaultIconFileName);
            if (embeddedStream is not null)
            {
                using (embeddedStream)
                {
                    var decoder = new IconBitmapDecoder(
                        embeddedStream,
                        BitmapCreateOptions.None,
                        BitmapCacheOption.OnLoad);
                    if (decoder.Frames.Count > 0)
                    {
                        Icon = decoder.Frames[0];
                        return;
                    }
                }
            }

            string iconPath = Path.Combine(AppContext.BaseDirectory, DefaultIconFileName);
            if (File.Exists(iconPath))
            {
                var fileDecoder = new IconBitmapDecoder(
                    new Uri(iconPath),
                    BitmapCreateOptions.None,
                    BitmapCacheOption.OnLoad);
                if (fileDecoder.Frames.Count > 0)
                {
                    Icon = fileDecoder.Frames[0];
                }
            }
        }
        catch (Exception ex)
        {
            _configService.AppendLog($"窗口图标加载失败: {ex.Message}");
        }
    }

    private Drawing.Icon LoadTrayIcon()
    {
        try
        {
            Stream? embeddedStream = TryOpenEmbeddedResource(DefaultIconFileName);
            if (embeddedStream is not null)
            {
                using (embeddedStream)
                using (var icon = new Drawing.Icon(embeddedStream))
                {
                    return (Drawing.Icon)icon.Clone();
                }
            }

            string iconPath = Path.Combine(AppContext.BaseDirectory, DefaultIconFileName);
            if (File.Exists(iconPath))
            {
                return new Drawing.Icon(iconPath);
            }
        }
        catch (Exception ex)
        {
            _configService.AppendLog($"托盘图标加载失败: {ex.Message}");
        }

        return Drawing.SystemIcons.Application;
    }

    private static Stream? TryOpenEmbeddedResource(string fileName)
    {
        string? resourceName = typeof(MainWindow)
            .Assembly
            .GetManifestResourceNames()
            .FirstOrDefault(x => x.EndsWith(fileName, StringComparison.OrdinalIgnoreCase));

        if (string.IsNullOrWhiteSpace(resourceName))
        {
            return null;
        }

        return typeof(MainWindow).Assembly.GetManifestResourceStream(resourceName);
    }

    private void ApplyStateToUi()
    {
        Topmost = _state.App.TopMost;
        Width = Math.Clamp(_state.App.WindowWidth, 140, 960);
        Height = Math.Clamp(_state.App.WindowHeight, 88, 720);
        ResizeMode = _state.App.FixedMode ? ResizeMode.NoResize : ResizeMode.CanResizeWithGrip;

        ApplyTextAppearance();
        UpdateNotesText();
        ApplyResponsiveLayout();
    }

    private void ApplyVisualEffects()
    {
        double transparencyPercent = Math.Clamp(_state.App.Transparency, 0, 100);
        if (Math.Abs(_lastAppliedTransparencyPercent - transparencyPercent) > 0.001)
        {
            _lastAppliedTransparencyPercent = transparencyPercent;
            _configService.AppendLog($"视觉渲染模式: CompatibilityLayered, transparency={transparencyPercent:0}%");
        }

        double opacityRatio = 1.0 - (transparencyPercent / 100.0);
        opacityRatio = Math.Clamp(opacityRatio, 0.0, 1.0);

        Background = MediaBrushes.Transparent;
        AppleEdgeOverlay.Visibility = Visibility.Collapsed;
        MaterialOverlay.Visibility = Visibility.Collapsed;
        PanelBackground.Effect = null;

        if (_state.App.FixedMode)
        {
            PanelBackground.Background = MediaBrushes.Transparent;
            PanelBackground.BorderBrush = MediaBrushes.Transparent;
            RootBorder.Effect = null;
            return;
        }

        if (_memoryPressureMode)
        {
            RootBorder.Effect = null;
        }
        else
        {
            RootBorder.Effect = new DropShadowEffect
            {
                BlurRadius = 24,
                ShadowDepth = 0,
                Opacity = 0.24,
                Color = Color.FromArgb(140, 0, 0, 0)
            };
        }

        Color baseColor = ParseMediaColor(_state.App.BackgroundColor, Color.FromRgb(255, 255, 255));
        if (_memoryPressureMode)
        {
            ApplyFrostedMode(baseColor, opacityRatio);
            PanelBackground.Effect = null;
            return;
        }

        switch (_state.App.BackgroundEffect)
        {
            case "Apple":
                ApplyAppleMode(baseColor, opacityRatio);
                break;
            case "Blur":
                ApplyBlurMode(baseColor, opacityRatio);
                break;
            default:
                ApplyFrostedMode(baseColor, opacityRatio);
                break;
        }
    }

    private void ApplyFrostedMode(Color baseColor, double opacityRatio)
    {
        Color top = BlendColor(baseColor, Color.FromRgb(255, 255, 255), 0.68);
        Color middle = BlendColor(baseColor, Color.FromRgb(237, 244, 252), 0.50);
        Color bottom = BlendColor(baseColor, Color.FromRgb(214, 226, 241), 0.22);

        byte aTop = (byte)Math.Clamp((int)(opacityRatio * 230), 0, 230);
        byte aMid = (byte)Math.Clamp((int)(opacityRatio * 198), 0, 198);
        byte aBottom = (byte)Math.Clamp((int)(opacityRatio * 174), 0, 174);
        byte borderAlpha = (byte)Math.Clamp((int)(opacityRatio * 205), 0, 220);

        var fill = new LinearGradientBrush
        {
            StartPoint = new MediaPoint(0, 0),
            EndPoint = new MediaPoint(0, 1)
        };
        fill.GradientStops.Add(new GradientStop(Color.FromArgb(aTop, top.R, top.G, top.B), 0.0));
        fill.GradientStops.Add(new GradientStop(Color.FromArgb(aMid, middle.R, middle.G, middle.B), 0.52));
        fill.GradientStops.Add(new GradientStop(Color.FromArgb(aBottom, bottom.R, bottom.G, bottom.B), 1.0));

        PanelBackground.Background = fill;
        PanelBackground.BorderBrush = new SolidColorBrush(Color.FromArgb(borderAlpha, 247, 251, 255));

        var overlay = new LinearGradientBrush
        {
            StartPoint = new MediaPoint(0, 0),
            EndPoint = new MediaPoint(1, 1)
        };
        overlay.GradientStops.Add(new GradientStop(Color.FromArgb((byte)Math.Clamp((int)(opacityRatio * 95), 0, 95), 255, 255, 255), 0.0));
        overlay.GradientStops.Add(new GradientStop(Color.FromArgb((byte)Math.Clamp((int)(opacityRatio * 40), 0, 40), 233, 242, 252), 0.48));
        overlay.GradientStops.Add(new GradientStop(Color.FromArgb((byte)Math.Clamp((int)(opacityRatio * 72), 0, 72), 196, 213, 233), 1.0));
        MaterialOverlay.Background = overlay;
        MaterialOverlay.Visibility = Visibility.Visible;
    }

    private void ApplyBlurMode(Color baseColor, double opacityRatio)
    {
        Color top = BlendColor(baseColor, Color.FromRgb(255, 255, 255), 0.75);
        Color middle = BlendColor(baseColor, Color.FromRgb(232, 241, 252), 0.46);
        Color bottom = BlendColor(baseColor, Color.FromRgb(197, 213, 232), 0.28);

        byte aTop = (byte)Math.Clamp((int)(opacityRatio * 214), 0, 214);
        byte aMid = (byte)Math.Clamp((int)(opacityRatio * 186), 0, 186);
        byte aBottom = (byte)Math.Clamp((int)(opacityRatio * 164), 0, 164);
        byte borderAlpha = (byte)Math.Clamp((int)(opacityRatio * 212), 0, 220);

        var fill = new LinearGradientBrush
        {
            StartPoint = new MediaPoint(0, 0),
            EndPoint = new MediaPoint(0, 1)
        };
        fill.GradientStops.Add(new GradientStop(Color.FromArgb(aTop, top.R, top.G, top.B), 0.0));
        fill.GradientStops.Add(new GradientStop(Color.FromArgb(aMid, middle.R, middle.G, middle.B), 0.56));
        fill.GradientStops.Add(new GradientStop(Color.FromArgb(aBottom, bottom.R, bottom.G, bottom.B), 1.0));

        PanelBackground.Background = fill;
        PanelBackground.BorderBrush = new SolidColorBrush(Color.FromArgb(borderAlpha, 250, 253, 255));
        PanelBackground.Effect = new BlurEffect
        {
            Radius = Math.Clamp((12 * opacityRatio) + 5, 3, 20)
        };

        var overlay = new RadialGradientBrush
        {
            Center = new MediaPoint(0.28, 0.18),
            GradientOrigin = new MediaPoint(0.28, 0.18),
            RadiusX = 1.05,
            RadiusY = 1.05
        };
        overlay.GradientStops.Add(new GradientStop(Color.FromArgb((byte)Math.Clamp((int)(opacityRatio * 110), 0, 110), 255, 255, 255), 0.0));
        overlay.GradientStops.Add(new GradientStop(Color.FromArgb((byte)Math.Clamp((int)(opacityRatio * 42), 0, 42), 242, 248, 255), 0.58));
        overlay.GradientStops.Add(new GradientStop(Color.FromArgb((byte)Math.Clamp((int)(opacityRatio * 88), 0, 88), 188, 205, 224), 1.0));
        MaterialOverlay.Background = overlay;
        MaterialOverlay.Visibility = Visibility.Visible;
    }

    private void ApplyAppleMode(Color baseColor, double opacityRatio)
    {
        byte edgeAlpha = (byte)Math.Clamp((int)(opacityRatio * 210), 0, 210);
        byte borderAlpha = (byte)Math.Clamp((int)(opacityRatio * 198), 0, 220);

        PanelBackground.Background = MediaBrushes.Transparent;
        PanelBackground.BorderBrush = new SolidColorBrush(Color.FromArgb(borderAlpha, 239, 246, 255));

        var edgeBrush = new RadialGradientBrush
        {
            Center = new MediaPoint(0.5, 0.5),
            GradientOrigin = new MediaPoint(0.5, 0.5),
            RadiusX = 0.85,
            RadiusY = 0.85
        };
        edgeBrush.GradientStops.Add(new GradientStop(Color.FromArgb(0, baseColor.R, baseColor.G, baseColor.B), 0.45));
        edgeBrush.GradientStops.Add(new GradientStop(Color.FromArgb((byte)(edgeAlpha / 2), baseColor.R, baseColor.G, baseColor.B), 0.72));
        edgeBrush.GradientStops.Add(new GradientStop(Color.FromArgb(edgeAlpha, baseColor.R, baseColor.G, baseColor.B), 1.0));

        AppleEdgeOverlay.Background = edgeBrush;
        AppleEdgeOverlay.Visibility = Visibility.Visible;
    }

    private static Color BlendColor(Color source, Color target, double ratio)
    {
        double clamped = Math.Clamp(ratio, 0, 1);
        byte r = (byte)Math.Clamp((int)Math.Round(source.R + ((target.R - source.R) * clamped)), 0, 255);
        byte g = (byte)Math.Clamp((int)Math.Round(source.G + ((target.G - source.G) * clamped)), 0, 255);
        byte b = (byte)Math.Clamp((int)Math.Round(source.B + ((target.B - source.B) * clamped)), 0, 255);
        return Color.FromRgb(r, g, b);
    }

    private static double QuantizeFontSize(double value)
    {
        return Math.Round(value);
    }

    private void ApplyResponsiveLayout()
    {
        if (ActualWidth <= 0 || ActualHeight <= 0)
        {
            return;
        }

        double widthScale = ActualWidth / 380.0;
        double heightScale = ActualHeight / 210.0;
        double scale = Math.Clamp(Math.Max(widthScale, heightScale), 0.40, 4.20);

        NotesDisplayText.FontSize = QuantizeFontSize(Math.Clamp(_state.Notes.FontSize * scale, 10, 132));
        NotesDisplayText.Margin = new Thickness(10);
    }

    private void UpdateNotesText()
    {
        if (_state.NotesContent.Segments.Count == 0)
        {
            _state.NotesContent.Segments.Add(DefaultNoteText);
            _state.NotesContent.CurrentIndex = 0;
        }

        if (_state.NotesContent.CurrentIndex >= _state.NotesContent.Segments.Count)
        {
            _state.NotesContent.CurrentIndex = 0;
        }

        string raw = _state.NotesContent.Segments[_state.NotesContent.CurrentIndex] ?? string.Empty;
        ApplyNotesLayoutRules(raw);
        ApplyTextAppearance();
        ApplyResponsiveLayout();
    }

    private void ApplyNotesLayoutRules(string rawText)
    {
        string normalized = rawText.Replace("\r\n", "\n").Replace('\r', '\n');
        List<string> lines = normalized
            .Split('\n')
            .Select(line => line.TrimEnd())
            .Where(line => !string.IsNullOrWhiteSpace(line))
            .ToList();

        if (lines.Count <= 1)
        {
            NotesDisplayText.TextAlignment = TextAlignment.Center;
            NotesDisplayText.Text = lines.Count == 0 ? string.Empty : lines[0].Trim();
            return;
        }

        NotesDisplayText.TextAlignment = TextAlignment.Left;
        string firstLine = $"　　{lines[0].TrimStart()}";
        IEnumerable<string> remain = lines.Skip(1).Select(x => x.TrimStart());
        NotesDisplayText.Text = string.Join(Environment.NewLine, new[] { firstLine }.Concat(remain));
    }

    private void ApplyTextAppearance()
    {
        NotesDisplayText.FontFamily = ResolveFontFamily(_state.Notes.FontFamily);
        NotesDisplayText.Foreground = new SolidColorBrush(ParseMediaColor(_state.App.NotesTextColor, Color.FromRgb(255, 182, 193)));
    }

    private static FontFamily ResolveFontFamily(string requested)
    {
        if (!string.IsNullOrWhiteSpace(requested))
        {
            try
            {
                return new FontFamily(requested);
            }
            catch (ArgumentException)
            {
                // Keep fallback below.
            }
        }

        FontFamily? matched = Fonts.SystemFontFamilies
            .FirstOrDefault(f => string.Equals(f.Source, requested, StringComparison.OrdinalIgnoreCase));
        return matched ?? new FontFamily("KaiTi");
    }

    private static Color ParseMediaColor(string colorText, Color fallback)
    {
        if (!TryParseHexColor(colorText, out Color parsed))
        {
            return fallback;
        }

        return parsed;
    }

    private static Drawing.Color ParseDrawingColor(string colorText, Drawing.Color fallback)
    {
        Color media = ParseMediaColor(colorText, Color.FromRgb(fallback.R, fallback.G, fallback.B));
        return Drawing.Color.FromArgb(media.R, media.G, media.B);
    }

    private static string ToHexColor(Drawing.Color color)
    {
        return $"#{color.R:X2}{color.G:X2}{color.B:X2}";
    }

    private static bool TryParseHexColor(string? colorText, out Color color)
    {
        color = Color.FromRgb(0, 0, 0);
        if (string.IsNullOrWhiteSpace(colorText))
        {
            return false;
        }

        string value = colorText.Trim();
        if (value.Length != 7 || value[0] != '#')
        {
            return false;
        }

        bool parsedR = byte.TryParse(value.Substring(1, 2), System.Globalization.NumberStyles.HexNumber, provider: null, out byte r);
        bool parsedG = byte.TryParse(value.Substring(3, 2), System.Globalization.NumberStyles.HexNumber, provider: null, out byte g);
        bool parsedB = byte.TryParse(value.Substring(5, 2), System.Globalization.NumberStyles.HexNumber, provider: null, out byte b);
        if (!parsedR || !parsedG || !parsedB)
        {
            return false;
        }

        color = Color.FromRgb(r, g, b);
        return true;
    }

    private bool TrySelectColor(string title, string currentHex, out string selectedHex)
    {
        using var dialog = new WinForms.ColorDialog
        {
            FullOpen = true,
            AnyColor = true,
            SolidColorOnly = false,
            Color = ParseDrawingColor(currentHex, Drawing.Color.FromArgb(76, 109, 140))
        };

        if (dialog.ShowDialog() != WinForms.DialogResult.OK)
        {
            selectedHex = currentHex;
            return false;
        }

        selectedHex = ToHexColor(dialog.Color);
        _configService.AppendLog($"{title}: {selectedHex}");
        return true;
    }

    private bool TryPrompt(string title, string prompt, string defaultValue, out string value)
    {
        var dialog = new InputDialog(title, prompt, defaultValue)
        {
            Owner = this
        };
        bool? result = dialog.ShowDialog();
        value = dialog.Value;
        return result == true;
    }

    private void SaveState()
    {
        _state.App.TopMost = Topmost;
        _state.App.WindowWidth = (int)Width;
        _state.App.WindowHeight = (int)Height;
        _configService.Save(_state);
    }

    private static string GetCurrentExePath()
    {
        return Process.GetCurrentProcess().MainModule?.FileName ?? string.Empty;
    }

    private static bool IsPathMatch(string left, string right)
    {
        string normalizedLeft = NormalizePathForCompare(left);
        string normalizedRight = NormalizePathForCompare(right);
        return string.Equals(normalizedLeft, normalizedRight, StringComparison.OrdinalIgnoreCase);
    }

    private static string NormalizePathForCompare(string path)
    {
        string trimmed = path.Trim().Trim('"');
        if (string.IsNullOrWhiteSpace(trimmed))
        {
            return string.Empty;
        }

        try
        {
            return Path.GetFullPath(trimmed);
        }
        catch (ArgumentException)
        {
            return trimmed;
        }
        catch (NotSupportedException)
        {
            return trimmed;
        }
        catch (PathTooLongException)
        {
            return trimmed;
        }
    }

    private bool IsAutoStartEnabled()
    {
        using RegistryKey? key = Registry.CurrentUser.OpenSubKey(RunKeyPath);
        string? configuredPath = key?.GetValue(RunValueName) as string;
        if (string.IsNullOrWhiteSpace(configuredPath))
        {
            return false;
        }

        return IsPathMatch(configuredPath, GetCurrentExePath());
    }

    private void SetAutoStart(bool enabled)
    {
        using RegistryKey? key = Registry.CurrentUser.CreateSubKey(RunKeyPath, writable: true);
        if (key is null)
        {
            throw new UnauthorizedAccessException("无法打开启动项注册表键。");
        }

        if (enabled)
        {
            key.SetValue(RunValueName, $"\"{GetCurrentExePath()}\"");
            return;
        }

        key.DeleteValue(RunValueName, throwOnMissingValue: false);
    }

    private void DispatchToUi(Action action)
    {
        if (Dispatcher.CheckAccess())
        {
            action();
            return;
        }

        Dispatcher.Invoke(action);
    }

    private void SetMenuChecked(WinForms.ToolStripMenuItem menuItem, bool value)
    {
        if (menuItem.Checked == value)
        {
            return;
        }

        _suppressCheckCallbacks = true;
        try
        {
            menuItem.Checked = value;
        }
        finally
        {
            _suppressCheckCallbacks = false;
        }
    }

    private void SuspendWindowForTray()
    {
        if (_suspendedForTray)
        {
            return;
        }

        _suspendedForTray = true;
        _noteRotationRunningBeforeSuspend = _noteRotationTimer.IsEnabled;
        _noteRotationTimer.Stop();

        RootBorder.Effect = null;
        PanelBackground.Effect = null;
        PanelBackground.Background = MediaBrushes.Transparent;
        PanelBackground.BorderBrush = MediaBrushes.Transparent;
        AppleEdgeOverlay.Background = null;
        AppleEdgeOverlay.Visibility = Visibility.Collapsed;
        MaterialOverlay.Background = null;
        MaterialOverlay.Visibility = Visibility.Collapsed;

        TrimMemoryUsage();
    }

    private void ResumeWindowFromTray()
    {
        if (!_suspendedForTray)
        {
            return;
        }

        _suspendedForTray = false;
        if (_noteRotationRunningBeforeSuspend)
        {
            ConfigureNoteRotationTimer();
        }
    }

    private void TrimMemoryUsage()
    {
        GCSettings.LargeObjectHeapCompactionMode = GCLargeObjectHeapCompactionMode.CompactOnce;
        GC.Collect(2, GCCollectionMode.Forced, blocking: true, compacting: true);
        GC.WaitForPendingFinalizers();
        GC.Collect(2, GCCollectionMode.Forced, blocking: true, compacting: true);

        IntPtr handle = Process.GetCurrentProcess().Handle;
        bool trimmed = EmptyWorkingSet(handle);
        if (!trimmed)
        {
            int errorCode = Marshal.GetLastWin32Error();
            _configService.AppendLog($"工作集收缩失败: {errorCode}");
        }
    }

    private void DisposeTrayIcon()
    {
        _memoryGuardTimer.Stop();
        _memoryGuardTimer.Tick -= MemoryGuardTimer_Tick;

        if (_notifyIcon is not null)
        {
            _notifyIcon.Visible = false;
            _notifyIcon.Dispose();
            _notifyIcon = null;
        }

        _trayIcon?.Dispose();
        _trayIcon = null;
    }
}
