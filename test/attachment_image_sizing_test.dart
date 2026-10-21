import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_application_1/core/storage/attachment_open_cache.dart';
import 'package:flutter_application_1/features/dashboard/models/note_model.dart';
import 'package:flutter_application_1/features/dashboard/widgets/attachment_viewer.dart'
    as desktop;
import 'package:flutter_application_1/features/dashboard/mobile/attachment_viewer.dart'
    as mobile;
import 'support/editor_harness.dart';

Future<File> syntheticImage(
  Directory run,
  int width,
  int height,
  bool gif,
) async {
  final file = File('${run.path}/synthetic.${gif ? 'gif' : 'png'}');
  if (gif) {
    // Valid GIF canvas larger than its small animated frame rectangles.
    final bytes = File(
      'test/fixtures/animated-two-frame.gif',
    ).readAsBytesSync();
    ByteData.sublistView(bytes).setUint16(6, width, Endian.little);
    ByteData.sublistView(bytes).setUint16(8, height, Endian.little);
    file.writeAsBytesSync(bytes);
  } else {
    final recorder = ui.PictureRecorder();
    Canvas(recorder).drawRect(
      Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()),
      Paint()..color = Colors.blue,
    );
    final picture = recorder.endRecording();
    final image = await picture.toImage(width, height);
    try {
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      file.writeAsBytesSync(bytes!.buffer.asUint8List());
    } finally {
      image.dispose();
      picture.dispose();
    }
  }
  return file;
}

void main() {
  for (final isMobile in [false, true]) {
    for (final gif in [false, true]) {
      for (final size in [const Size(2400, 600), const Size(600, 2400)]) {
        testWidgets(
          '${isMobile ? 'mobile' : 'desktop'} ${gif ? 'GIF' : 'image'} preserves $size proportions within preview bounds',
          (tester) async {
            tester.view.physicalSize = isMobile
                ? const Size(390, 844)
                : const Size(1100, 800);
            tester.view.devicePixelRatio = 1;
            addTearDown(tester.view.resetPhysicalSize);
            addTearDown(tester.view.resetDevicePixelRatio);
            final h = await EditorHarness.create();
            final file = (await tester.runAsync(
              () => syntheticImage(
                h.run,
                size.width.toInt(),
                size.height.toInt(),
                gif,
              ),
            ))!;
            final attachment = AttachmentModel(
              id: 'synthetic-image',
              fileName: file.uri.pathSegments.last,
              size: file.lengthSync(),
            );
            final cached = CachedAttachmentFile(
              file.path,
              file.lengthSync(),
              'synthetic',
            );
            try {
              await tester.pumpWidget(
                MaterialApp(
                  home: Scaffold(
                    body: isMobile
                        ? mobile.AttachmentViewer(
                            viewModel: h.editor,
                            attachment: attachment,
                            file: cached,
                          )
                        : desktop.AttachmentViewer(
                            viewModel: h.editor,
                            attachment: attachment,
                            file: cached,
                          ),
                  ),
                ),
              );
              ui.Image? decoded;
              for (var i = 0; i < 80; i++) {
                await tester.runAsync(
                  () => Future<void>.delayed(const Duration(milliseconds: 10)),
                );
                await tester.pump();
                final images = tester
                    .widgetList<RawImage>(find.byType(RawImage))
                    .where((w) => w.image != null);
                if (images.isNotEmpty) {
                  decoded = images.first.image;
                  break;
                }
              }
              expect(
                decoded,
                isNotNull,
                reason: 'The synthetic image must actually decode.',
              );
              if (size.width >= size.height) {
                expect(
                  decoded!.height,
                  closeTo(decoded.width / size.aspectRatio, 1),
                  reason:
                      'Allow at most one decoded pixel of aspect-ratio rounding.',
                );
              } else {
                expect(
                  decoded!.width,
                  closeTo(decoded.height * size.aspectRatio, 1),
                  reason:
                      'Allow at most one decoded pixel of aspect-ratio rounding.',
                );
              }
              // Flutter's animated GIF codec retains its logical canvas size.
              // Static image decoding must remain within the existing budget.
              if (!gif) {
                expect(decoded.width, lessThanOrEqualTo(2048));
                expect(decoded.height, lessThanOrEqualTo(2048));
              }
              expect(h.files.writeAttempts, 0);
              expect(tester.takeException(), isNull);
            } finally {
              await tester.pumpWidget(const SizedBox.shrink());
              h.disposeEditor();
              await tester.pump(const Duration(seconds: 3));
              await tester.runAsync(h.dispose);
            }
          },
        );
      }
    }
  }
}
