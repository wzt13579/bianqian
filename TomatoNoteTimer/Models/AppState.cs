using System.Collections.Generic;
using System.Text.RegularExpressions;

namespace TomatoNoteTimer.Models;

public sealed class AppState
{
    private const string DefaultNoteText = "人生若只如初见，何事秋风悲画扇";
    private const string DefaultNotesColor = "#FFB6C1";

    public AppSettings App { get; set; } = new();
    public NotesSettings Notes { get; set; } = new();
    public NotesContent NotesContent { get; set; } = new();

    public void Normalize()
    {
        App = App ?? new AppSettings();
        Notes = Notes ?? new NotesSettings();
        NotesContent = NotesContent ?? new NotesContent();

        if (Notes.FontSize < 10)
        {
            Notes.FontSize = 24;
        }

        if (Notes.RotationSeconds < 2)
        {
            Notes.RotationSeconds = 8;
        }

        if (App.WindowWidth < 140)
        {
            App.WindowWidth = 380;
        }

        if (App.WindowHeight < 88)
        {
            App.WindowHeight = 210;
        }

        App.Hotkeys = App.Hotkeys ?? new HotkeySettings();
        App.Hotkeys.Normalize();

        // Backward compatibility: old versions stored opacity in [0,1].
        if (App.Transparency >= 0 && App.Transparency <= 1.0)
        {
            App.Transparency = (1.0 - App.Transparency) * 100.0;
        }

        if (App.Transparency < 0 || App.Transparency > 100)
        {
            App.Transparency = 20;
        }
        App.Transparency = System.Math.Round(App.Transparency, 0);

        // Migrate previous default profile to the new default profile.
        if (string.Equals(App.BackgroundColor, "#4C6D8C", System.StringComparison.OrdinalIgnoreCase) &&
            System.Math.Abs(App.Transparency - 18) < 0.1)
        {
            App.BackgroundColor = "#FFFFFF";
            App.Transparency = 20;
        }

        App.BackgroundEffect = NormalizeEffectMode(App.BackgroundEffect);
        App.BackgroundColor = NormalizeHexColor(App.BackgroundColor, "#FFFFFF");
        App.NotesTextColor = NormalizeHexColor(App.NotesTextColor, DefaultNotesColor);

        if (string.IsNullOrWhiteSpace(Notes.FontFamily) ||
            string.Equals(Notes.FontFamily, "Microsoft YaHei UI", System.StringComparison.OrdinalIgnoreCase))
        {
            Notes.FontFamily = "KaiTi";
        }

        if (NotesContent.Segments is null || NotesContent.Segments.Count == 0)
        {
            NotesContent.Segments = new List<string> { DefaultNoteText };
        }

        if (NotesContent.CurrentIndex < 0 || NotesContent.CurrentIndex >= NotesContent.Segments.Count)
        {
            NotesContent.CurrentIndex = 0;
        }
    }

    private static string NormalizeEffectMode(string? mode)
    {
        return mode?.Trim().ToLowerInvariant() switch
        {
            "blur" => "Blur",
            "frosted" => "Frosted",
            "apple" => "Apple",
            _ => "Blur"
        };
    }

    private static string NormalizeHexColor(string? color, string fallback)
    {
        if (string.IsNullOrWhiteSpace(color))
        {
            return fallback;
        }

        string normalized = color.Trim();
        if (Regex.IsMatch(normalized, "^#[0-9a-fA-F]{6}$"))
        {
            return normalized.ToUpperInvariant();
        }

        if (Regex.IsMatch(normalized, "^#[0-9a-fA-F]{8}$"))
        {
            return $"#{normalized.Substring(3, 6).ToUpperInvariant()}";
        }

        return fallback;
    }
}

public sealed class AppSettings
{
    public bool TopMost { get; set; } = true;
    public bool FixedMode { get; set; }
    // 0 = fully opaque, 100 = fully transparent
    public double Transparency { get; set; } = 20;
    public int WindowWidth { get; set; } = 380;
    public int WindowHeight { get; set; } = 210;
    public bool MinimizeToTrayOnClose { get; set; } = true;
    public bool AutoStart { get; set; }
    public string BackgroundEffect { get; set; } = "Blur";
    public string BackgroundColor { get; set; } = "#FFFFFF";
    public string NotesTextColor { get; set; } = "#FFB6C1";
    public HotkeySettings Hotkeys { get; set; } = new();
}

public sealed class NotesSettings
{
    public string FontFamily { get; set; } = "KaiTi";
    public double FontSize { get; set; } = 24;
    public bool EnableRotation { get; set; }
    public int RotationSeconds { get; set; } = 8;
}

public sealed class NotesContent
{
    public List<string> Segments { get; set; } = new() { "人生若只如初见，何事秋风悲画扇" };
    public int CurrentIndex { get; set; }
}

public sealed class HotkeySettings
{
    public string ToggleTopMost { get; set; } = string.Empty;
    public string ToggleFixedMode { get; set; } = string.Empty;
    public string ToggleVisibility { get; set; } = string.Empty;
    public string NextNote { get; set; } = string.Empty;
    public string PrevNote { get; set; } = string.Empty;

    public void Normalize()
    {
        ToggleTopMost = NormalizeValue(ToggleTopMost);
        ToggleFixedMode = NormalizeValue(ToggleFixedMode);
        ToggleVisibility = NormalizeValue(ToggleVisibility);
        NextNote = NormalizeValue(NextNote);
        PrevNote = NormalizeValue(PrevNote);
    }

    private static string NormalizeValue(string? value)
    {
        return string.IsNullOrWhiteSpace(value) ? string.Empty : value.Trim();
    }
}
