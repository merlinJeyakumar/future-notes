import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_application_1/features/dashboard/models/draft_transition.dart';
import 'package:flutter_application_1/features/dashboard/widgets/draft_decision_dialog.dart';

void main() {
  for (final kind in DraftDecisionKind.values) {
    testWidgets('decision dialog offers the required choices for $kind', (
      tester,
    ) async {
      DraftDecision? chosen;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => TextButton(
              onPressed: () async {
                chosen = await showDialog<DraftDecision>(
                  context: context,
                  barrierDismissible: false,
                  builder: (_) => DraftDecisionDialog(
                    request: DraftDecisionRequest(
                      kind,
                      DraftTransition.navigation,
                    ),
                  ),
                );
              },
              child: const Text('Open'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      if (kind == DraftDecisionKind.activeAttachments) {
        expect(find.text('Keep editing'), findsOneWidget);
        expect(find.text('Cancel & wait'), findsOneWidget);
        expect(find.text('Discard'), findsNothing);
        await tester.tap(find.text('Keep editing'));
        await tester.pumpAndSettle();
        expect(chosen, DraftDecision.cancel);
        return;
      }
      expect(find.text('Cancel'), findsOneWidget);
      expect(
        find.text('Discard'),
        kind == DraftDecisionKind.firstAttachment
            ? findsNothing
            : findsOneWidget,
      );
      expect(
        find.text(
          kind == DraftDecisionKind.saveFailure
              ? 'Retry'
              : kind == DraftDecisionKind.firstAttachment
              ? 'Save & Continue'
              : 'Save',
        ),
        findsOneWidget,
      );
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(chosen, DraftDecision.cancel);
    });
  }
}
