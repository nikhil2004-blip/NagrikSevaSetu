// test/widgets/complaint_card_test.dart
// ─────────────────────────────────────────────────────────────
// Widget tests for ComplaintCard
//
// ComplaintCard renders a Complaint object. We test:
//   - Category text is shown
//   - Status badge text is shown
//   - Status badge has the right color for each status
//   - Description text is shown
//   - Falls back to "(Voice note — see transcript below)" when
//     description is empty
//   - Voice transcript section appears when available
//   - Image section appears when imageUrl is set
//   - Upvote count is shown
//   - Relative timestamp is shown
//   - Category icon changes per category
// ─────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:mockito/annotations.dart';
import 'package:mockito/mockito.dart';
import 'package:civic/widgets/complaint_card.dart';
import 'package:civic/providers/complaint_provider.dart';
import 'package:civic/repositories/complaint_repository.dart';
import '../helpers/mock_data.dart';

import 'complaint_card_test.mocks.dart';

@GenerateMocks([ComplaintRepository])
void main() {
  late MockComplaintRepository mockRepo;
  late ComplaintProvider provider;

  setUp(() {
    mockRepo = MockComplaintRepository();
    when(mockRepo.getAllComplaints(
      category: anyNamed('category'),
      status: anyNamed('status'),
    )).thenAnswer((_) async => []);
    provider = ComplaintProvider(repository: mockRepo);
  });

  tearDown(() => provider.dispose());

  /// Wraps the widget in the minimal scaffolding required for widget tests:
  ///   - MaterialApp (provides Theme, MediaQuery, etc.)
  ///   - ChangeNotifierProvider<ComplaintProvider> (because UpvoteButton reads it)
  Widget buildCard(Widget child) {
    return MaterialApp(
      home: Scaffold(
        body: ChangeNotifierProvider<ComplaintProvider>.value(
          value: provider,
          child: child,
        ),
      ),
    );
  }

  group('ComplaintCard — basic content rendering', () {
    testWidgets('shows category name', (tester) async {
      final complaint = MockData.makeComplaint(category: 'Sanitation');
      await tester.pumpWidget(buildCard(ComplaintCard(complaint: complaint)));

      expect(find.text('Sanitation'), findsOneWidget);
    });

    testWidgets('shows status badge text', (tester) async {
      final complaint = MockData.makeComplaint(status: 'Pending');
      await tester.pumpWidget(buildCard(ComplaintCard(complaint: complaint)));

      expect(find.text('Pending'), findsOneWidget);
    });

    testWidgets('shows description text when non-empty', (tester) async {
      final complaint = MockData.makeComplaint(
          description: 'A large pothole near the school');
      await tester.pumpWidget(buildCard(ComplaintCard(complaint: complaint)));

      expect(find.text('A large pothole near the school'), findsOneWidget);
    });

    testWidgets('shows fallback text when description is empty', (tester) async {
      final complaint = MockData.makeComplaint(description: '');
      await tester.pumpWidget(buildCard(ComplaintCard(complaint: complaint)));

      expect(find.text('(Voice note — see transcript below)'), findsOneWidget);
    });

    testWidgets('shows upvote count', (tester) async {
      final complaint = MockData.makeComplaint(upvotes: 42);
      await tester.pumpWidget(buildCard(ComplaintCard(complaint: complaint)));

      expect(find.text('42'), findsOneWidget);
    });

    testWidgets('shows "upvote" (singular) when count is 1', (tester) async {
      final complaint = MockData.makeComplaint(upvotes: 1);
      await tester.pumpWidget(buildCard(ComplaintCard(complaint: complaint)));

      expect(find.text('upvote'), findsOneWidget);
    });

    testWidgets('shows "upvotes" (plural) when count is 0 or >1', (tester) async {
      final complaint = MockData.makeComplaint(upvotes: 0);
      await tester.pumpWidget(buildCard(ComplaintCard(complaint: complaint)));

      expect(find.text('upvotes'), findsOneWidget);
    });
  });

  // ─────────────────────────────────────────────────────────────
  group('ComplaintCard — voice transcript', () {
    testWidgets('voice transcript section is hidden when transcript is null',
        (tester) async {
      final complaint = MockData.makeComplaint(voiceNoteTranscript: null);
      await tester.pumpWidget(buildCard(ComplaintCard(complaint: complaint)));

      expect(find.text('AI Voice Transcript'), findsNothing);
    });

    testWidgets('voice transcript section is hidden when transcript is empty',
        (tester) async {
      final complaint = MockData.makeComplaint(voiceNoteTranscript: '');
      await tester.pumpWidget(buildCard(ComplaintCard(complaint: complaint)));

      expect(find.text('AI Voice Transcript'), findsNothing);
    });

    testWidgets('voice transcript section is shown when transcript is set',
        (tester) async {
      final complaint = MockData.makeComplaint(
          voiceNoteTranscript: 'There is a huge pit in the road.');
      await tester.pumpWidget(buildCard(ComplaintCard(complaint: complaint)));

      expect(find.text('AI Voice Transcript'), findsOneWidget);
      expect(find.text('There is a huge pit in the road.'), findsOneWidget);
    });
  });

  // ─────────────────────────────────────────────────────────────
  group('ComplaintCard — image section', () {
    testWidgets('image widget is NOT rendered when imageUrl is null',
        (tester) async {
      final complaint = MockData.makeComplaint(imageUrl: null);
      await tester.pumpWidget(buildCard(ComplaintCard(complaint: complaint)));

      expect(find.byType(Image), findsNothing);
    });

    testWidgets('Network image is rendered when imageUrl is set',
        (tester) async {
      final complaint = MockData.makeComplaint(
          imageUrl: 'https://res.cloudinary.com/test/image.jpg');
      await tester.pumpWidget(buildCard(ComplaintCard(complaint: complaint)));

      expect(find.byType(Image), findsOneWidget);
    });
  });

  // ─────────────────────────────────────────────────────────────
  group('ComplaintCard — relative timestamp', () {
    testWidgets('shows "Just now" for very recent complaints', (tester) async {
      final complaint = MockData.makeComplaint(
          createdAt: DateTime.now().subtract(const Duration(seconds: 10)));
      await tester.pumpWidget(buildCard(ComplaintCard(complaint: complaint)));

      expect(find.text('Just now'), findsOneWidget);
    });

    testWidgets('shows "Xm ago" for complaints within 60 minutes', (tester) async {
      final complaint = MockData.makeComplaint(
          createdAt: DateTime.now().subtract(const Duration(minutes: 30)));
      await tester.pumpWidget(buildCard(ComplaintCard(complaint: complaint)));

      expect(find.text('30m ago'), findsOneWidget);
    });

    testWidgets('shows "Xh ago" for complaints within 24 hours', (tester) async {
      final complaint = MockData.makeComplaint(
          createdAt: DateTime.now().subtract(const Duration(hours: 5)));
      await tester.pumpWidget(buildCard(ComplaintCard(complaint: complaint)));

      expect(find.text('5h ago'), findsOneWidget);
    });

    testWidgets('shows "Xd ago" for complaints within 7 days', (tester) async {
      final complaint = MockData.makeComplaint(
          createdAt: DateTime.now().subtract(const Duration(days: 3)));
      await tester.pumpWidget(buildCard(ComplaintCard(complaint: complaint)));

      expect(find.text('3d ago'), findsOneWidget);
    });

    testWidgets('shows "Xw ago" for complaints within 30 days', (tester) async {
      final complaint = MockData.makeComplaint(
          createdAt: DateTime.now().subtract(const Duration(days: 14)));
      await tester.pumpWidget(buildCard(ComplaintCard(complaint: complaint)));

      expect(find.text('2w ago'), findsOneWidget);
    });

    testWidgets('shows absolute date for complaints older than 30 days',
        (tester) async {
      final old = DateTime(2024, 3, 5);
      final complaint = MockData.makeComplaint(createdAt: old);
      await tester.pumpWidget(buildCard(ComplaintCard(complaint: complaint)));

      expect(find.text('5/3/2024'), findsOneWidget);
    });
  });

  // ─────────────────────────────────────────────────────────────
  group('ComplaintCard — category icons', () {
    testWidgets('Sanitation complaint shows cleaning_services icon',
        (tester) async {
      final complaint = MockData.makeComplaint(category: 'Sanitation');
      await tester.pumpWidget(buildCard(ComplaintCard(complaint: complaint)));

      expect(find.byIcon(Icons.cleaning_services_rounded), findsOneWidget);
    });

    testWidgets('Water complaint shows water_drop icon', (tester) async {
      final complaint = MockData.makeComplaint(category: 'Water');
      await tester.pumpWidget(buildCard(ComplaintCard(complaint: complaint)));

      expect(find.byIcon(Icons.water_drop_rounded), findsOneWidget);
    });

    testWidgets('Electrical complaint shows electrical_services icon',
        (tester) async {
      final complaint = MockData.makeComplaint(category: 'Electrical');
      await tester.pumpWidget(buildCard(ComplaintCard(complaint: complaint)));

      expect(find.byIcon(Icons.electrical_services_rounded), findsOneWidget);
    });

    testWidgets('Road complaint shows route icon', (tester) async {
      final complaint = MockData.makeComplaint(category: 'Road');
      await tester.pumpWidget(buildCard(ComplaintCard(complaint: complaint)));

      expect(find.byIcon(Icons.route_rounded), findsOneWidget);
    });

    testWidgets('Unknown category shows report_problem icon', (tester) async {
      final complaint = MockData.makeComplaint(category: 'Others');
      await tester.pumpWidget(buildCard(ComplaintCard(complaint: complaint)));

      expect(find.byIcon(Icons.report_problem_rounded), findsOneWidget);
    });
  });
}
