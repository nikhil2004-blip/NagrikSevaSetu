// test/models/complaint_model_test.dart
// ─────────────────────────────────────────────────────────────
// Unit tests for Complaint.fromJson(), toJson(), and copyWith()
//
// These are PURE unit tests — no Flutter widgets, no network,
// no Firebase. They only validate data transformation logic.
// ─────────────────────────────────────────────────────────────

import 'package:flutter_test/flutter_test.dart';
import 'package:civic/models/complaint.dart';
import '../helpers/mock_data.dart';

void main() {
  group('Complaint.fromJson()', () {
    test('parses all standard fields correctly', () {
      final json = MockData.complaintJson();
      final complaint = Complaint.fromJson(json);

      expect(complaint.id, 'complaint-1');
      expect(complaint.category, 'Road');
      expect(complaint.description, 'A large pothole near the school');
      expect(complaint.status, 'Pending');
      expect(complaint.urgency, 'Medium');
      expect(complaint.upvotes, 3);
      expect(complaint.hasUpvoted, false);
    });

    test('extracts GeoJSON coordinates: index 0 = lng, index 1 = lat', () {
      final json = MockData.complaintJson();
      final complaint = Complaint.fromJson(json);

      // GeoJSON stores [longitude, latitude]
      expect(complaint.lng, closeTo(77.5946, 0.001));
      expect(complaint.lat, closeTo(12.9716, 0.001));
    });

    test('parses populated userId object (name/email) — takes _id field', () {
      final json = MockData.complaintJson();
      json['userId'] = {'_id': 'user-abc', 'name': 'Alice', 'email': 'a@b.com'};
      final complaint = Complaint.fromJson(json);

      expect(complaint.userId, 'user-abc');
    });

    test('parses raw string userId', () {
      final json = MockData.complaintJson();
      json['userId'] = 'raw-string-uid';
      final complaint = Complaint.fromJson(json);

      expect(complaint.userId, 'raw-string-uid');
    });

    test('uses _id field first, falls back to id', () {
      final json = MockData.complaintJson();
      json.remove('_id');
      json['id'] = 'fallback-id';
      final complaint = Complaint.fromJson(json);

      expect(complaint.id, 'fallback-id');
    });

    test('defaults category to "Others" when missing', () {
      final json = MockData.complaintJson();
      json.remove('category');
      final complaint = Complaint.fromJson(json);

      expect(complaint.category, 'Others');
    });

    test('defaults status to "Pending" when missing', () {
      final json = MockData.complaintJson();
      json.remove('status');
      final complaint = Complaint.fromJson(json);

      expect(complaint.status, 'Pending');
    });

    test('defaults urgency to "Low" when missing', () {
      final json = MockData.complaintJson();
      json.remove('urgency');
      final complaint = Complaint.fromJson(json);

      expect(complaint.urgency, 'Low');
    });

    test('defaults upvotes to 0 when missing', () {
      final json = MockData.complaintJson();
      json.remove('upvotes');
      final complaint = Complaint.fromJson(json);

      expect(complaint.upvotes, 0);
    });

    test('defaults hasUpvoted to false when missing', () {
      final json = MockData.complaintJson();
      json.remove('hasUpvoted');
      final complaint = Complaint.fromJson(json);

      expect(complaint.hasUpvoted, false);
    });

    test('defaults lat and lng to 0.0 when location is null', () {
      final json = MockData.complaintJson();
      json['location'] = null;
      final complaint = Complaint.fromJson(json);

      expect(complaint.lat, 0.0);
      expect(complaint.lng, 0.0);
    });

    test('defaults lat and lng to 0.0 when coordinates list is missing', () {
      final json = MockData.complaintJson();
      json['location'] = {'type': 'Point'}; // no coordinates key
      final complaint = Complaint.fromJson(json);

      expect(complaint.lat, 0.0);
      expect(complaint.lng, 0.0);
    });

    test('falls back to DateTime.now() for invalid createdAt string', () {
      final json = MockData.complaintJson();
      json['createdAt'] = 'not-a-date';
      final before = DateTime.now();
      final complaint = Complaint.fromJson(json);
      final after = DateTime.now();

      expect(
        complaint.createdAt.isAfter(before.subtract(const Duration(seconds: 1))),
        true,
      );
      expect(
        complaint.createdAt.isBefore(after.add(const Duration(seconds: 1))),
        true,
      );
    });

    test('falls back to DateTime.now() when createdAt is null', () {
      final json = MockData.complaintJson();
      json['createdAt'] = null;
      final complaint = Complaint.fromJson(json);

      expect(complaint.createdAt, isA<DateTime>());
    });

    test('parses imageUrl correctly', () {
      final json = MockData.complaintJson();
      json['imageUrl'] = 'https://res.cloudinary.com/test/image/upload/v1/photo.jpg';
      final complaint = Complaint.fromJson(json);

      expect(complaint.imageUrl, contains('cloudinary.com'));
    });

    test('parses voiceNoteTranscript correctly', () {
      final json = MockData.complaintJson();
      json['voiceNoteTranscript'] = 'There is a big pothole here.';
      final complaint = Complaint.fromJson(json);

      expect(complaint.voiceNoteTranscript, 'There is a big pothole here.');
    });

    test('integer coordinates cast to double correctly', () {
      final json = MockData.complaintJson();
      json['location'] = {
        'type': 'Point',
        'coordinates': [77, 12], // integers, not doubles
      };
      final complaint = Complaint.fromJson(json);

      expect(complaint.lng, isA<double>());
      expect(complaint.lat, isA<double>());
    });
  });

  // ─────────────────────────────────────────────────────────────
  group('Complaint.toJson()', () {
    test('includes required fields', () {
      final c = MockData.makeComplaint(
        category: 'Water',
        description: 'No water supply',
        lat: 28.6139,
        lng: 77.2090,
      );
      final json = c.toJson();

      expect(json['category'], 'Water');
      expect(json['description'], 'No water supply');
      expect(json['lat'], 28.6139);
      expect(json['lng'], 77.2090);
    });

    test('omits imageUrl when null', () {
      final c = MockData.makeComplaint(imageUrl: null);
      final json = c.toJson();

      expect(json.containsKey('imageUrl'), false);
    });

    test('includes imageUrl when set', () {
      final c = MockData.makeComplaint(
          imageUrl: 'https://res.cloudinary.com/test/image.jpg');
      final json = c.toJson();

      expect(json['imageUrl'], isNotNull);
    });

    test('omits voiceNoteUrl when null', () {
      final c = MockData.makeComplaint(voiceNoteUrl: null);
      final json = c.toJson();

      expect(json.containsKey('voiceNoteUrl'), false);
    });

    test('includes voiceNoteUrl when set', () {
      final c = MockData.makeComplaint(
          voiceNoteUrl: 'https://res.cloudinary.com/test/audio.m4a');
      final json = c.toJson();

      expect(json['voiceNoteUrl'], isNotNull);
    });
  });

  // ─────────────────────────────────────────────────────────────
  group('Complaint.copyWith()', () {
    test('updates status while preserving other fields', () {
      final original = MockData.makeComplaint(status: 'Pending');
      final updated = original.copyWith(status: 'Resolved');

      expect(updated.status, 'Resolved');
      expect(updated.id, original.id);
      expect(updated.category, original.category);
      expect(updated.description, original.description);
      expect(updated.lat, original.lat);
      expect(updated.lng, original.lng);
    });

    test('updates upvotes correctly', () {
      final original = MockData.makeComplaint(upvotes: 5);
      final updated = original.copyWith(upvotes: 6);

      expect(updated.upvotes, 6);
      expect(updated.hasUpvoted, original.hasUpvoted);
    });

    test('flips hasUpvoted from false to true', () {
      final original = MockData.makeComplaint(hasUpvoted: false, upvotes: 2);
      final updated = original.copyWith(hasUpvoted: true, upvotes: 3);

      expect(updated.hasUpvoted, true);
      expect(updated.upvotes, 3);
    });

    test('updates urgency while keeping all other fields', () {
      final original = MockData.makeComplaint(urgency: 'Low');
      final updated = original.copyWith(urgency: 'High');

      expect(updated.urgency, 'High');
      expect(updated.status, original.status);
    });

    test('returns same values when called with no arguments', () {
      final original = MockData.makeComplaint();
      final copy = original.copyWith();

      expect(copy.id, original.id);
      expect(copy.status, original.status);
      expect(copy.upvotes, original.upvotes);
      expect(copy.urgency, original.urgency);
    });
  });
}
