import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:halo_sdk/halo_sdk.dart';
import 'package:halo_shell/main.dart';
import 'package:halo_shell/stream/stream_screen.dart';
import 'package:halo_shell/switchboard/switchboard_screen.dart';
import 'package:halo_shell/recents/recents_screen.dart';
import 'package:halo_shell/home/home_screen.dart';
import 'package:halo_shell/lock/lock_screen.dart';
import 'package:halo_ui/halo_ui.dart';

import 'support/fonts.dart';

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await loadHaloFonts();
  });

  Future<void> pumpShell(WidgetTester tester, {String start = 'lock'}) {
    tester.view.physicalSize = const Size(390 * 2, 844 * 2);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    return tester.pumpWidget(HaloShell(backend: MockBackend(), start: start));
  }

  Future<void> swipe(WidgetTester tester, Offset from, Offset by) async {
    await tester.dragFrom(from, by);
    await tester.pumpAndSettle();
  }

  const topRight = Offset(300, 10);
  const topLeft = Offset(90, 10);
  const bottom = Offset(195, 834);

  testWidgets('starts locked and unlocks to Home with the hold ring', (
    tester,
  ) async {
    await pumpShell(tester);
    expect(find.byType(LockScreen), findsOneWidget);
    final g = await tester.startGesture(
      tester.getCenter(find.byType(HaloHoldRing)),
    );
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(milliseconds: 900));
    await g.up();
    await tester.pumpAndSettle();
    expect(find.byType(HomeScreen), findsOneWidget);
  });

  testWidgets('Lock has no edge swipes', (tester) async {
    await pumpShell(tester);
    await swipe(tester, topRight, const Offset(0, 160));
    expect(find.byType(LockScreen), findsOneWidget);
    await swipe(tester, bottom, const Offset(0, -160));
    expect(find.byType(LockScreen), findsOneWidget);
  });

  testWidgets('top right opens the Switchboard, bottom swipe returns Home', (
    tester,
  ) async {
    await pumpShell(tester, start: 'home');
    await swipe(tester, topRight, const Offset(0, 160));
    expect(find.byType(SwitchboardScreen), findsOneWidget);
    await swipe(tester, bottom, const Offset(0, -160));
    expect(find.byType(HomeScreen), findsOneWidget);
  });

  testWidgets('top left opens the Stream', (tester) async {
    await pumpShell(tester, start: 'home');
    await swipe(tester, topLeft, const Offset(0, 160));
    expect(find.byType(StreamScreen), findsOneWidget);
  });

  testWidgets('bottom swipe goes Home, then Recents, then back Home', (
    tester,
  ) async {
    await pumpShell(tester, start: 'stream');
    await swipe(tester, bottom, const Offset(0, -160));
    expect(find.byType(HomeScreen), findsOneWidget);
    await swipe(tester, bottom, const Offset(0, -160));
    expect(find.byType(RecentsScreen), findsOneWidget);
    await swipe(tester, bottom, const Offset(0, -160));
    expect(find.byType(HomeScreen), findsOneWidget);
  });

  testWidgets('short or wrong-way swipes do nothing', (tester) async {
    await pumpShell(tester, start: 'home');
    await swipe(tester, topRight, const Offset(0, 40)); // too short
    expect(find.byType(HomeScreen), findsOneWidget);
    await swipe(tester, topRight, const Offset(0, -160)); // wrong way
    expect(find.byType(HomeScreen), findsOneWidget);
    await swipe(
      tester,
      const Offset(300, 400),
      const Offset(0, 160),
    ); // not an edge
    expect(find.byType(HomeScreen), findsOneWidget);
  });

  testWidgets('launching an app shows a placeholder; Home button returns', (
    tester,
  ) async {
    await pumpShell(tester, start: 'home');
    await tester.tap(find.byKey(const ValueKey('arc-messages')));
    await tester.pumpAndSettle();
    expect(find.byType(HomeScreen), findsNothing);
    expect(find.text('MESSAGES'), findsOneWidget);
    await tester.tap(find.text('Home'));
    await tester.pumpAndSettle();
    expect(find.byType(HomeScreen), findsOneWidget);
  });

  testWidgets('every screen can be the start screen', (tester) async {
    for (final s in [
      'lock',
      'home',
      'switchboard',
      'recents',
      'stream',
      'system',
    ]) {
      await pumpShell(tester, start: s);
      expect(tester.takeException(), isNull, reason: s);
    }
  });
}
