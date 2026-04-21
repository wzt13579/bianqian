import 'package:flutter/material.dart';

/// 5 sticky-note color palettes that mimic the original Mi Notes app.
class NoteColorPalette {
  final String name;
  final Color paper;       // body background
  final Color paperDark;   // header strip on cards
  final Color accent;      // active accent
  final Color text;

  const NoteColorPalette({
    required this.name,
    required this.paper,
    required this.paperDark,
    required this.accent,
    required this.text,
  });
}

class NoteColors {
  static const List<NoteColorPalette> palettes = [
    NoteColorPalette(
      name: '黄',
      paper: Color(0xFFFFF6C7),
      paperDark: Color(0xFFFFE981),
      accent: Color(0xFFE0B400),
      text: Color(0xFF3A2E00),
    ),
    NoteColorPalette(
      name: '蓝',
      paper: Color(0xFFD7ECFF),
      paperDark: Color(0xFFB7D9FB),
      accent: Color(0xFF1E88E5),
      text: Color(0xFF0D2A4A),
    ),
    NoteColorPalette(
      name: '白',
      paper: Color(0xFFFAFAFA),
      paperDark: Color(0xFFE9E9E9),
      accent: Color(0xFF616161),
      text: Color(0xFF202020),
    ),
    NoteColorPalette(
      name: '绿',
      paper: Color(0xFFDDF3D6),
      paperDark: Color(0xFFB9E4AB),
      accent: Color(0xFF2E7D32),
      text: Color(0xFF18331A),
    ),
    NoteColorPalette(
      name: '红',
      paper: Color(0xFFFFD7D2),
      paperDark: Color(0xFFFFB6AC),
      accent: Color(0xFFC62828),
      text: Color(0xFF4A1010),
    ),
  ];

  static NoteColorPalette of(int index) {
    if (index < 0 || index >= palettes.length) return palettes[0];
    return palettes[index];
  }
}
