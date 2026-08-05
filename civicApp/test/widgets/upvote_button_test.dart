// test/widgets/upvote_button_test.dart
// ─────────────────────────────────────────────────────────────
// Widget tests for UpvoteButton
//
// UpvoteButton is a "connected" widget: it reads hasUpvoted from
// ComplaintProvider and calls toggleUpvote when tapped.
//
// Tests:
//   - Shows thumb_up_outlined icon when NOT upvoted
//   - Shows thumb_up (filled) icon when upvoted
//   - Calls provider.toggleUpvote when tapped
//   - Renders gracefully when complaint is not found in provider
// ─────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:mockito/annotations.dart';
import 'package:mockito/mockito.dart';
import 'package:civic/widgets/upvote_button.dart';
import 'package:civic/providers/complaint_provider.dart';
import 'package:civic/repositories/complaint_repository.dart';
import '../helpers/mock_data.dart';

import 'upvote_button_test.mocks.dart';

@GenerateMocks([ComplaintRepository])
void main() {
  late MockComplaintRepository mockRepo;
  late ComplaintProvider provider;

  Widget buildButton(String complaintId) {
    return MaterialApp(
      home: Scaffold(
        body: ChangeNotifierProvider<ComplaintProvider>.value(
          value: provider,
          child: UpvoteButton(complaintId: complaintId),
        ),
      ),
    );
  }

  setUp(() {
    mockRepo = MockComplaintRepository();
    provider = ComplaintProvider(repository: mockRepo);
  });

  tearDown(() => provider.dispose());

  Future<void> seedProvider(
    WidgetTester tester, {
    required bool hasUpvoted,
    int upvotes = 0,
  }) async {
    final complaint = MockData.makeComplaint(
      id: 'c-1',
      hasUpvoted: hasUpvoted,
      upvotes: upvotes,
    );
    when(mockRepo.getAllComplaints(
      category: anyNamed('category'),
      status: anyNamed('status'),
    )).thenAnswer((_) async => [complaint]);
    await provider.loadAllComplaints();
    await tester.pump();
  }

  group('UpvoteButton — icon state', () {
    testWidgets('shows outlined thumb icon when NOT upvoted', (tester) async {
      await tester.pumpWidget(buildButton('c-1'));
      await seedProvider(tester, hasUpvoted: false);
      await tester.pump();

      expect(find.byIcon(Icons.thumb_up_outlined), findsOneWidget);
      expect(find.byIcon(Icons.thumb_up), findsNothing);
    });

    testWidgets('shows filled thumb icon when upvoted', (tester) async {
      await tester.pumpWidget(buildButton('c-1'));
      await seedProvider(tester, hasUpvoted: true, upvotes: 1);
      await tester.pump();

      expect(find.byIcon(Icons.thumb_up), findsOneWidget);
    });

    testWidgets('shows outlined icon when complaint is not in provider', (tester) async {
      // 'nonexistent' not in provider — defaults to hasUpvoted: false
      await tester.pumpWidget(buildButton('nonexistent'));
      await tester.pump();

      expect(find.byIcon(Icons.thumb_up_outlined), findsOneWidget);
    });
  });

  group('UpvoteButton — tap interaction', () {
    testWidgets('calls toggleUpvote when tapped', (tester) async {
      await tester.pumpWidget(buildButton('c-1'));
      await seedProvider(tester, hasUpvoted: false, upvotes: 0);
      await tester.pump();

      when(mockRepo.toggleUpvote('c-1'))
          .thenAnswer((_) async => (upvotes: 1, hasUpvoted: true));

      await tester.tap(find.byType(GestureDetector).first);
      await tester.pumpAndSettle();

      verify(mockRepo.toggleUpvote('c-1')).called(1);
    });

    testWidgets('icon switches from outlined to filled after tap', (tester) async {
      await tester.pumpWidget(buildButton('c-1'));
      await seedProvider(tester, hasUpvoted: false, upvotes: 0);
      await tester.pump();

      when(mockRepo.toggleUpvote('c-1'))
          .thenAnswer((_) async => (upvotes: 1, hasUpvoted: true));

      expect(find.byIcon(Icons.thumb_up_outlined), findsOneWidget);

      await tester.tap(find.byType(GestureDetector).first);
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.thumb_up), findsOneWidget);
    });
  });
}
