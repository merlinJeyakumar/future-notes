class AttachmentModel {
  final String id;
  final String fileName;
  final int size;
  final String? mimeType;
  final String? mentionId;
  final String? encryptedThumbnail;
  String get mentionIdentity => mentionId ?? id;
  final bool isLoading; // Transient

  AttachmentModel({
    required this.id,
    required this.fileName,
    this.size = 0,
    this.mimeType,
    this.mentionId,
    this.encryptedThumbnail,
    this.isLoading = false,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'fileName': fileName,
    'size': size,
    'mimeType': mimeType,
    if (mentionId != null) 'mentionId': mentionId,
    if (encryptedThumbnail != null) 'encryptedThumbnail': encryptedThumbnail,
  };

  factory AttachmentModel.fromJson(Map<String, dynamic> json) {
    return AttachmentModel(
      id: json['id'] as String,
      fileName: json['fileName'] as String? ?? 'Attachment',
      size: json['size'] as int? ?? 0,
      mimeType: json['mimeType'] as String?,
      mentionId: json['mentionId'] as String?,
      encryptedThumbnail:
          json['encryptedThumbnail'] is String &&
              (json['encryptedThumbnail'] as String).length <= 48 * 1024
          ? json['encryptedThumbnail'] as String
          : null,
      isLoading: false,
    );
  }
}

class NoteModel {
  final String id;
  final String title;
  final String content;
  final bool isLocked;
  final int timestamp;
  final List<AttachmentModel> attachments;

  NoteModel({
    required this.id,
    required this.title,
    required this.content,
    required this.isLocked,
    required this.timestamp,
    this.attachments = const [],
  });

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'content': content,
      'isLocked': isLocked,
      'timestamp': timestamp,
      'attachments': attachments.map((e) => e.toJson()).toList(),
    };
  }

  factory NoteModel.fromJson(Map<String, dynamic> json) {
    var attachmentsList = <AttachmentModel>[];
    if (json['attachments'] != null) {
      if (json['attachments'] is List) {
        final list = json['attachments'] as List;
        if (list.isNotEmpty) {
          if (list.first is String) {
            // Legacy: List<String> IDs
            attachmentsList = list
                .map(
                  (e) =>
                      AttachmentModel(id: e as String, fileName: 'Attachment'),
                )
                .toList();
          } else {
            // New: List<Map>
            attachmentsList = list
                .map((e) => AttachmentModel.fromJson(e as Map<String, dynamic>))
                .toList();
          }
        }
      }
    }

    return NoteModel(
      id: json['id'] as String,
      title: json['title'] as String,
      content: json['content'] as String,
      isLocked: json['isLocked'] as bool,
      timestamp: json['timestamp'] as int,
      attachments: attachmentsList,
    );
  }
}

class RecentFile {
  final String path;
  final String fullPath;
  final String title;
  final String? noteId;
  final bool isLocked;
  final DateTime? created; // Can be file creation time or note timestamp
  final DateTime? modified;
  final int? sizeBytes;

  RecentFile({
    required this.path,
    required this.fullPath,
    required this.title,
    this.noteId,
    this.isLocked = false,
    this.created,
    this.modified,
    this.sizeBytes,
  });
}
