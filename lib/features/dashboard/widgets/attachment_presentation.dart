import '../models/attachment_job.dart';

enum AttachmentVisualKind { image, video, audio, document, file }

AttachmentVisualKind attachmentVisualKind(String name) {
  final ext = name.split('.').last.toLowerCase();
  if (['jpg', 'jpeg', 'png', 'webp', 'gif', 'bmp'].contains(ext)) {
    return AttachmentVisualKind.image;
  }
  if ([
    'mp4',
    'mkv',
    'mov',
    'webm',
    'avi',
    'wmv',
    'm4v',
    'mpg',
    'mpeg',
    '3gp',
  ].contains(ext)) {
    return AttachmentVisualKind.video;
  }
  if (['mp3', 'wav', 'ogg', 'm4a', 'aac', 'flac'].contains(ext)) {
    return AttachmentVisualKind.audio;
  }
  if ([
    'pdf',
    'txt',
    'md',
    'doc',
    'docx',
    'xls',
    'xlsx',
    'ppt',
    'pptx',
  ].contains(ext)) {
    return AttachmentVisualKind.document;
  }
  return AttachmentVisualKind.file;
}

String formatAttachmentBytes(int bytes) {
  if (bytes < 1024) return '$bytes B';
  var value = bytes.toDouble();
  const units = ['B', 'KiB', 'MiB', 'GiB', 'TiB'];
  var unit = 0;
  while (value >= 1024 && unit < units.length - 1) {
    value /= 1024;
    unit++;
  }
  return '${value.toStringAsFixed(value >= 100 ? 0 : 1)} ${units[unit]}';
}

String attachmentPhaseLabel(AttachmentJobPhase phase) => switch (phase) {
  AttachmentJobPhase.queued => 'Queued',
  AttachmentJobPhase.preparing => 'Checking attachment…',
  AttachmentJobPhase.decrypting => 'Decrypting',
  AttachmentJobPhase.encrypting => 'Encrypting',
  AttachmentJobPhase.verifying => 'Verifying',
  AttachmentJobPhase.finalizing => 'Finishing safely…',
  AttachmentJobPhase.cancelling => 'Cancelling…',
  AttachmentJobPhase.completed => 'Completed',
  AttachmentJobPhase.cancelled => 'Cancelled',
  AttachmentJobPhase.failed => 'Failed',
};
