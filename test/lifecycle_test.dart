import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hotspot/hotspot.dart';
import 'package:hotspot/src/paint_bounds_builder.dart';

const duration = Duration(milliseconds: 100);

class TourHarness extends StatefulWidget {
  const TourHarness({super.key});
  @override
  State<TourHarness> createState() => TourHarnessState();
}

class TourHarnessState extends State<TourHarness> {
  final controller = GlobalKey<HotspotProviderState>();
  final targets = ValueNotifier<List<int>>([1, 2, 3]);
  final counter = ValueNotifier<int>(0);

  @override
  void dispose() {
    targets.dispose();
    counter.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
        home: HotspotProvider(
          key: controller,
          duration: duration,
          child: Scaffold(
            body: Column(children: [
              ValueListenableBuilder<int>(
                valueListenable: counter,
                builder: (_, value, __) => TextButton(
                  onPressed: () => counter.value++,
                  child: Text('Counter $value'),
                ),
              ),
              ValueListenableBuilder<List<int>>(
                valueListenable: targets,
                builder: (_, values, __) => Column(children: [
                  for (final value in values)
                    HotspotTarget(
                      key: ValueKey(value),
                      order: value,
                      calloutBody: Text('Step $value'),
                      child: SizedBox(
                          width: 80, height: 50, child: Text('Target $value')),
                    ),
                ]),
              ),
            ]),
          ),
        ),
      );
}

Future<TourHarnessState> openTour(WidgetTester tester) async {
  final key = GlobalKey<TourHarnessState>();
  await tester.pumpWidget(TourHarness(key: key));
  await tester.pumpAndSettle();
  key.currentState!.controller.currentState!.startFlow();
  await tester.pumpAndSettle();
  expect(find.text('Step 1'), findsOneWidget);
  return key.currentState!;
}

