import 'dart:ui' show FrameTiming;
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_application_1/core/theme/motion_frame_log.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'frame diagnostics batch, measure both stages and ignore late frames',
    () {
      final messages = <String>[];
      final log = MotionFrameLog(refreshRate: 60, write: messages.add)..start();
      FrameTiming frame(int build, int raster) => FrameTiming(
        vsyncStart: 0,
        buildStart: 0,
        buildFinish: build,
        rasterStart: build,
        rasterFinish: build + raster,
        rasterFinishWallTime: build + raster,
      );
      log.record(List.generate(60, (i) => frame(i == 59 ? 20000 : 2000, 3000)));
      expect(messages, hasLength(1));
      expect(messages.single, contains('build_p95_ms=2.00 raster_p95_ms=3.00'));
      expect(messages.single, contains('over_budget=1'));
      log.record([frame(1000, 25000)]);
      log.stop();
      expect(messages, hasLength(2));
      expect(messages.last, contains('n=1'));
      expect(messages.last, contains('over_budget=1'));
      log.record([frame(99999, 99999)]);
      expect(messages, hasLength(2));
      log.stop();
    },
  );
}
