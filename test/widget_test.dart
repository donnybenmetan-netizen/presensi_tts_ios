import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:presensi_tts/main.dart';

void main() {
  testWidgets('Presensi page renders basic UI', (WidgetTester tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: PresensiGuruTTS(),
      ),
    );

    expect(find.text('PRESENSI GURU TTS'), findsOneWidget);
    expect(find.text('Silakan cari nama Anda pada kotak di atas.'), findsOneWidget);
    expect(find.byType(Autocomplete<Map<String, String>>), findsOneWidget);
  });
}