// Basic smoke test for the SARAP app.
//
// This just verifies the app builds and renders without throwing —
// not a full feature test, but enough to catch a broken root widget.

import 'package:flutter_test/flutter_test.dart';
import 'package:sarap_app/main.dart';

void main() {
  testWidgets('App builds without crashing', (WidgetTester tester) async {
    await tester.pumpWidget(const SarapApp());
    // No specific assertion needed — reaching this line without an
    // exception means the widget tree built successfully.
  });
}
