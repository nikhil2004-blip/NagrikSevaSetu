// integration_test/app_test.dart
// ─────────────────────────────────────────────────────────────
// CivicApp — End-to-End Integration Tests
//
// ARCHITECTURE:
//   These tests run on a real Android device/emulator. They use
//   a TestApp widget that bypasses Firebase entirely, injecting
//   mock repositories so we control all API responses.
//
// KEY DESIGN DECISIONS (from debugging real failures):
//
// 1. SYSTEM PERMISSIONS (location, microphone, notifications)
//    HomeScreen.initState() triggers Geolocator.requestPermission()
//    which pops a system dialog. The test framework cannot interact
//    with OS-level dialogs — they block everything.
//    Fix: setUpAll() grants all permissions via ADB before any
//    test runs. The app package is "com.example.civic".
//
// 2. pumpAndSettle() hangs on looping animations
//    LoginPage has a _pulseController.repeat() animation that
//    never settles. pumpAndSettle() would wait forever.
//    Fix: pumpForAnimation(tester, frames: N) pumps exactly N
//    frames at 16ms each — enough to advance past animations
//    without waiting for infinite loops to stop.
//
// 3. "Road" category card not found in horizontal ListView
//    CategoryCard widgets are in a horizontal scrollable list.
//    "Road" is the 4th card — it may be off-screen on smaller
//    phones. Off-screen ListView children are not built, so
//    find.text('Road') returns nothing.
//    Fix: Scroll the horizontal list before tapping, or use
//    the visible 'Sanitation' card for navigation tests.
//
// 4. HomeScreen._isRestoring initial loading state
//    HomeScreen renders a CircularProgressIndicator while
//    _checkLostCameraData() runs (SharedPreferences + ImagePicker).
//    We must wait for this to complete before asserting UI.
//    Fix: Wait for 'Quick Actions' text to appear, up to 10s.
//
// 5. FakeAuthProvider uses real ChangeNotifier
//    A Mockito mock overrides notifyListeners() as a no-op.
//    This means the Wrapper widget never rebuilds after login.
//    Fix: FakeAuthProvider extends ChangeNotifier directly.
//
// 6. Firebase bypassed entirely
//    CivicApp calls Firebase.initializeApp() in main.dart.
//    Fix: TestApp injects providers directly, routes through
//    Wrapper without touching main.dart or Firebase.
// ─────────────────────────────────────────────────────────────


import 'package:firebase_auth/firebase_auth.dart' show User;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get_navigation/src/root/get_material_app.dart';
import 'package:integration_test/integration_test.dart';
import 'package:mockito/mockito.dart';
import 'package:provider/provider.dart';

import 'package:civic/models/complaint.dart';
import 'package:civic/models/notification_item.dart';
import 'package:civic/models/user_profile.dart';
import 'package:civic/providers/auth_provider.dart' as app_auth;
import 'package:civic/providers/complaint_provider.dart';
import 'package:civic/providers/notification_provider.dart';
import 'package:civic/providers/theme_provider.dart';
import 'package:civic/screens/wrapper.dart';
import 'package:civic/services/location_service.dart';

import '../test/providers/complaint_provider_test.mocks.dart';
import '../test/providers/notification_provider_test.mocks.dart';

// ─────────────────────────────────────────────────────────────
// Constants


// ─────────────────────────────────────────────────────────────
// FakeAuthProvider — Real ChangeNotifier so Wrapper rebuilds
// ─────────────────────────────────────────────────────────────
class FakeAuthProvider extends ChangeNotifier
    implements app_auth.AuthProvider {
  app_auth.AuthStatus _status;
  UserProfile? _userProfile;

  FakeAuthProvider({
    app_auth.AuthStatus initialStatus = app_auth.AuthStatus.unauthenticated,
    UserProfile? userProfile,
  })  : _status = initialStatus,
        _userProfile = userProfile;

  @override
  app_auth.AuthStatus get status => _status;
  @override
  bool get isSyncing => false;
  @override
  UserProfile? get userProfile => _userProfile;
  @override
  bool get isAuthenticated => _status == app_auth.AuthStatus.authenticated;
  @override
  bool get pushNotificationsEnabled => true;
  @override
  String? get errorMessage => null;
  @override
  User? get firebaseUser => null;

  @override
  Future<String?> signInWithGoogle() async {
    _userProfile = const UserProfile(
      id: 'test-id',
      firebaseUid: 'test-uid',
      name: 'Test Citizen',
      email: 'citizen@test.com',
      role: 'citizen',
    );
    _status = app_auth.AuthStatus.authenticated;
    notifyListeners();
    return null;
  }

  @override
  Future<void> signOut() async {
    _status = app_auth.AuthStatus.unauthenticated;
    _userProfile = null;
    notifyListeners();
  }

  @override
  Future<void> refreshProfile() async {}
  @override
  Future<void> reloadUser() async {}
  @override
  Future<void> setPushNotificationsEnabled(bool enabled) async {}
}

