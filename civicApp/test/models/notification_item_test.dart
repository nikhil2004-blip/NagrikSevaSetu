// test/models/notification_item_test.dart
// ─────────────────────────────────────────────────────────────
// Unit tests for NotificationItem.fromJson() and markRead()
// ─────────────────────────────────────────────────────────────

import 'package:flutter_test/flutter_test.dart';
import 'package:civic/models/notification_item.dart';
import '../helpers/mock_data.dart';

void main() {
  group('NotificationItem.fromJson()', () {
    test('parses all standard fields correctly', () {
      final json = MockData.notificationJson();
      final notif = NotificationItem.fromJson(json);

      expect(notif.id, 'notif-1');
      expect(notif.userId, 'user-abc');
      expect(notif.complaintId, 'complaint-1');
      expect(notif.type, 'status_update');
      expect(notif.message, 'Your complaint status changed');
      expect(notif.read, false);
    });

    test('parses createdAt timestamp correctly', () {
      final json = MockData.notificationJson(createdAt: '2025-06-15T08:00:00.000Z');
      final notif = NotificationItem.fromJson(json);

      expect(notif.createdAt.year, 2025);
      expect(notif.createdAt.month, 6);
      expect(notif.createdAt.day, 15);
    });

    test('uses _id field for id', () {
      final json = MockData.notificationJson(id: 'notif-xyz');
      final notif = NotificationItem.fromJson(json);

      expect(notif.id, 'notif-xyz');
    });

    test('defaults read to false when missing', () {
      final json = MockData.notificationJson();
      json.remove('read');
      final notif = NotificationItem.fromJson(json);

      expect(notif.read, false);
    });

    test('parses read: true correctly', () {
      final json = MockData.notificationJson(read: true);
      final notif = NotificationItem.fromJson(json);

      expect(notif.read, true);
    });

    test('defaults type to "status_update" when missing', () {
      final json = MockData.notificationJson();
      json.remove('type');
      final notif = NotificationItem.fromJson(json);

      expect(notif.type, 'status_update');
    });

    test('defaults message to empty string when missing', () {
      final json = MockData.notificationJson();
      json.remove('message');
      final notif = NotificationItem.fromJson(json);

      expect(notif.message, '');
    });

    test('handles null complaintId → complaintId is null', () {
      final json = MockData.notificationJson(complaintId: null);
      final notif = NotificationItem.fromJson(json);

      expect(notif.complaintId, isNull);
    });

    test('handles populated complaintId object — takes _id field', () {
      final json = MockData.notificationJson();
      json['complaintId'] = {'_id': 'cid-123', 'category': 'Road'};
      final notif = NotificationItem.fromJson(json);

      expect(notif.complaintId, 'cid-123');
    });

    test('falls back to DateTime.now() for invalid createdAt', () {
      final json = MockData.notificationJson(createdAt: 'INVALID');
      final notif = NotificationItem.fromJson(json);

      expect(notif.createdAt, isA<DateTime>());
    });

    test('falls back to DateTime.now() when createdAt is null', () {
      final json = MockData.notificationJson();
      json['createdAt'] = null;
      final notif = NotificationItem.fromJson(json);

      expect(notif.createdAt, isA<DateTime>());
    });

    test('parses upvote type correctly', () {
      final json = MockData.notificationJson(
          type: 'upvote', message: 'Someone upvoted your complaint');
      final notif = NotificationItem.fromJson(json);

      expect(notif.type, 'upvote');
      expect(notif.message, 'Someone upvoted your complaint');
    });
  });

  // ─────────────────────────────────────────────────────────────
  group('NotificationItem.markRead()', () {
    test('returns a new instance with read: true', () {
      final original = MockData.makeNotification(read: false);
      final marked = original.markRead();

      expect(marked.read, true);
      expect(original.read, false); // original is unchanged (immutable)
    });

    test('preserves all other fields when marking read', () {
      final original = MockData.makeNotification(
        id: 'notif-99',
        type: 'upvote',
        message: 'You got an upvote',
        complaintId: 'c-55',
      );
      final marked = original.markRead();

      expect(marked.id, 'notif-99');
      expect(marked.type, 'upvote');
      expect(marked.message, 'You got an upvote');
      expect(marked.complaintId, 'c-55');
      expect(marked.userId, original.userId);
      expect(marked.createdAt, original.createdAt);
    });

    test('returns a new object (not the same reference)', () {
      final original = MockData.makeNotification(read: false);
      final marked = original.markRead();

      expect(identical(original, marked), false);
    });

    test('calling markRead() on already-read notification still returns read: true', () {
      final alreadyRead = MockData.makeNotification(read: true);
      final marked = alreadyRead.markRead();

      expect(marked.read, true);
    });
  });
}
