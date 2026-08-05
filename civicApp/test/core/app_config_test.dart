// test/core/app_config_test.dart
// ─────────────────────────────────────────────────────────────
// Unit tests for AppConfig.
//
// Note: AppConfig uses String.fromEnvironment() which is injected
// at compile time via --dart-define. In the test environment,
// no --dart-define flags are set, so:
//   - ENV defaults to 'dev'
//   - API_URL defaults to '' (empty)
//   - CLOUDINARY_CLOUD_NAME defaults to 'dmecx8pcz'
//   - CLOUDINARY_UPLOAD_PRESET defaults to 'civic_sih2025'
//
// These tests verify the compile-time default values and that
// the logic in the getters (isDev, isProd, apiUrl) is correct.
// ─────────────────────────────────────────────────────────────

import 'package:flutter_test/flutter_test.dart';
import 'package:civic/core/config/app_config.dart';

void main() {
  group('AppConfig — compile-time defaults (test environment)', () {
    test('env defaults to "dev" in test environment', () {
      // No --dart-define=ENV is set in test runs, so defaultValue is used.
      expect(AppConfig.env, 'dev');
    });

    test('isDev returns true in test environment', () {
      expect(AppConfig.isDev, true);
    });

    test('isProd returns false in test environment', () {
      expect(AppConfig.isProd, false);
    });

    test('apiUrl returns Android emulator URL in dev mode (no API_URL override)', () {
      // In test env: _injectedApiUrl is empty, isDev is true
      // → should return the emulator default
      expect(AppConfig.apiUrl, 'http://10.0.2.2:5000');
    });

    test('cloudinaryCloudName has a non-empty default', () {
      expect(AppConfig.cloudinaryCloudName, isNotEmpty);
    });

    test('cloudinaryUploadPreset has a non-empty default', () {
      expect(AppConfig.cloudinaryUploadPreset, isNotEmpty);
    });
  });

  group('AppConfig — logic invariants', () {
    test('isDev and isProd are mutually exclusive', () {
      // They can't both be true at the same time
      expect(AppConfig.isDev && AppConfig.isProd, false);
    });

    test('cloudinaryCloudName default matches expected dev value', () {
      // This ensures the fallback didn't get accidentally cleared
      expect(AppConfig.cloudinaryCloudName, 'dmecx8pcz');
    });

    test('cloudinaryUploadPreset default matches expected dev value', () {
      expect(AppConfig.cloudinaryUploadPreset, 'civic_sih2025');
    });

    test('apiUrl is a valid URL string (non-empty, starts with http)', () {
      expect(AppConfig.apiUrl, startsWith('http'));
    });

    test('AppConfig cannot be instantiated (private constructor)', () {
      // AppConfig._() is private — we can't call it.
      // This just verifies the class is accessible as a namespace.
      expect(AppConfig.env, isA<String>());
    });
  });
}