void main() {
  testWidgets('removing selected target dismisses and preserves screen state',
      (tester) async {
    final state = await openTour(tester);
    state.counter.value = 7;
    state.targets.value = [2, 3];
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('Step 1'), findsNothing);
    expect(find.byType(PaintBoundsBuilder), findsNothing);
    await tester.tap(find.text('Counter 7'));
    await tester.pump();
    expect(find.text('Counter 8'), findsOneWidget);
    state.controller.currentState!.startFlow();
    await tester.pumpAndSettle();
    expect(find.text('Step 2'), findsOneWidget);
  });

  testWidgets(
      'removing preceding targets keeps selected identity and valid index',
      (tester) async {
    final state = await openTour(tester);
    state.controller.currentState!.next();
    await tester.pumpAndSettle();
    state.controller.currentState!.next();
    await tester.pumpAndSettle();
    state.targets.value = [3];
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('Step 3'), findsOneWidget);
    state.controller.currentState!.next();
    await tester.pumpAndSettle();
    expect(find.byType(PaintBoundsBuilder), findsNothing);
  });

  testWidgets('dismissal removes measurements before a target disappears',
      (tester) async {
    final state = await openTour(tester);
    state.controller.currentState!.dismiss();
    state.targets.value = [];
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.byType(PaintBoundsBuilder), findsNothing);
  });

  testWidgets('empty flow dismisses an existing tour and supports reopening',
      (tester) async {
    final state = await openTour(tester);
    state.controller.currentState!.startFlow('missing');
    await tester.pumpAndSettle();
    expect(find.byType(PaintBoundsBuilder), findsNothing);
    state.controller.currentState!.startFlow();
    await tester.pumpAndSettle();
    expect(find.text('Step 1'), findsOneWidget);
  });

  testWidgets('dismiss then reopen does not reset a newer tour',
      (tester) async {
    final state = await openTour(tester);
    state.controller.currentState!.dismiss();
    await tester.pump();
    state.controller.currentState!.startFlow();
    state.controller.currentState!.next();
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('Step 2'), findsOneWidget);
  });

  testWidgets('provider disposal after dismissal cancels delayed work',
      (tester) async {
    final state = await openTour(tester);
    final controller = state.controller.currentState!;
    controller.dismiss();
    await tester.pumpWidget(const SizedBox());
    await tester.pump(duration * 2);
    expect(tester.takeException(), isNull);
  });

  testWidgets('removing all targets while starting a tour is safe',
      (tester) async {
    final state = await openTour(tester);
    state.controller.currentState!.dismiss();
    await tester.pumpAndSettle();
    state.controller.currentState!.startFlow();
    state.targets.value = [];
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.byType(PaintBoundsBuilder), findsNothing);
  });

  testWidgets('disposed target bounds can be queried safely', (tester) async {
    final state = await openTour(tester);
    final target =
        tester.state<HotspotTargetState>(find.byType(HotspotTarget).first);
    state.targets.value = [];
    await tester.pumpAndSettle();
    expect(target.tryGlobalPaintBounds, isNull);
    expect(target.globalPaintBounds, Rect.zero);
    expect(target.toString(), contains('disposed'));
    expect(tester.takeException(), isNull);
  });

  testWidgets('measurement waits for layout before calling the builder',
      (tester) async {
    var measured = false;
    await tester.pumpWidget(Directionality(
      textDirection: TextDirection.ltr,
      child: PaintBoundsBuilder(builder: (_, bounds) {
        measured = true;
        expect(bounds.isFinite, isTrue);
        return const SizedBox();
      }),
    ));
    expect(measured, isFalse);
    await tester.pump();
    expect(measured, isTrue);
    await tester.pumpWidget(const SizedBox());
    expect(tester.takeException(), isNull);
  });

  testWidgets('global key movement within a provider retains the active step',
      (tester) async {
    final provider = GlobalKey<HotspotProviderState>();
    final target = GlobalKey();
    final onLeft = ValueNotifier(true);
    addTearDown(onLeft.dispose);
    await tester.pumpWidget(MaterialApp(
        home: HotspotProvider(
      key: provider,
      child: ValueListenableBuilder<bool>(
          valueListenable: onLeft,
          builder: (_, left, __) {
            final child = HotspotTarget(
                key: target,
                order: 1,
                calloutBody: const Text('Moving step'),
                child: const SizedBox(width: 50, height: 50));
            return Row(children: [
              Expanded(child: left ? child : const SizedBox()),
              Expanded(child: left ? const SizedBox() : child),
            ]);
          }),
    )));
    await tester.pumpAndSettle();
    provider.currentState!.startFlow();
    await tester.pumpAndSettle();
    onLeft.value = false;
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('Moving step'), findsOneWidget);
    expect(provider.currentState!.currentFlow, hasLength(1));
  });

  testWidgets('dependency rebuilds do not register a target twice',
      (tester) async {
    final state = await openTour(tester);
    state.targets.value = [1, 2, 3];
    await tester.pumpAndSettle();
    expect(state.controller.currentState!.currentFlow, hasLength(3));
  });

  testWidgets(
      'navigation disposes active targets without retaining the overlay',
      (tester) async {
    final provider = GlobalKey<HotspotProviderState>();
    final navigator = GlobalKey<NavigatorState>();
    await tester.pumpWidget(MaterialApp(
        home: HotspotProvider(
      key: provider,
      duration: duration,
      child: Navigator(
          key: navigator,
          onGenerateRoute: (_) => MaterialPageRoute<void>(
                builder: (_) => const HotspotTarget(
                    order: 1,
                    calloutBody: Text('Route step'),
                    child: Scaffold(body: Text('First route'))),
              )),
    )));
    await tester.pumpAndSettle();
    provider.currentState!.startFlow();
    await tester.pumpAndSettle();
    navigator.currentState!.pushReplacement(MaterialPageRoute<void>(
        builder: (_) => const Scaffold(body: Text('Second route'))));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('Second route'), findsOneWidget);
    expect(find.byType(PaintBoundsBuilder), findsNothing);
  });

  testWidgets('nested providers keep their own targets', (tester) async {
    final outer = GlobalKey<HotspotProviderState>();
    final inner = GlobalKey<HotspotProviderState>();
    await tester.pumpWidget(MaterialApp(
        home: HotspotProvider(
      key: outer,
      child: HotspotProvider(
          key: inner,
          child: const HotspotTarget(
            order: 1,
            calloutBody: Text('Inner step'),
            child: SizedBox.expand(),
          )),
    )));
    await tester.pumpAndSettle();
    outer.currentState!.startFlow();
    await tester.pumpAndSettle();
    expect(find.text('Inner step'), findsNothing);
    inner.currentState!.startFlow();
    await tester.pumpAndSettle();
    expect(find.text('Inner step'), findsOneWidget);
  });

  testWidgets('first step End tour dismisses without an exception',
      (tester) async {
    await openTour(tester);
    await tester.tap(find.text('End tour'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.byType(PaintBoundsBuilder), findsNothing);
  });
  testWidgets('start and dismiss in one frame releases the overlay',
      (tester) async {
    final key = GlobalKey<TourHarnessState>();
    await tester.pumpWidget(TourHarness(key: key));
    await tester.pumpAndSettle();
    final controller = key.currentState!.controller.currentState!;
    controller.startFlow();
    controller.dismiss();
    await tester.pumpAndSettle();
    expect(find.byType(PaintBoundsBuilder), findsNothing);
  });
  testWidgets('selected target leaving the active flow dismisses the tour',
      (tester) async {
    final provider = GlobalKey<HotspotProviderState>();
    final flow = ValueNotifier('main');
    addTearDown(flow.dispose);
    await tester.pumpWidget(MaterialApp(
        home: HotspotProvider(
      key: provider,
      child: ValueListenableBuilder<String>(
          valueListenable: flow,
          builder: (_, value, __) => HotspotTarget(
              flow: value,
              order: 1,
              calloutBody: const Text('Callout'),
              child: const SizedBox(width: 100, height: 60))),
    )));
    await tester.pumpAndSettle();
    provider.currentState!.startFlow();
    await tester.pumpAndSettle();
    expect(find.text('Callout'), findsOneWidget);
    flow.value = 'other';
    await tester.pumpAndSettle();
    expect(provider.currentState!.currentFlow, isEmpty);
    expect(find.byType(PaintBoundsBuilder), findsNothing);
  });

  testWidgets('toggling enabled keeps the child state and updates the flow',
      (tester) async {
    final provider = GlobalKey<HotspotProviderState>();
    final enabled = ValueNotifier(true);
    addTearDown(enabled.dispose);
    await tester.pumpWidget(MaterialApp(
        home: HotspotProvider(
      key: provider,
      child: ValueListenableBuilder<bool>(
          valueListenable: enabled,
          builder: (_, on, __) => HotspotTarget(
              enabled: on,
              order: 1,
              calloutBody: const Text('Callout'),
              child: const _Probe())),
    )));
    await tester.pumpAndSettle();
    final probe = tester.state(find.byType(_Probe));
    provider.currentState!.startFlow();
    await tester.pumpAndSettle();
    expect(find.text('Callout'), findsOneWidget);

    enabled.value = false;
    await tester.pumpAndSettle();
    expect(tester.state(find.byType(_Probe)), same(probe));
    expect(provider.currentState!.currentFlow, isEmpty);
    expect(find.byType(PaintBoundsBuilder), findsNothing);

    enabled.value = true;
    await tester.pumpAndSettle();
    expect(tester.state(find.byType(_Probe)), same(probe));
    expect(provider.currentState!.currentFlow, hasLength(1));
  });
}

class _Probe extends StatefulWidget {
  const _Probe();
  @override
  State<_Probe> createState() => _ProbeState();
}

class _ProbeState extends State<_Probe> {
  @override
  Widget build(BuildContext context) =>
      const SizedBox(width: 100, height: 60);
}
