import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_application_1/features/dashboard/models/note_model.dart';
import 'package:flutter_application_1/features/dashboard/widgets/sidebar.dart';

void main() {
  testWidgets('saved notes show their retained note date', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Sidebar(
            recentFiles: [
              RecentFile(
                path: 'note_synthetic',
                fullPath: 'D:/synthetic/note_synthetic',
                title: 'Synthetic note',
                created: DateTime(2024, 1, 15),
                modified: DateTime(2024, 2, 20),
              ),
            ],
            onFileSelected: (_) {},
            onOpenFolder: (_) {},
            onDelete: (_) {},
            onNewNote: () {},
          ),
        ),
      ),
    );

    expect(find.text('Synthetic note'), findsOneWidget);
    expect(find.text('Note date 15 Jan 2024'), findsOneWidget);
  });

  testWidgets('missing retained date does not invent one', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Sidebar(
            recentFiles: [
              RecentFile(
                path: 'legacy',
                fullPath: 'D:/synthetic/legacy',
                title: 'Legacy note',
                modified: DateTime(2024, 2, 20),
              ),
            ],
            onFileSelected: (_) {},
            onOpenFolder: (_) {},
            onDelete: (_) {},
            onNewNote: () {},
          ),
        ),
      ),
    );

    expect(find.textContaining('Note date'), findsNothing);
  });
}
