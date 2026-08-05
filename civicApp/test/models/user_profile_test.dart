// test/models/user_profile_test.dart
// ─────────────────────────────────────────────────────────────
// Unit tests for UserProfile.fromJson(), toSyncJson(),
// isStaff getter, and isAdmin getter.
// ─────────────────────────────────────────────────────────────

import 'package:flutter_test/flutter_test.dart';
import 'package:civic/models/user_profile.dart';
import '../helpers/mock_data.dart';

void main() {
  group('UserProfile.fromJson()', () {
    test('parses all standard fields correctly', () {
      final json = MockData.userProfileJson();
      final profile = UserProfile.fromJson(json);

      expect(profile.id, 'mongo-user-1');
      expect(profile.firebaseUid, 'firebase-uid-1');
      expect(profile.name, 'Test User');
      expect(profile.email, 'test@test.com');
      expect(profile.role, 'citizen');
    });

    test('uses _id as fallback when id is missing', () {
      final json = MockData.userProfileJson();
      json.remove('id');
      // _id should already be there from the factory
      json['_id'] = 'mongo-from-id';
      final profile = UserProfile.fromJson(json);

      expect(profile.id, 'mongo-from-id');
    });

    test('defaults name to "User" when missing', () {
      final json = MockData.userProfileJson();
      json.remove('name');
      final profile = UserProfile.fromJson(json);

      expect(profile.name, 'User');
    });

    test('defaults email to empty string when missing', () {
      final json = MockData.userProfileJson();
      json.remove('email');
      final profile = UserProfile.fromJson(json);

      expect(profile.email, '');
    });

    test('defaults role to "citizen" when missing', () {
      final json = MockData.userProfileJson();
      json.remove('role');
      final profile = UserProfile.fromJson(json);

      expect(profile.role, 'citizen');
    });

    test('parses phone number when present', () {
      final json = MockData.userProfileJson();
      json['phone'] = '+91-9876543210';
      final profile = UserProfile.fromJson(json);

      expect(profile.phone, '+91-9876543210');
    });

    test('phone is null when not present in JSON', () {
      final json = MockData.userProfileJson();
      json.remove('phone');
      final profile = UserProfile.fromJson(json);

      expect(profile.phone, isNull);
    });

    test('parses department field', () {
      final json = MockData.userProfileJson(
        role: 'department_staff',
        department: 'Road',
      );
      final profile = UserProfile.fromJson(json);

      expect(profile.department, 'Road');
    });

    test('reads deptCategory as fallback for department', () {
      final json = MockData.userProfileJson(role: 'department_staff');
      json['deptCategory'] = 'Water';
      final profile = UserProfile.fromJson(json);

      expect(profile.department, 'Water');
    });

    test('department is null when neither field is present', () {
      final json = MockData.userProfileJson();
      json.remove('department');
      json.remove('deptCategory');
      final profile = UserProfile.fromJson(json);

      expect(profile.department, isNull);
    });

    test('parses createdAt correctly', () {
      final json = MockData.userProfileJson();
      json['createdAt'] = '2024-06-01T00:00:00.000Z';
      final profile = UserProfile.fromJson(json);

      expect(profile.createdAt!.year, 2024);
      expect(profile.createdAt!.month, 6);
      expect(profile.createdAt!.day, 1);
    });

    test('createdAt is null when missing from JSON', () {
      final json = MockData.userProfileJson();
      json.remove('createdAt');
      final profile = UserProfile.fromJson(json);

      expect(profile.createdAt, isNull);
    });

    test('parses admin role', () {
      final json = MockData.userProfileJson(role: 'admin');
      final profile = UserProfile.fromJson(json);

      expect(profile.role, 'admin');
    });

    test('parses main_officer role', () {
      final json = MockData.userProfileJson(role: 'main_officer');
      final profile = UserProfile.fromJson(json);

      expect(profile.role, 'main_officer');
    });
  });

  // ─────────────────────────────────────────────────────────────
  group('UserProfile.toSyncJson()', () {
    test('includes name and email', () {
      final profile = MockData.makeCitizenProfile(
          name: 'Alice', email: 'alice@test.com');
      final json = profile.toSyncJson();

      expect(json['name'], 'Alice');
      expect(json['email'], 'alice@test.com');
    });

    test('omits phone when null', () {
      final profile = MockData.makeCitizenProfile(phone: null);
      final json = profile.toSyncJson();

      expect(json.containsKey('phone'), false);
    });

    test('includes phone when set', () {
      final profile = MockData.makeCitizenProfile(phone: '+91-9876543210');
      final json = profile.toSyncJson();

      expect(json['phone'], '+91-9876543210');
    });
  });

  // ─────────────────────────────────────────────────────────────
  group('UserProfile.isStaff getter', () {
    test('citizen → isStaff is false', () {
      expect(MockData.makeCitizenProfile().isStaff, false);
    });

    test('admin → isStaff is true', () {
      expect(MockData.makeAdminProfile().isStaff, true);
    });

    test('main_officer → isStaff is true', () {
      final profile = UserProfile.fromJson(MockData.userProfileJson(role: 'main_officer'));
      expect(profile.isStaff, true);
    });

    test('department_staff → isStaff is true', () {
      expect(MockData.makeStaffProfile().isStaff, true);
    });
  });

  // ─────────────────────────────────────────────────────────────
  group('UserProfile.isAdmin getter', () {
    test('citizen → isAdmin is false', () {
      expect(MockData.makeCitizenProfile().isAdmin, false);
    });

    test('admin → isAdmin is true', () {
      expect(MockData.makeAdminProfile().isAdmin, true);
    });

    test('main_officer → isAdmin is false', () {
      final profile = UserProfile.fromJson(MockData.userProfileJson(role: 'main_officer'));
      expect(profile.isAdmin, false);
    });

    test('department_staff → isAdmin is false', () {
      expect(MockData.makeStaffProfile().isAdmin, false);
    });
  });
}
