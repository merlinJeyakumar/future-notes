import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_application_1/features/dashboard/models/note_model.dart';
import 'package:flutter_application_1/features/dashboard/widgets/attachment_media_overlay.dart';

void main() {
  testWidgets(
    'ribbon appears initially and on hover without moving or blocking media',
    (tester) async {
      var taps = 0;
      const media = ValueKey('synthetic-media');
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: 400,
                height: 300,
                child: AttachmentMediaOverlay(
                  attachment: AttachmentModel(
                    id: 'synthetic',
                    fileName: 'sample-animation.gif',
                  ),
                  length: 2048,
                  storedDate: Future.value(DateTime(2026, 10, 16, 14, 5)),
                  child: GestureDetector(
                    key: media,
                    behavior: HitTestBehavior.opaque,
                    onTap: () => taps++,
                    child: const ColoredBox(color: Colors.blue),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      final ribbon = find.byKey(const ValueKey('media-information-ribbon'));
      final opacity = find.ancestor(
        of: ribbon,
        matching: find.byType(AnimatedOpacity),
      );
      final rect = tester.getRect(find.byKey(media));
      expect(tester.widget<AnimatedOpacity>(opacity).opacity, 1);
      expect(find.text('sample-animation.gif'), findsOneWidget);
      expect(find.text('GIF · 2.0 KiB · Stored 16/10 14:05'), findsOneWidget);
      await tester.tapAt(tester.getCenter(ribbon));
      expect(taps, 1);
      await tester.pump(const Duration(seconds: 3));
      await tester.pump(const Duration(milliseconds: 100));
      expect(tester.widget<AnimatedOpacity>(opacity).opacity, 0);
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: Offset.zero);
      await mouse.moveTo(rect.center);
      await tester.pump();
      expect(tester.widget<AnimatedOpacity>(opacity).opacity, 1);
      await tester.pump(const Duration(milliseconds: 60));
      final fade = find.descendant(
        of: opacity,
        matching: find.byType(FadeTransition),
      );
      expect(
        tester.widget<FadeTransition>(fade).opacity.value,
        inExclusiveRange(0, 1),
      );
      expect(tester.getRect(find.byKey(media)), rect);
      await mouse.moveTo(Offset.zero);
      await tester.pumpAndSettle();
      expect(tester.widget<AnimatedOpacity>(opacity).opacity, 0);
      expect(tester.getRect(find.byKey(media)), rect);
      await mouse.removePointer();
    },
  );

  testWidgets(
    'keyboard focus retains the ribbon; reduced motion and early disposal are immediate',
    (tester) async {
      final focus = FocusNode();
      try {
        await tester.pumpWidget(
          MaterialApp(
            home: MediaQuery(
              data: const MediaQueryData(disableAnimations: true),
              child: Scaffold(
                body: AttachmentMediaOverlay(
                  attachment: AttachmentModel(
                    id: 'audio',
                    fileName: 'sample.mp3',
                  ),
                  length: 10,
                  child: Center(
                    child: TextButton(
                      focusNode: focus,
                      onPressed: () {},
                      child: const Text('Play'),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
        focus.requestFocus();
        await tester.pump();
        await tester.pump(const Duration(seconds: 4));
        final opacity = find.byType(AnimatedOpacity);
        expect(tester.widget<AnimatedOpacity>(opacity).opacity, 1);
        focus.unfocus();
        await tester.pump();
        await tester.pump();
        expect(tester.widget<AnimatedOpacity>(opacity).opacity, 0);
        expect(tester.widget<AnimatedOpacity>(opacity).duration, Duration.zero);
        await tester.pumpWidget(
          MaterialApp(
            home: AttachmentMediaOverlay(
              key: const ValueKey('new-media'),
              attachment: AttachmentModel(id: 'image', fileName: 'sample.png'),
              length: 1,
              child: const SizedBox.expand(),
            ),
          ),
        );
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump(const Duration(seconds: 4));
        expect(tester.takeException(), isNull);
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        focus.dispose();
      }
    },
  );
}
