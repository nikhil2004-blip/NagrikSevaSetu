// test/providers/complaint_provider_test.dart
// ─────────────────────────────────────────────────────────────
// Unit tests for ComplaintProvider
//
// Strategy: We create a mock ComplaintRepository using mockito's
// @GenerateMocks annotation and test the provider's state
// transitions (isLoading, errorMessage, list updates).
//
// Run code generation ONCE before first run:
//   flutter pub run build_runner build --delete-conflicting-outputs
// ─────────────────────────────────────────────────────────────

import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/annotations.dart';
import 'package:mockito/mockito.dart';
import 'package:civic/providers/complaint_provider.dart';
import 'package:civic/repositories/complaint_repository.dart';
import 'package:civic/core/errors/app_exception.dart';
import '../helpers/mock_data.dart';

import 'complaint_provider_test.mocks.dart';

@GenerateMocks([ComplaintRepository])
void main() {
  late MockComplaintRepository mockRepository;
  late ComplaintProvider provider;

  setUp(() {
    mockRepository = MockComplaintRepository();
    provider = ComplaintProvider(repository: mockRepository);
  });

  tearDown(() {
    provider.dispose();
  });

  // ── Helper ──────────────────────────────────────────────────
  final complaint1 = MockData.makeComplaint(id: 'c-1', upvotes: 0, hasUpvoted: false);
  final complaint2 = MockData.makeComplaint(id: 'c-2', category: 'Water');

  // ── loadAllComplaints ────────────────────────────────────────
  group('loadAllComplaints()', () {
    test('sets isLoadingAll true then false around the call', () async {
      when(mockRepository.getAllComplaints(
        category: anyNamed('category'),
        status: anyNamed('status'),
      )).thenAnswer((_) async {
        // Assert loading is true during the call
        expect(provider.isLoadingAll, true);
        return [complaint1, complaint2];
      });

      final future = provider.loadAllComplaints();
      expect(provider.isLoadingAll, true);
      await future;
      expect(provider.isLoadingAll, false);
    });

    test('populates allComplaints on success', () async {
      when(mockRepository.getAllComplaints(
        category: anyNamed('category'),
        status: anyNamed('status'),
      )).thenAnswer((_) async => [complaint1, complaint2]);

      await provider.loadAllComplaints();

      expect(provider.allComplaints.length, 2);
      expect(provider.allComplaints[0].id, 'c-1');
      expect(provider.errorMessage, isNull);
    });

    test('sets errorMessage on AppException and does NOT throw', () async {
      when(mockRepository.getAllComplaints(
        category: anyNamed('category'),
        status: anyNamed('status'),
      )).thenThrow(const NetworkException());

      await provider.loadAllComplaints(); // must not throw

      expect(provider.allComplaints, isEmpty);
      expect(provider.errorMessage,
          contains('No internet connection'));
      expect(provider.isLoadingAll, false);
    });

    test('sets generic errorMessage on unexpected exception', () async {
      when(mockRepository.getAllComplaints(
        category: anyNamed('category'),
        status: anyNamed('status'),
      )).thenThrow(Exception('Random failure'));

      await provider.loadAllComplaints();

      expect(provider.errorMessage, 'Failed to load complaints.');
    });

    test('clears errorMessage on successful reload after error', () async {
      // Dart Mockito doesn't support .thenThrow().thenAnswer() chaining.
      // Use a call counter inside thenAnswer instead.
      var callCount = 0;
      when(mockRepository.getAllComplaints(
        category: anyNamed('category'),
        status: anyNamed('status'),
      )).thenAnswer((_) async {
        callCount++;
        if (callCount == 1) throw const NetworkException();
        return [complaint1];
      });

      await provider.loadAllComplaints(); // first call: throws
      expect(provider.errorMessage, isNotNull);

      await provider.loadAllComplaints(); // second call: succeeds
      expect(provider.errorMessage, isNull);
      expect(provider.allComplaints.length, 1);
    });

    test('returns an unmodifiable list', () async {
      when(mockRepository.getAllComplaints(
        category: anyNamed('category'),
        status: anyNamed('status'),
      )).thenAnswer((_) async => [complaint1]);

      await provider.loadAllComplaints();

      expect(
        () => provider.allComplaints.add(complaint2),
        throwsUnsupportedError,
      );
    });
  });

  // ── loadMyComplaints ─────────────────────────────────────────
  group('loadMyComplaints()', () {
    test('populates myComplaints on success', () async {
      when(mockRepository.getMyComplaints())
          .thenAnswer((_) async => [complaint1]);

      await provider.loadMyComplaints();

      expect(provider.myComplaints.length, 1);
      expect(provider.isLoadingMine, false);
    });

    test('sets errorMessage on AppException', () async {
      when(mockRepository.getMyComplaints())
          .thenThrow(const UnauthorizedException());

      await provider.loadMyComplaints();

      expect(provider.myComplaints, isEmpty);
      expect(provider.errorMessage, contains('Session expired'));
    });
  });

  // ── submitComplaint ──────────────────────────────────────────
  group('submitComplaint()', () {
    test('returns null on success and inserts at top of both lists', () async {
      // Pre-populate lists
      when(mockRepository.getAllComplaints(
        category: anyNamed('category'),
        status: anyNamed('status'),
      )).thenAnswer((_) async => [complaint2]);
      await provider.loadAllComplaints();

      final newComplaint = MockData.makeComplaint(id: 'new-c');
      when(mockRepository.createComplaint(
        category: anyNamed('category'),
        description: anyNamed('description'),
        lat: anyNamed('lat'),
        lng: anyNamed('lng'),
        imageFile: anyNamed('imageFile'),
        voiceNoteUrl: anyNamed('voiceNoteUrl'),
      )).thenAnswer((_) async => newComplaint);

      final error = await provider.submitComplaint(
        category: 'Road',
        description: 'Large pothole',
        lat: 12.9716,
        lng: 77.5946,
      );

      expect(error, isNull);
      expect(provider.allComplaints.first.id, 'new-c'); // prepended
      expect(provider.isSubmitting, false);
    });

    test('returns error message on AppException', () async {
      when(mockRepository.createComplaint(
        category: anyNamed('category'),
        description: anyNamed('description'),
        lat: anyNamed('lat'),
        lng: anyNamed('lng'),
        imageFile: anyNamed('imageFile'),
        voiceNoteUrl: anyNamed('voiceNoteUrl'),
      )).thenThrow(const ValidationException('Description is too short.'));

      final error = await provider.submitComplaint(
        category: 'Road',
        description: 'Bad',
        lat: 12.0,
        lng: 77.0,
      );

      expect(error, 'Description is too short.');
      expect(provider.isSubmitting, false);
    });

    test('returns generic message on unexpected exception', () async {
      when(mockRepository.createComplaint(
        category: anyNamed('category'),
        description: anyNamed('description'),
        lat: anyNamed('lat'),
        lng: anyNamed('lng'),
        imageFile: anyNamed('imageFile'),
        voiceNoteUrl: anyNamed('voiceNoteUrl'),
      )).thenThrow(Exception('Unexpected!'));

      final error = await provider.submitComplaint(
        category: 'Road',
        description: 'Test',
        lat: 12.0,
        lng: 77.0,
      );

      expect(error, 'Failed to submit complaint.');
    });
  });

  // ── toggleUpvote ─────────────────────────────────────────────
  group('toggleUpvote()', () {
    setUp(() async {
      // Load a complaint without upvote first
      when(mockRepository.getAllComplaints(
        category: anyNamed('category'),
        status: anyNamed('status'),
      )).thenAnswer((_) async => [complaint1]);
      await provider.loadAllComplaints();
    });

    test('optimistically increments upvote count before backend responds', () async {
      when(mockRepository.toggleUpvote('c-1'))
          .thenAnswer((_) async => (upvotes: 1, hasUpvoted: true));

      final future = provider.toggleUpvote('c-1');
      // After optimistic update but before backend response
      expect(provider.allComplaints.first.hasUpvoted, true);
      expect(provider.allComplaints.first.upvotes, 1);
      await future;
    });

    test('confirms with backend upvote count after API call', () async {
      when(mockRepository.toggleUpvote('c-1'))
          .thenAnswer((_) async => (upvotes: 5, hasUpvoted: true));

      await provider.toggleUpvote('c-1');

      expect(provider.allComplaints.first.upvotes, 5);
      expect(provider.allComplaints.first.hasUpvoted, true);
    });

    test('rolls back optimistic update on API failure', () async {
      when(mockRepository.toggleUpvote('c-1'))
          .thenThrow(const NetworkException());

      final originalCount = complaint1.upvotes; // 0
      await provider.toggleUpvote('c-1');

      // Should be rolled back to original
      expect(provider.allComplaints.first.upvotes, originalCount);
      expect(provider.allComplaints.first.hasUpvoted, false);
    });

    test('does nothing if complaintId is not in either list', () async {
      // 'nonexistent' is not in allComplaints or myComplaints
      await provider.toggleUpvote('nonexistent');
      verifyNever(mockRepository.toggleUpvote(any));
    });

    test('optimistically decrements when already upvoted', () async {
      // Pre-load a complaint that is already upvoted
      final alreadyUpvoted = MockData.makeComplaint(
        id: 'c-upvoted', upvotes: 5, hasUpvoted: true);
      when(mockRepository.getAllComplaints(
        category: anyNamed('category'),
        status: anyNamed('status'),
      )).thenAnswer((_) async => [alreadyUpvoted]);
      await provider.loadAllComplaints();

      when(mockRepository.toggleUpvote('c-upvoted'))
          .thenAnswer((_) async => (upvotes: 4, hasUpvoted: false));

      final future = provider.toggleUpvote('c-upvoted');
      // Optimistic: should immediately decrement
      expect(provider.allComplaints.first.upvotes, 4);
      expect(provider.allComplaints.first.hasUpvoted, false);
      await future;
    });
  });

  // ── clearAll ─────────────────────────────────────────────────
  group('clearAll()', () {
    test('empties both complaint lists and errorMessage', () async {
      when(mockRepository.getAllComplaints(
        category: anyNamed('category'),
        status: anyNamed('status'),
      )).thenAnswer((_) async => [complaint1]);
      await provider.loadAllComplaints();

      provider.clearAll();

      expect(provider.allComplaints, isEmpty);
      expect(provider.myComplaints, isEmpty);
      expect(provider.errorMessage, isNull);
    });
  });
}
