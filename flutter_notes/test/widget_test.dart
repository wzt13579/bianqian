import 'package:flutter_test/flutter_test.dart';

import 'package:mi_notes_flutter/ui/theme/note_colors.dart';

void main() {
  test('NoteColors palette count', () {
    expect(NoteColors.palettes.length, 5);
  });
}
