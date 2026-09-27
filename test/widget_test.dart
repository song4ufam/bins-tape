import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bins_tape/main.dart';

void main() {
  testWidgets("Bin's Tape shows the music player screen",
      (WidgetTester tester) async {
    await tester.pumpWidget(const BinsTapeApp());
    await tester.pump();

    expect(find.byType(MusicPlayerScreen), findsOneWidget);
    expect(find.byType(SyncLyricsView), findsOneWidget);
  });
}
