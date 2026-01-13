import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_application_1/features/dashboard/models/note_model.dart';

void main() {
  group('RecentFile Model Tests', () {
    test('creates RecentFile with required fields', () {
      final file = RecentFile(
        path: 'note_abc123',
        fullPath: '/data/notes/note_abc123',
        title: 'Test Note',
      );

      expect(file.path, 'note_abc123');
      expect(file.fullPath, '/data/notes/note_abc123');
      expect(file.title, 'Test Note');
      expect(file.isLocked, false); // Default value
      expect(file.created, isNull);
      expect(file.modified, isNull);
      expect(file.sizeBytes, isNull);
    });

    test('creates RecentFile with all fields', () {
      final now = DateTime.now();
      final file = RecentFile(
        path: 'note_abc123',
        fullPath: '/data/notes/note_abc123',
        title: 'Locked Note',
        isLocked: true,
        created: now,
        modified: now,
        sizeBytes: 2048,
      );

      expect(file.path, 'note_abc123');
      expect(file.title, 'Locked Note');
      expect(file.isLocked, true);
      expect(file.created, now);
      expect(file.modified, now);
      expect(file.sizeBytes, 2048);
    });

    test('isLocked defaults to false', () {
      final file = RecentFile(
        path: 'note_test',
        fullPath: '/path/note_test',
        title: 'Test',
      );

      expect(file.isLocked, false);
    });
  });

  group('NoteModel Tests', () {
    test('creates NoteModel from JSON', () {
      final json = {
        'id': 'test-id-123',
        'title': 'Test Note',
        'content': '{"ops":[{"insert":"Hello\\n"}]}',
        'isLocked': false,
        'timestamp': 1705312800000,
        'attachments': [],
      };

      final note = NoteModel.fromJson(json);

      expect(note.id, 'test-id-123');
      expect(note.title, 'Test Note');
      expect(note.content, '{"ops":[{"insert":"Hello\\n"}]}');
      expect(note.isLocked, false);
      expect(note.timestamp, 1705312800000);
      expect(note.attachments, isEmpty);
    });

    test('creates NoteModel with attachments from JSON', () {
      final json = {
        'id': 'test-id-456',
        'title': 'Note With Attachments',
        'content': 'content',
        'isLocked': true,
        'timestamp': 1705312800000,
        'attachments': [
          {
            'id': 'attach-1',
            'fileName': 'image.png',
            'size': 1024,
            'mimeType': 'image/png',
          },
        ],
      };

      final note = NoteModel.fromJson(json);

      expect(note.attachments.length, 1);
      expect(note.attachments[0].id, 'attach-1');
      expect(note.attachments[0].fileName, 'image.png');
      expect(note.attachments[0].size, 1024);
      expect(note.attachments[0].mimeType, 'image/png');
    });

    test('NoteModel toJson produces valid JSON', () {
      final note = NoteModel(
        id: 'id-789',
        title: 'My Note',
        content: 'test content',
        isLocked: true,
        timestamp: 1705312800000,
        attachments: [
          AttachmentModel(
            id: 'a1',
            fileName: 'file.txt',
            size: 100,
            mimeType: 'text/plain',
          ),
        ],
      );

      final json = note.toJson();

      expect(json['id'], 'id-789');
      expect(json['title'], 'My Note');
      expect(json['content'], 'test content');
      expect(json['isLocked'], true);
      expect(json['timestamp'], 1705312800000);
      expect(json['attachments'], isA<List>());
      expect((json['attachments'] as List).length, 1);
    });

    test('handles legacy attachments (string IDs)', () {
      final json = {
        'id': 'test-id',
        'title': 'Legacy Note',
        'content': 'content',
        'isLocked': false,
        'timestamp': 1705312800000,
        'attachments': ['legacy-id-1', 'legacy-id-2'],
      };

      final note = NoteModel.fromJson(json);

      expect(note.attachments.length, 2);
      expect(note.attachments[0].id, 'legacy-id-1');
      expect(note.attachments[0].fileName, 'Attachment');
      expect(note.attachments[1].id, 'legacy-id-2');
    });
  });

  group('AttachmentModel Tests', () {
    test('creates AttachmentModel with required fields', () {
      final attachment = AttachmentModel(
        id: 'attach-id',
        fileName: 'photo.jpg',
      );

      expect(attachment.id, 'attach-id');
      expect(attachment.fileName, 'photo.jpg');
      expect(attachment.size, 0); // Default
      expect(attachment.mimeType, isNull);
      expect(attachment.isLoading, false);
    });

    test('creates AttachmentModel from JSON', () {
      final json = {
        'id': 'json-id',
        'fileName': 'document.pdf',
        'size': 5000,
        'mimeType': 'application/pdf',
      };

      final attachment = AttachmentModel.fromJson(json);

      expect(attachment.id, 'json-id');
      expect(attachment.fileName, 'document.pdf');
      expect(attachment.size, 5000);
      expect(attachment.mimeType, 'application/pdf');
      expect(attachment.isLoading, false); // Always false from JSON
    });

    test('AttachmentModel toJson produces valid JSON', () {
      final attachment = AttachmentModel(
        id: 'test-id',
        fileName: 'test.txt',
        size: 999,
        mimeType: 'text/plain',
      );

      final json = attachment.toJson();

      expect(json['id'], 'test-id');
      expect(json['fileName'], 'test.txt');
      expect(json['size'], 999);
      expect(json['mimeType'], 'text/plain');
      // isLoading should NOT be in JSON (it's transient)
      expect(json.containsKey('isLoading'), false);
    });

    test('handles missing optional fields in JSON', () {
      final json = {
        'id': 'minimal-id',
        // fileName missing - should use default
      };

      final attachment = AttachmentModel.fromJson(json);

      expect(attachment.id, 'minimal-id');
      expect(attachment.fileName, 'Attachment'); // Default
      expect(attachment.size, 0); // Default
      expect(attachment.mimeType, isNull);
    });
  });
}
