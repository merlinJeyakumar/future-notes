import 'package:flutter/foundation.dart';
import '../../features/dashboard/models/attachment_job.dart';

abstract interface class AdditionalMobileJobs {
  ValueListenable<List<AttachmentJobState>> get jobs;
  Future<void> cancel(String id);
  Map<String, Object?>? recovery(String id);
}
