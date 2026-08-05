// test/providers/notification_provider_test.dart
// ─────────────────────────────────────────────────────────────
// Unit tests for NotificationProvider
//
// Tests:
//   - loadNotifications: success, error, clears old data
//   - markAsRead: optimistic update, rollback on failure
//   - markAllAsRead: bulk optimistic update, rollback on failure
//   - clearAll: on sign-out
// ─────────────────────────────────────────────────────────────

import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/annotations.dart';
import 'package:mockito/mockito.dart';
import 'package:civic/providers/notification_provider.dart';
import 'package:civic/repositories/notification_repository.dart';
import 'package:civic/core/errors/app_exception.dart';
import '../helpers/mock_data.dart';

import 'notification_provider_test.mocks.dart';

@GenerateMocks([NotificationRepository])
void main() {
  late MockNotificationRepository mockRepository;
  late NotificationProvider provider;

  final notif1 = MockData.makeNotification(id: 'n-1', read: false);
  final notif2 = MockData.makeNotification(id: 'n-2', read: false);
  final notif3 = MockData.makeNotification(id: 'n-3', read: true);

  setUp(() {
    mockRepository = MockNotificationRepository();
    provider = NotificationProvider(repository: mockRepository);
  });

  tearDown(() {
    provider.dispose();
  });

  // ── loadNotifications ────────────────────────────────────────
  group('loadNotifications()', () {
    test('sets isLoading true then false', () async {
      when(mockRepository.getMyNotifications()).thenAnswer((_) async {
        expect(provider.isLoading, true);
        return (notifications: [notif1], unreadCount: 1);
      });

      final future = provider.loadNotifications();
      expect(provider.isLoading, true);
      await future;
      expect(provider.isLoading, false);
    });

    test('populates notifications and unreadCount on success', () async {
      when(mockRepository.getMyNotifications())
          .thenAnswer((_) async =>
              (notifications: [notif1, notif2, notif3], unreadCount: 2));

      await provider.loadNotifications();

      expect(provider.notifications.length, 3);
      expect(provider.unreadCount, 2);
      expect(provider.errorMessage, isNull);
    });

    test('sets errorMessage on AppException and does not throw', () async {
      when(mockRepository.getMyNotifications())
          .thenThrow(const UnauthorizedException());

      await provider.loadNotifications(); // must not throw

      expect(provider.notifications, isEmpty);
      expect(provider.errorMessage, contains('Session expired'));
      expect(provider.isLoading, false);
    });

    test('sets generic errorMessage on unexpected exception', () async {
      when(mockRepository.getMyNotifications())
          .thenThrow(Exception('Random failure'));

      await provider.loadNotifications();

      expect(provider.errorMessage, 'Failed to load notifications.');
    });

    test('returns an unmodifiable list', () async {
      when(mockRepository.getMyNotifications())
          .thenAnswer((_) async =>
              (notifications: [notif1], unreadCount: 1));

      await provider.loadNotifications();

      expect(
        () => provider.notifications.add(notif2),
        throwsUnsupportedError,
      );
    });
  });

  // ── markAsRead ───────────────────────────────────────────────
  group('markAsRead()', () {
    setUp(() async {
      when(mockRepository.getMyNotifications())
          .thenAnswer((_) async =>
              (notifications: [notif1, notif2, notif3], unreadCount: 2));
      await provider.loadNotifications();
    });

    test('immediately sets notification read: true (optimistic)', () async {
      when(mockRepository.markAsRead('n-1')).thenAnswer((_) async {});

      final future = provider.markAsRead('n-1');
      // Optimistic update — already applied before awaiting
      expect(provider.notifications.firstWhere((n) => n.id == 'n-1').read, true);
      await future;
    });

    test('decrements unreadCount on successful mark-read', () async {
      when(mockRepository.markAsRead('n-1')).thenAnswer((_) async {});

      await provider.markAsRead('n-1');

      expect(provider.unreadCount, 1);
    });

    test('does not decrement unreadCount below zero', () async {
      // notif3 is already read (read: true)
      when(mockRepository.markAsRead('n-3')).thenAnswer((_) async {});

      await provider.markAsRead('n-3'); // should be a no-op

      // unreadCount was 2, should still be 2 because n-3 was already read
      expect(provider.unreadCount, 2);
    });

    test('does nothing for a non-existent notification id', () async {
      await provider.markAsRead('nonexistent');
      verifyNever(mockRepository.markAsRead(any));
    });

    test('reloads on AppException (consistency recovery)', () async {
      when(mockRepository.markAsRead('n-1'))
          .thenThrow(const NetworkException());
      // The provider will call loadNotifications on failure
      when(mockRepository.getMyNotifications())
          .thenAnswer((_) async =>
              (notifications: [notif1, notif2, notif3], unreadCount: 2));

      await provider.markAsRead('n-1');

      // Should have re-fetched from backend to restore consistent state
      verify(mockRepository.getMyNotifications()).called(2); // initial + reload
    });
  });

  // ── markAllAsRead ────────────────────────────────────────────
  group('markAllAsRead()', () {
    setUp(() async {
      when(mockRepository.getMyNotifications())
          .thenAnswer((_) async =>
              (notifications: [notif1, notif2, notif3], unreadCount: 2));
      await provider.loadNotifications();
    });

    test('immediately marks all notifications as read (optimistic)', () async {
      when(mockRepository.markAllAsRead()).thenAnswer((_) async {});

      final future = provider.markAllAsRead();
      expect(provider.notifications.every((n) => n.read), true);
      expect(provider.unreadCount, 0);
      await future;
    });

    test('sets unreadCount to 0', () async {
      when(mockRepository.markAllAsRead()).thenAnswer((_) async {});

      await provider.markAllAsRead();

      expect(provider.unreadCount, 0);
    });

    test('reloads on AppException for consistency', () async {
      when(mockRepository.markAllAsRead())
          .thenThrow(const ServerException());
      when(mockRepository.getMyNotifications())
          .thenAnswer((_) async =>
              (notifications: [notif1, notif2, notif3], unreadCount: 2));

      await provider.markAllAsRead();

      verify(mockRepository.getMyNotifications()).called(2);
    });
  });

  // ── clearAll ─────────────────────────────────────────────────
  group('clearAll()', () {
    setUp(() async {
      when(mockRepository.getMyNotifications())
          .thenAnswer((_) async =>
              (notifications: [notif1, notif2], unreadCount: 2));
      await provider.loadNotifications();
    });

    test('empties notifications list and resets counts', () {
      provider.clearAll();

      expect(provider.notifications, isEmpty);
      expect(provider.unreadCount, 0);
      expect(provider.errorMessage, isNull);
    });
  });
}