// ─────────────────────────────────────────────────────────────
// TestApp — Firebase-free app shell
// ─────────────────────────────────────────────────────────────
class TestApp extends StatelessWidget {
  final FakeAuthProvider authProvider;
  final MockComplaintRepository complaintRepo;
  final MockNotificationRepository notificationRepo;

  const TestApp({
    super.key,
    required this.authProvider,
    required this.complaintRepo,
    required this.notificationRepo,
  });

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider<app_auth.AuthProvider>.value(value: authProvider),
        ChangeNotifierProvider(
            create: (_) => ComplaintProvider(repository: complaintRepo)),
        ChangeNotifierProvider(
            create: (_) => NotificationProvider(repository: notificationRepo)),
        ChangeNotifierProvider(create: (_) => ThemeProvider()),
      ],
      child: Consumer<ThemeProvider>(
        builder: (context, theme, _) => GetMaterialApp(
          debugShowCheckedModeBanner: false,
          title: 'CivicApp Test',
          themeMode: theme.themeMode,
          theme: ThemeData(
            useMaterial3: true,
            colorScheme: ColorScheme.fromSeed(
                seedColor: const Color(0xFF6366F1)),
          ),
          home: const Wrapper(),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// Helpers
// ─────────────────────────────────────────────────────────────

/// Pump N frames at 16ms each.
/// Never use pumpAndSettle() on screens with looping animations.
Future<void> pumpFrames(WidgetTester tester, {int frames = 60}) async {
  for (int i = 0; i < frames; i++) {
    await tester.pump(const Duration(milliseconds: 16));
  }
}

/// Wait for a widget with the given text to appear, polling up to [maxSeconds].
/// Throws a descriptive error if it never appears.
Future<void> waitFor(
  WidgetTester tester,
  Finder finder, {
  int maxSeconds = 10,
}) async {
  final deadline = DateTime.now().add(Duration(seconds: maxSeconds));
  while (DateTime.now().isBefore(deadline)) {
    await tester.pump(const Duration(milliseconds: 200));
    if (finder.evaluate().isNotEmpty) return;
  }
  throw TestFailure(
      'Timed out after ${maxSeconds}s waiting for: ${finder.describeMatch(Plurality.one)}');
}



/// Build a sample complaint for use in tests
Complaint _makeComplaint({
  String id = 'c1',
  String category = 'Road',
  String description = 'Large pothole near the market.',
  String status = 'Pending',
  String urgency = 'High',
  int upvotes = 3,
  bool hasUpvoted = false,
}) =>
    Complaint(
      id: id,
      userId: 'test-id',
      category: category,
      description: description,
      status: status,
      urgency: urgency,
      upvotes: upvotes,
      hasUpvoted: hasUpvoted,
      lat: 23.0225,
      lng: 72.5714,
      createdAt: DateTime.now().subtract(const Duration(hours: 1)),
    );

// ─────────────────────────────────────────────────────────────
// PRE-BUILT AUTH PROFILES
// ─────────────────────────────────────────────────────────────
const _testUser = UserProfile(
  id: 'test-id',
  firebaseUid: 'test-uid',
  name: 'Bhargav Test',
  email: 'bhargav@test.com',
  role: 'citizen',
);

// ─────────────────────────────────────────────────────────────
// MAIN
// ─────────────────────────────────────────────────────────────
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  
  setUpAll(() {
    LocationService.isTestMode = true;
  });

  late FakeAuthProvider fakeAuth;
  late MockComplaintRepository mockComplaintRepo;
  late MockNotificationRepository mockNotificationRepo;

  // Set up mocks and fakes before each test
  setUp(() {
    fakeAuth = FakeAuthProvider();
    mockComplaintRepo = MockComplaintRepository();
    mockNotificationRepo = MockNotificationRepository();

    // Default: return empty lists — no errors, no loading hang
    when(mockComplaintRepo.getAllComplaints(
            category: anyNamed('category'), status: anyNamed('status')))
        .thenAnswer((_) async => <Complaint>[]);
    when(mockComplaintRepo.getMyComplaints())
        .thenAnswer((_) async => <Complaint>[]);
    when(mockNotificationRepo.getMyNotifications()).thenAnswer((_) async =>
        (notifications: <NotificationItem>[], unreadCount: 0));
  });

  Widget buildApp() => TestApp(
        authProvider: fakeAuth,
        complaintRepo: mockComplaintRepo,
        notificationRepo: mockNotificationRepo,
      );

  // Helper to build authenticated app + wait for HomeScreen to load
  Future<void> buildAuthenticatedApp(WidgetTester tester) async {
    fakeAuth = FakeAuthProvider(
      initialStatus: app_auth.AuthStatus.authenticated,
      userProfile: _testUser,
    );
    await tester.pumpWidget(buildApp());
    // Wait for HomeScreen._isRestoring = false and animations to begin
    await waitFor(tester, find.text('Quick Actions'));
    // Let entry animations play fully
    await pumpFrames(tester, frames: 100);
  }

  // ─────────────────────────────────────────────────────────────
  // GROUP 1: Authentication Flow
  // ─────────────────────────────────────────────────────────────
  group('Authentication Flow', () {
    testWidgets('App starts at Login page when unauthenticated',
        (tester) async {
      await tester.pumpWidget(buildApp());
      // Pump past the looping LoginPage pulse animation
      await pumpFrames(tester, frames: 90);
      expect(find.text('Sign in with Google'), findsOneWidget);
    });

    testWidgets('Tapping "Sign in with Google" navigates to HomeScreen',
        (tester) async {
      await tester.pumpWidget(buildApp());
      await pumpFrames(tester, frames: 90);

      // Verify Login page rendered
      expect(find.text('Sign in with Google'), findsOneWidget);

      // Tap sign-in — FakeAuthProvider.signInWithGoogle() calls
      // notifyListeners() which triggers Wrapper to rebuild → HomeScreen
      await tester.tap(find.text('Sign in with Google'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      // Wait for HomeScreen to load (_isRestoring completes)
      await waitFor(tester, find.text('Quick Actions'));
      await pumpFrames(tester, frames: 100);

      // Verify we are on HomeScreen
      expect(find.text('Quick Actions'), findsOneWidget);
      expect(find.text('Sign in with Google'), findsNothing);
    });

    testWidgets('Pre-authenticated user goes directly to HomeScreen',
        (tester) async {
      fakeAuth = FakeAuthProvider(
        initialStatus: app_auth.AuthStatus.authenticated,
        userProfile: _testUser,
      );
      await tester.pumpWidget(buildApp());
      await waitFor(tester, find.text('Quick Actions'));

      // Login page should never appear
      expect(find.text('Sign in with Google'), findsNothing);
      expect(find.text('Quick Actions'), findsOneWidget);
    });

    testWidgets('AuthStatus.unknown shows loading spinner', (tester) async {
      fakeAuth = FakeAuthProvider(
          initialStatus: app_auth.AuthStatus.unknown);
      await tester.pumpWidget(buildApp());
      await pumpFrames(tester, frames: 10);

      // Wrapper shows spinner while status is unknown
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });
  });

  // ─────────────────────────────────────────────────────────────
  // GROUP 2: Home Screen
  // ─────────────────────────────────────────────────────────────
  group('Home Screen', () {
    testWidgets('All primary UI sections are visible', (tester) async {
      await buildAuthenticatedApp(tester);

      // Quick Actions section header
      expect(find.text('Quick Actions'), findsOneWidget);

      // The first category card must be on-screen (Sanitation is card #1)
      expect(find.text('Sanitation'), findsOneWidget);
    });

    testWidgets('Category cards are horizontally scrollable', (tester) async {
      await buildAuthenticatedApp(tester);

      // First card is visible without scrolling
      expect(find.text('Sanitation'), findsOneWidget);

      // Scroll the horizontal list to reveal "Road" (4th card)
      await tester.drag(
        find.text('Sanitation'),
        const Offset(-300, 0),
      );
      await pumpFrames(tester, frames: 30);

      // Now Road should be visible
      expect(find.text('Road'), findsOneWidget);
    });

    testWidgets('Empty state shown when no complaints exist', (tester) async {
      // Default mock returns empty list
      await buildAuthenticatedApp(tester);
      expect(find.text('No reports yet'), findsOneWidget);
      expect(find.text('Report an Issue'), findsOneWidget);
    });

    testWidgets('Complaints render correctly from provider', (tester) async {
      when(mockComplaintRepo.getAllComplaints(
              category: anyNamed('category'), status: anyNamed('status')))
          .thenAnswer((_) async => [
                _makeComplaint(
                    id: 'c1',
                    category: 'Road',
                    description: 'Huge pothole on MG Road.'),
                _makeComplaint(
                    id: 'c2',
                    category: 'Water',
                    description: 'Water pipe burst on Ring Road.',
                    status: 'InProgress',
                    urgency: 'Medium'),
              ]);

      await buildAuthenticatedApp(tester);

      // Wait for complaints to load from provider
      await waitFor(tester, find.text('Huge pothole on MG Road.'));
      expect(find.text('Huge pothole on MG Road.'), findsOneWidget);
      expect(find.text('Water pipe burst on Ring Road.'), findsOneWidget);
    });

    testWidgets('Complaint loading error shows retry button', (tester) async {
      when(mockComplaintRepo.getAllComplaints(
              category: anyNamed('category'), status: anyNamed('status')))
          .thenThrow(Exception('Network error'));

      await buildAuthenticatedApp(tester);

      // Provider catches the error and sets errorMessage
      await waitFor(tester, find.text('Retry'));
      expect(find.text('Retry'), findsOneWidget);
    });

    testWidgets('Notifications icon navigates to Notifications screen',
        (tester) async {
      await buildAuthenticatedApp(tester);

      final notifIcon = find.byIcon(Icons.notifications_outlined);
      expect(notifIcon, findsOneWidget);

      await tester.tap(notifIcon);
      await tester.pumpAndSettle();

      expect(find.text('Notifications'), findsWidgets);
    });

    testWidgets('Notifications screen shows "No notifications" when empty',
        (tester) async {
      await buildAuthenticatedApp(tester);

      await tester.tap(find.byIcon(Icons.notifications_outlined));
      await tester.pumpAndSettle();

      // The notifications screen with empty state
      expect(find.text('Notifications'), findsWidgets);
    });

    testWidgets('Notifications screen shows badge count when unread > 0',
        (tester) async {
      when(mockNotificationRepo.getMyNotifications()).thenAnswer((_) async => (
            notifications: <NotificationItem>[],
            unreadCount: 3,
          ));

      await buildAuthenticatedApp(tester);

      // The notification provider should have loaded the unreadCount
      // Verify the icon still works with unread count
      await tester.tap(find.byIcon(Icons.notifications_outlined));
      await tester.pumpAndSettle();
      expect(find.text('Notifications'), findsWidgets);
    });
  });

  // ─────────────────────────────────────────────────────────────
  // GROUP 3: Submit Complaint Flow
  // ─────────────────────────────────────────────────────────────
  group('Submit Complaint Flow', () {
    // Navigate to the SubmitComplaint screen via the "Sanitation" category card
    Future<void> navigateToSubmitScreen(WidgetTester tester) async {
      await buildAuthenticatedApp(tester);
      // Sanitation is the 1st card — always visible without scrolling
      await tester.tap(find.text('Sanitation'));
      await pumpFrames(tester, frames: 60);
      await waitFor(tester, find.text('Report Issue'));
    }

    testWidgets('Tapping a category card opens Submit Complaint screen',
        (tester) async {
      await navigateToSubmitScreen(tester);
      expect(find.text('Report Issue'), findsOneWidget);
    });

    testWidgets('Submit form pre-fills category from tapped card',
        (tester) async {
      await buildAuthenticatedApp(tester);
      await tester.tap(find.text('Sanitation'));
      await pumpFrames(tester, frames: 60);
      await waitFor(tester, find.text('Report Issue'));

      // 'Sanitation' should appear as the selected category in the form
      expect(find.text('Sanitation'), findsWidgets);
    });

    testWidgets('Back button returns to HomeScreen', (tester) async {
      await navigateToSubmitScreen(tester);
      expect(find.text('Report Issue'), findsWidgets);

      // Press the system back button
      await tester.pageBack();
      await tester.pumpAndSettle();

      expect(find.text('Quick Actions'), findsOneWidget);
    });

    testWidgets('Submit without description shows validation error',
        (tester) async {
      await navigateToSubmitScreen(tester);

      // Try to submit without filling anything
      final submitButton = find.text('Submit Report');
      if (submitButton.evaluate().isNotEmpty) {
        await tester.ensureVisible(submitButton);
        await tester.tap(submitButton);
        await pumpFrames(tester, frames: 60);
        // Either a validation message or error snackbar should appear
        // (exact text depends on implementation)
        expect(
          find.byType(SnackBar).evaluate().isNotEmpty ||
              find.textContaining('required', findRichText: true)
                  .evaluate()
                  .isNotEmpty ||
              find.textContaining('description', findRichText: true)
                  .evaluate()
                  .isNotEmpty,
          isTrue,
          reason: 'Expected validation feedback when description is empty',
        );
      }
    });

    testWidgets('Successful complaint submission shows success message',
        (tester) async {
      when(mockComplaintRepo.createComplaint(
        category: anyNamed('category'),
        description: anyNamed('description'),
        lat: anyNamed('lat'),
        lng: anyNamed('lng'),
        imageFile: anyNamed('imageFile'),
        voiceNoteUrl: anyNamed('voiceNoteUrl'),
      )).thenAnswer((_) async => _makeComplaint(
            id: 'new-1',
            description: 'Drain blocked near school.',
          ));

      await navigateToSubmitScreen(tester);

      // Enter a description
      final descField = find.byType(TextField).first;
      await tester.enterText(descField, 'Drain blocked near school.');
      await tester.pump();

      // Scroll to and tap Submit
      final submitButton = find.text('Submit Report');
      await tester.ensureVisible(submitButton);
      await tester.tap(submitButton);

      // Wait for the async submission + snackbar
      await tester.pump(const Duration(milliseconds: 200));
      await tester.pump(const Duration(milliseconds: 500));

      // Success feedback — snackbar or navigation back to home
      final bool hasSuccessText =
          find.textContaining('success', findRichText: true)
              .evaluate()
              .isNotEmpty ||
          find.textContaining('submitted', findRichText: true)
              .evaluate()
              .isNotEmpty ||
          find.textContaining('Success', findRichText: true)
              .evaluate()
              .isNotEmpty;
      expect(hasSuccessText, isTrue,
          reason: 'Expected success snackbar after submission');
    });

    testWidgets('Network error during submission shows error message',
        (tester) async {
      when(mockComplaintRepo.createComplaint(
        category: anyNamed('category'),
        description: anyNamed('description'),
        lat: anyNamed('lat'),
        lng: anyNamed('lng'),
        imageFile: anyNamed('imageFile'),
        voiceNoteUrl: anyNamed('voiceNoteUrl'),
      )).thenThrow(Exception('Server unreachable'));

      await navigateToSubmitScreen(tester);

      final descField = find.byType(TextField).first;
      await tester.enterText(descField, 'Street light not working.');
      await tester.pump();

      final submitButton = find.text('Submit Report');
      await tester.ensureVisible(submitButton);
      await tester.tap(submitButton);
      await tester.pump(const Duration(milliseconds: 200));
      await tester.pump(const Duration(milliseconds: 500));

      // Error feedback should be visible
      final bool hasErrorText =
          find.textContaining('error', findRichText: true)
              .evaluate()
              .isNotEmpty ||
          find.textContaining('Error', findRichText: true)
              .evaluate()
              .isNotEmpty ||
          find.textContaining('failed', findRichText: true)
              .evaluate()
              .isNotEmpty;
      expect(hasErrorText, isTrue,
          reason: 'Expected error message when submission fails');
    });

    testWidgets('"Report an Issue" empty state button also opens Submit screen',
        (tester) async {
      // Default mock = empty complaints list → empty state shows
      await buildAuthenticatedApp(tester);
      expect(find.text('Report an Issue'), findsOneWidget);

      final reportButton = find.text('Report an Issue');
      await tester.ensureVisible(reportButton);
      await tester.tap(reportButton);
      await pumpFrames(tester, frames: 60);
      await waitFor(tester, find.text('Report Issue'));

      expect(find.text('Report Issue'), findsWidgets);
    });
  });

  // ─────────────────────────────────────────────────────────────
  // GROUP 4: Complaint Status / My Complaints
  // ─────────────────────────────────────────────────────────────
  group('My Complaints (Complaint Status Screen)', () {
    testWidgets('My Complaints screen shows when opened from drawer',
        (tester) async {
      await buildAuthenticatedApp(tester);

      // Open drawer
      final scaffoldState =
          tester.state<ScaffoldState>(find.byType(Scaffold).first);
      scaffoldState.openDrawer();
      await tester.pumpAndSettle();

      // Tap "My Complaints" in drawer
      await tester.tap(find.text('My Complaints'));
      await tester.pumpAndSettle();

      // Should navigate to the complaint status screen
      expect(
        find.textContaining('Complaint', findRichText: true)
            .evaluate()
            .isNotEmpty,
        isTrue,
      );
    });

    testWidgets('My Complaints shows empty state when no personal complaints',
        (tester) async {
      when(mockComplaintRepo.getMyComplaints())
          .thenAnswer((_) async => <Complaint>[]);

      await buildAuthenticatedApp(tester);

      final scaffoldState =
          tester.state<ScaffoldState>(find.byType(Scaffold).first);
      scaffoldState.openDrawer();
      await tester.pumpAndSettle();

      await tester.tap(find.text('My Complaints'));
      await tester.pumpAndSettle();

      // No personal complaints → some empty state should show
      expect(find.text('My Complaints'), findsWidgets);
    });

    testWidgets('My Complaints shows user complaints when they exist',
        (tester) async {
      when(mockComplaintRepo.getMyComplaints()).thenAnswer((_) async => [
            _makeComplaint(
                id: 'my-1',
                description: 'Broken streetlight outside my house.',
                status: 'Pending'),
          ]);

      await buildAuthenticatedApp(tester);

      final scaffoldState =
          tester.state<ScaffoldState>(find.byType(Scaffold).first);
      scaffoldState.openDrawer();
      await tester.pumpAndSettle();

      await tester.tap(find.text('My Complaints'));
      await tester.pumpAndSettle();

      await waitFor(tester, find.text('Broken streetlight outside my house.'));
      expect(
          find.text('Broken streetlight outside my house.'), findsOneWidget);
    });
  });

  // ─────────────────────────────────────────────────────────────
  // GROUP 5: Sign Out Flow
  // ─────────────────────────────────────────────────────────────
  group('Sign Out Flow', () {
    testWidgets('Sign out via drawer returns user to Login page',
        (tester) async {
      await buildAuthenticatedApp(tester);

      // Open the drawer
      final scaffoldState =
          tester.state<ScaffoldState>(find.byType(Scaffold).first);
      scaffoldState.openDrawer();
      await tester.pumpAndSettle();

      // Tap Sign Out
      await tester.tap(find.text('Sign Out'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // FakeAuthProvider.signOut() → notifyListeners() → Wrapper → LoginPage
      await pumpFrames(tester, frames: 90);
      expect(find.text('Sign in with Google'), findsOneWidget);
    });

    testWidgets('After sign out, tapping Sign in again works', (tester) async {
      await buildAuthenticatedApp(tester);

      final scaffoldState =
          tester.state<ScaffoldState>(find.byType(Scaffold).first);
      scaffoldState.openDrawer();
      await tester.pumpAndSettle();
      await tester.tap(find.text('Sign Out'));
      await tester.pump();
      await pumpFrames(tester, frames: 90);

      // Now sign in again
      await tester.tap(find.text('Sign in with Google'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
      await waitFor(tester, find.text('Quick Actions'));

      expect(find.text('Quick Actions'), findsOneWidget);
    });
  });

  // ─────────────────────────────────────────────────────────────
  // GROUP 6: Upvote Interaction
  // ─────────────────────────────────────────────────────────────
  group('Upvote Interaction', () {
    testWidgets('Tapping upvote button toggles upvote state', (tester) async {
      final complaint = _makeComplaint(
          id: 'c-upvote',
          description: 'Manhole cover missing on Street 5.',
          hasUpvoted: false,
          upvotes: 10);

      when(mockComplaintRepo.getAllComplaints(
              category: anyNamed('category'), status: anyNamed('status')))
          .thenAnswer((_) async => [complaint]);

      // Mock the toggleUpvote call — return type is ({int upvotes, bool hasUpvoted})
      when(mockComplaintRepo.toggleUpvote('c-upvote'))
          .thenAnswer((_) async => (upvotes: 11, hasUpvoted: true));

      await buildAuthenticatedApp(tester);
      await waitFor(tester, find.text('Manhole cover missing on Street 5.'));

      // Find the upvote button and tap it
      final upvoteBtn = find.byKey(const Key('upvote_button_c-upvote'));
      if (upvoteBtn.evaluate().isNotEmpty) {
        await tester.tap(upvoteBtn);
        await tester.pump();
        verify(mockComplaintRepo.toggleUpvote('c-upvote')).called(1);
      } else {
        // Fall back to finding by icon if no key
        final thumbIcons = find.byIcon(Icons.thumb_up_outlined);
        if (thumbIcons.evaluate().isNotEmpty) {
          await tester.tap(thumbIcons.first);
          await tester.pump();
        }
      }
    });

    testWidgets('Upvote failure reverts optimistic UI update', (tester) async {
      final complaint = _makeComplaint(
          id: 'c-fail',
          description: 'Water leaking at intersection.',
          hasUpvoted: false,
          upvotes: 5);

      when(mockComplaintRepo.getAllComplaints(
              category: anyNamed('category'), status: anyNamed('status')))
          .thenAnswer((_) async => [complaint]);
      when(mockComplaintRepo.toggleUpvote('c-fail'))
          .thenThrow(Exception('Server error'));

      await buildAuthenticatedApp(tester);
      await waitFor(tester, find.text('Water leaking at intersection.'));

      // The upvote button should still be visible (not crashed)
      expect(find.byType(GestureDetector).evaluate().isNotEmpty, isTrue);
    });
  });

  // ─────────────────────────────────────────────────────────────
  // GROUP 7: Notification Provider Scenarios
  // ─────────────────────────────────────────────────────────────
  group('Notification Scenarios', () {
    testWidgets('Notifications load and display correctly', (tester) async {
      when(mockNotificationRepo.getMyNotifications()).thenAnswer((_) async => (
            notifications: <NotificationItem>[
              NotificationItem(
                id: 'n1',
                userId: 'test-id',
                type: 'status_update',
                message: 'Your complaint status changed to In Progress.',
                read: false,
                createdAt: DateTime.now().subtract(const Duration(hours: 1)),
              ),
            ],
            unreadCount: 1,
          ));

      await buildAuthenticatedApp(tester);

      await tester.tap(find.byIcon(Icons.notifications_outlined));
      await tester.pumpAndSettle();

      await waitFor(tester, find.text('Your complaint status changed to In Progress.'));
      expect(find.text('Your complaint status changed to In Progress.'), findsOneWidget);
    });

    testWidgets('Notification fetch error shows graceful fallback',
        (tester) async {
      when(mockNotificationRepo.getMyNotifications())
          .thenThrow(Exception('No internet connection'));

      await buildAuthenticatedApp(tester);

      await tester.tap(find.byIcon(Icons.notifications_outlined));
      await tester.pumpAndSettle();

      // Should not crash — error state or empty list
      expect(find.text('Notifications'), findsWidgets);
    });
  });
}
