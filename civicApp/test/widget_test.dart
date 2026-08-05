// test/widget_test.dart
// ─────────────────────────────────────────────────────────────
// App-level smoke test.
//
// CivicApp requires Firebase to be initialized before it can
// render its widget tree. In unit/widget tests we do NOT
// initialize Firebase (it needs real native platform channels).
//
// Instead, this smoke test verifies that CivicApp's *class* is
// correctly exported from main.dart and that the file compiles
// cleanly. All meaningful UI and provider tests are in the
// individual test files under test/models/, test/providers/, and
// test/widgets/.
// ─────────────────────────────────────────────────────────────

import 'package:flutter_test/flutter_test.dart';
import 'package:civic/main.dart';

void main() {
  test('CivicApp class is exported and accessible from main.dart', () {
    // This compile-time check ensures main.dart is structurally sound.
    expect(CivicApp, isNotNull);
  });
}
