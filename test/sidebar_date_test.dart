import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_application_1/features/dashboard/models/note_model.dart';
import 'package:flutter_application_1/features/dashboard/models/note_list_ui_state.dart';
import 'package:flutter_application_1/features/dashboard/widgets/sidebar.dart';

void main() {
  testWidgets('unlocked row retains its icon after selecting another note', (
    tester,
  ) async {
    final files = [
      RecentFile(
        path: 'note_same',
        fullPath: 'D:/first/note_same/content.json',
        title: 'Same title',
        isLocked: true,
      ),
      RecentFile(
        path: 'note_same',
        fullPath: 'D:/second/note_same/content.json',
        title: 'Same title',
        isLocked: true,
      ),
    ];
    for (final remembered in [true, false]) {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Sidebar(
              listState: NoteListUiState(
                files: files,
                selectedContentPath: files.last.fullPath,
                selectedLockState: NoteLockState.locked,
                unlockedContentPaths: remembered
                    ? {files.first.fullPath}
                    : const {},
              ),
              onFileSelected: (_) {},
              onOpenFolder: (_) {},
              onDelete: (_) {},
              onNewNote: () {},
            ),
          ),
        ),
      );
      final first = tester.widget<ListTile>(
        find.byKey(ValueKey(files.first.fullPath)),
      );
      final second = tester.widget<ListTile>(
        find.byKey(ValueKey(files.last.fullPath)),
      );
      expect(
        (first.leading as Icon).icon,
        remembered ? Icons.lock_open_rounded : Icons.lock_rounded,
      );
      expect((second.leading as Icon).icon, Icons.lock_rounded);
    }
  });

  testWidgets(
    'selected note shows its live lock state without changing other rows',
    (tester) async {
      final files = [
        RecentFile(
          path: 'note_same',
          fullPath: 'D:/first/note_same/content.json',
          title: 'Same title',
          isLocked: true,
        ),
        RecentFile(
          path: 'note_same',
          fullPath: 'D:/second/note_same/content.json',
          title: 'Same title',
          isLocked: true,
        ),
      ];
      for (final state in [null, ...NoteLockState.values]) {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Sidebar(
                listState: NoteListUiState(
                  files: files,
                  selectedContentPath: files.first.fullPath,
                  selectedLockState: state,
                ),
                onFileSelected: (_) {},
                onOpenFolder: (_) {},
                onDelete: (_) {},
                onNewNote: () {},
              ),
            ),
          ),
        );
        expect(
          find.byIcon(Icons.lock_rounded),
          findsNWidgets(state == null || state == NoteLockState.locked ? 2 : 1),
        );
        expect(
          find.byIcon(Icons.lock_open_rounded),
          state == NoteLockState.unlocked ? findsOneWidget : findsNothing,
        );
        expect(
          find.byIcon(Icons.description_outlined),
          state == NoteLockState.unprotected ? findsOneWidget : findsNothing,
        );
        expect(files.every((file) => file.isLocked), isTrue);
      }
    },
  );

  testWidgets('saved notes show last modified date, time and persistent ID', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Sidebar(
            recentFiles: [
              RecentFile(
                path: 'note_synthetic',
                fullPath: 'D:/synthetic/note_synthetic',
                title: 'Synthetic note',
                noteId: 'persistent-a1b2c',
                isLocked: true,
                created: DateTime(2024, 1, 15, 14, 5),
                modified: DateTime(2024, 2, 20, 16, 7),
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
    expect(find.text('20/02/24 16:07 • a1b2c'), findsOneWidget);
    expect(find.textContaining('15/01/24'), findsNothing);
    expect(find.byIcon(Icons.lock_rounded), findsOneWidget);
  });

  testWidgets('missing dates do not invent one', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Sidebar(
            recentFiles: [
              RecentFile(
                path: 'legacy',
                fullPath: 'D:/synthetic/legacy',
                title: 'Legacy note',
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

    expect(tester.widget<ListTile>(find.byType(ListTile)).subtitle, isNull);
  });

  testWidgets('modified time displays even without a retained note date', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Sidebar(
            recentFiles: [
              RecentFile(
                path: 'storage-other',
                fullPath: 'D:/synthetic/storage-other',
                title: 'Synthetic note',
                noteId: 'abc',
                modified: DateTime(2024, 2, 20, 8, 4),
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
    expect(find.text('20/02/24 08:04 • abc'), findsOneWidget);
  });

  testWidgets('retained date is a fallback when modification time is absent', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Sidebar(
            recentFiles: [
              RecentFile(
                path: 'storage-other',
                fullPath: 'D:/synthetic/storage-other',
                title: 'Synthetic note',
                created: DateTime(2024, 1, 5, 9, 3),
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
    expect(find.text('05/01/24 09:03'), findsOneWidget);
    expect(find.textContaining('•'), findsNothing);
  });
}
