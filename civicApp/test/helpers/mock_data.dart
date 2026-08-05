// test/helpers/mock_data.dart
// ─────────────────────────────────────────────────────────────
// Shared test data factories used across all test files.
// Define once, reuse everywhere — keeps tests DRY.
// ─────────────────────────────────────────────────────────────

import 'package:civic/models/complaint.dart';
import 'package:civic/models/notification_item.dart';
import 'package:civic/models/user_profile.dart';

class MockData {
  MockData._();

  // ── Complaints ───────────────────────────────────────────────

  static Complaint makeComplaint({
    String id = 'complaint-1',
    String userId = 'user-abc',
    String category = 'Road',
    String description = 'A large pothole near the school',
    String? imageUrl,
    String? voiceNoteUrl,
    String? voiceNoteTranscript,
    String status = 'Pending',
    String urgency = 'Low',
    int upvotes = 0,
    bool hasUpvoted = false,
    double lat = 12.9716,
    double lng = 77.5946,
    DateTime? createdAt,
  }) {
    return Complaint(
      id: id,
      userId: userId,
      category: category,
      description: description,
      imageUrl: imageUrl,
      voiceNoteUrl: voiceNoteUrl,
      voiceNoteTranscript: voiceNoteTranscript,
      status: status,
      urgency: urgency,
      upvotes: upvotes,
      hasUpvoted: hasUpvoted,
      lat: lat,
      lng: lng,
      createdAt: createdAt ?? DateTime(2025, 1, 15, 10, 30),
    );
  }

  static Map<String, dynamic> complaintJson({
    String id = 'complaint-1',
    String category = 'Road',
    String description = 'A large pothole near the school',
    String status = 'Pending',
    String urgency = 'Medium',
    int upvotes = 3,
    bool hasUpvoted = false,
    String createdAt = '2025-01-15T10:30:00.000Z',
  }) => {
    '_id': id,
    'userId': {'_id': 'user-abc', 'name': 'Test User'},
    'category': category,
    'description': description,
    'status': status,
    'urgency': urgency,
    'upvotes': upvotes,
    'hasUpvoted': hasUpvoted,
    'location': {
      'type': 'Point',
      'coordinates': [77.5946, 12.9716],
    },
    'createdAt': createdAt,
  };

  // ── Notifications ────────────────────────────────────────────

  static NotificationItem makeNotification({
    String id = 'notif-1',
    String userId = 'user-abc',
    String? complaintId = 'complaint-1',
    String type = 'status_update',
    String message = 'Your complaint status changed to In Progress',
    bool read = false,
    DateTime? createdAt,
  }) {
    return NotificationItem(
      id: id,
      userId: userId,
      complaintId: complaintId,
      type: type,
      message: message,
      read: read,
      createdAt: createdAt ?? DateTime(2025, 1, 15, 11, 0),
    );
  }

  static Map<String, dynamic> notificationJson({
    String id = 'notif-1',
    String userId = 'user-abc',
    String? complaintId = 'complaint-1',
    String type = 'status_update',
    String message = 'Your complaint status changed',
    bool read = false,
    String createdAt = '2025-01-15T11:00:00.000Z',
  }) => {
    '_id': id,
    'userId': userId,
    'complaintId': complaintId,
    'type': type,
    'message': message,
    'read': read,
    'createdAt': createdAt,
  };

  // ── User Profiles ────────────────────────────────────────────

  static UserProfile makeCitizenProfile({
    String id = 'mongo-user-1',
    String firebaseUid = 'firebase-uid-1',
    String name = 'Test Citizen',
    String email = 'citizen@test.com',
    String? phone,
  }) {
    return UserProfile(
      id: id,
      firebaseUid: firebaseUid,
      name: name,
      email: email,
      phone: phone,
      role: 'citizen',
      createdAt: DateTime(2024, 6, 1),
    );
  }

  static UserProfile makeAdminProfile() {
    return const UserProfile(
      id: 'mongo-admin-1',
      firebaseUid: 'firebase-admin-uid',
      name: 'Admin User',
      email: 'admin@test.com',
      role: 'admin',
    );
  }

  static UserProfile makeStaffProfile({
    String department = 'Road',
  }) {
    return UserProfile(
      id: 'mongo-staff-1',
      firebaseUid: 'firebase-staff-uid',
      name: 'Road Staff',
      email: 'staff@test.com',
      role: 'department_staff',
      department: department,
    );
  }

  static Map<String, dynamic> userProfileJson({
    String id = 'mongo-user-1',
    String name = 'Test User',
    String email = 'test@test.com',
    String role = 'citizen',
    String? department,
  }) => {
    '_id': id,
    'firebaseUid': 'firebase-uid-1',
    'name': name,
    'email': email,
    'role': role,
    'department': ?department,
    'createdAt': '2024-06-01T00:00:00.000Z',
  };
}
