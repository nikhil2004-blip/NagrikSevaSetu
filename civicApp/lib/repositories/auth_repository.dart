// lib/repositories/auth_repository.dart
// ─────────────────────────────────────────────────────────────
// Auth Repository
//
// Responsibilities:
//   1. Call POST /api/users/sync after Firebase sign-in/sign-up
//      to create or update the user in MongoDB.
//   2. Call GET /api/users/me to fetch the current user's profile
//      (role, department, etc.) from MongoDB.
//
// WHY this exists:
//   Firebase Auth only stores uid, email, displayName.
//   Our backend's MongoDB User document stores role and department.
//   After every login, the app MUST call /sync to ensure the
//   MongoDB record is up-to-date, and then fetch the role so
//   the UI can show or hide staff-only features.
// ─────────────────────────────────────────────────────────────

import '../core/network/api_client.dart';
import '../models/user_profile.dart';

class AuthRepository {
  final ApiClient _apiClient;

  AuthRepository({required ApiClient apiClient}) : _apiClient = apiClient;

  /// Syncs Firebase user data to MongoDB.
  /// Called immediately after sign-in or sign-up.
  ///
  /// Uses an upsert operation on the backend (safe to call multiple times).
  /// Returns the full [UserProfile] from MongoDB.
  Future<UserProfile> syncUser({
    required String name,
    required String email,
    String? phone,
  }) async {
    final response = await _apiClient.post<Map<String, dynamic>>(
      '/api/users/sync',
      data: {
        'name': name,
        'email': email,
        'phone': ?phone,
      },
    );

    final data = response.data!['data'] as Map<String, dynamic>;
    return UserProfile.fromJson(data);
  }

  /// Fetches the current authenticated user's MongoDB profile.
  Future<UserProfile> getMyProfile() async {
    final response = await _apiClient.get<Map<String, dynamic>>('/api/users/me');
    final data = response.data!['data'] as Map<String, dynamic>;
    return UserProfile.fromJson(data);
  }

  /// Sends the FCM device token to the backend for push notifications
  Future<void> registerFcmToken(String token) async {
    await _apiClient.post<Map<String, dynamic>>(
      '/api/users/fcm-token',
      data: {'token': token},
    );
  }
}
