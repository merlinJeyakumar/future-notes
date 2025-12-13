class NoteModel {
  final String id;
  final String title;
  final String content;
  final bool isLocked;
  final int timestamp;

  NoteModel({
    required this.id,
    required this.title,
    required this.content,
    required this.isLocked,
    required this.timestamp,
  });

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'content': content,
      'isLocked': isLocked,
      'timestamp': timestamp,
    };
  }

  factory NoteModel.fromJson(Map<String, dynamic> json) {
    return NoteModel(
      id: json['id'] as String,
      title: json['title'] as String,
      content: json['content'] as String,
      isLocked: json['isLocked'] as bool,
      timestamp: json['timestamp'] as int,
    );
  }
}

class RecentFile {
  final String path;
  final String fullPath;
  final String title;
  final bool isLocked;
  final DateTime? created; // Can be file creation time or note timestamp
  final DateTime? modified;
  final int? sizeBytes;

  RecentFile({
    required this.path,
    required this.fullPath,
    required this.title,
    this.isLocked = false,
    this.created,
    this.modified,
    this.sizeBytes,
  });
}
