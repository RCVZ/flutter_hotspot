import 'dart:math';

import 'package:flutter/material.dart';
import 'package:hotspot/hotspot.dart';
import 'package:provider/provider.dart';

import 'callout_layout_delegate.dart';
import 'callout_tail_painter.dart';
import 'hotspot_painter.dart';
import 'paint_bounds_builder.dart';

/// Example of a typical HotspotProvider with actionBuilder handling the
/// progress dots, dismiss button, and next button.
///
/// We recommend setting the bodyWidth to 80% of the viewport width as a default.
///
///
/// ```dart
/// HotspotProvider(
///   curve: Sprung.overDamped,
///   color: Colors.deepPurple.shade800,
///   bodyWidth: min(280.0, MediaQuery.of(context).size.width * 0.8),
///   hotspotShapeBorder: crb.ContinuousRectangleBorder(cornerRadius: 12.0),
///   skrimColor: Colors.black.withOpacity(0.7),
///   child: child,
///   actionBuilder: (_, controller) {
///     return Row(
///       children: [
///         SizedBox(width: 8),
///         FlatButton(
///           child: Text("End tour"),
///           textColor: Colors.white54,
///           onPressed: controller.onDismiss,
///         ),
///         Spacer(flex: 1),
///         Transform.translate(
///           offset: Offset(-8, 0),
///           child: Row(
///             children: [
///               for (var i = 0; i < controller.pages; i++)
///                 AnimatedContainer(
///                   margin: EdgeInsets.all(3),
///                   duration: Duration(milliseconds: 250),
///                   decoration: BoxDecoration(
///                     color: controller.index == i ? Colors.white : Colors.white30,
///                     borderRadius: BorderRadius.circular(99),
///                   ),
///                   height: 6,
///                   width: 6,
///                 ),
///             ],
///           ),
///         ),
///         Spacer(flex: 1),
///         RaisedButton(
///           child: AnimatedCrossFade(
///             crossFadeState: controller.index + 1 < controller.pages
///                 ? CrossFadeState.showFirst
///                 : CrossFadeState.showSecond,
///             duration: Duration(milliseconds: 250),
///             firstChild: Text("Next"),
///             secondChild: Text("Done"),
///           ),
///           color: Colors.deepPurpleAccent,
///           textColor: Colors.white,
///           onPressed: controller.onNext,
///           elevation: 0.0,
///         ),
///         SizedBox(width: 8),
///       ],
///     );
///   },
/// )
/// ```
class HotspotProvider extends StatefulWidget {
  /// Set this to `false` to disable logging
  static var log = true;

  /// Listens for [HotspotTarget]s and provides a scrim with highlighting hotspot
  /// and overlay callout with actions for going to the next [HotspotTarget].
  const HotspotProvider({
    Key? key,
    this.actionBuilder,
    required this.child,
    this.backgroundColor,
    this.foregroundColor,
    this.curve = Curves.easeOutQuint,
    this.duration = const Duration(milliseconds: 750),
    this.padding = const EdgeInsets.all(16),
    this.tailInsets = const EdgeInsets.all(-2),
    this.tailSize = const Size(14, 8),
    this.bodyMargin = const EdgeInsets.all(8),
    this.bodyWidth = 322,
    this.skrimColor,
    this.hotspotShapeBorder = const RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(16))),
    this.bodyPadding = const EdgeInsets.all(16),
    this.dismissibleSkrim = true,
    this.skrimCurve = Curves.easeOutExpo,
  }) : super(key: key);

  /// The child which contains multiple [HotspotTarget] in the tree.
  final Widget child;

  /// The transition duration for the hotspot and callout.
  final Duration duration;

  /// The transition curve to use for the hotspot and callout.
  final Curve curve;

  /// The hotspot padding.
  final EdgeInsets padding;

  /// The margin between the hotspot and the tail.
  final EdgeInsets tailInsets;

  /// The size of the callout tail.
  final Size tailSize;

  /// The margin between the callout body and the viewport.
  final EdgeInsets bodyMargin;

  /// The color of the callout body and tail.
  final Color? backgroundColor;

  /// The color of text and icons.
  final Color? foregroundColor;

  /// The width of the callout body;
  final double bodyWidth;

  /// The color of the skrim which acts as the background
  /// between the hotspot callout and the view. Provides
  /// hotspot cutouts that surround the appropriate [HotspotTarget].
  final Color? skrimColor;

  /// The shape of the hotspot border.
  final ShapeBorder hotspotShapeBorder;

  /// The padding to apply to the callout body.
  final EdgeInsets bodyPadding;

  /// The actions to build at the bottom of the callout body.
  ///
  /// Localize the default by constructing [HotspotActionBuilder] with new strings
  final CalloutActionBuilder? actionBuilder;

  /// Tapping on the skrim dismisses the flow when `true`.
  final bool dismissibleSkrim;

  /// Curve for the skrim.
  final Curve skrimCurve;

  /// Retreive the ancestor [HotspotProvider] for the purpose of performing actions.
  static HotspotProviderState of(BuildContext context) =>
      Provider.of<HotspotProviderState>(context, listen: false);

  /// The ancestor [HotspotProvider], or null when there is none.
  static HotspotProviderState? maybeOf(BuildContext context) =>
      context.findAncestorStateOfType<HotspotProviderState>();

  @override
  HotspotProviderState createState() => HotspotProviderState();
}

class HotspotProviderState extends State<HotspotProvider>
    with TickerProviderStateMixin {
  CalloutActionBuilder get actionBuilder =>
      widget.actionBuilder ?? (_, c) => HotspotActionBuilder(c);

  /// Targets currently in the tree below this provider. Targets attach and
  /// detach themselves, so this never holds a deactivated or disposed target.
  final _targets = <HotspotTargetState>{};

  var _flow = 'main';

  /// Whether the overlay is shown (or fading in).
  var _visible = false;

  /// The highlighted target. Kept while the overlay fades out, cleared after.
  HotspotTargetState? _current;

  var _syncScheduled = false;

  /// Drives the overlay fade. When fully faded out, [_current] is cleared so a
  /// hidden tour never measures its target.
  late final AnimationController _fade;
  late final CurvedAnimation _opacity;

  @override
  void initState() {
    super.initState();
    _fade = AnimationController(vsync: this, duration: widget.duration)
      ..addStatusListener(_onFadeStatus);
    _opacity = CurvedAnimation(parent: _fade, curve: widget.skrimCurve);
  }

  @override
  void didUpdateWidget(HotspotProvider oldWidget) {
    super.didUpdateWidget(oldWidget);
    _fade.duration = widget.duration;
    _opacity.curve = widget.skrimCurve;
  }

  @override
  void dispose() {
    _opacity.dispose();
    _fade.dispose();
    super.dispose();
  }

  /// When we start the flow we save the last focus node, dismiss
  /// focus to close the keyboard, and after the tour is done we
  /// put the focus back where it was.
  FocusNode? _lastFocusNode;

  /// Convenience getter for the current flow sorted by order.
  List<HotspotTargetState> get currentFlow =>
      _targets.where((e) => e.widget.flow == _flow).toList()
        ..sort((a, b) => a.widget.order.compareTo(b.widget.order));

  /// Initiate a hotspot flow.
  void startFlow([String flow = 'main']) {
    _flow = flow;
    final first = currentFlow.firstOrNull;
    if (first == null && HotspotProvider.log) {
      debugPrint('[Hotspot] warning, flow dispatched, '
          'but no hotspots found. flow: $flow');
    }
    _show(first);
  }

  /// Called when tapping the next button.
  /// Can be called externally.
  void next() => _step(1);

  /// Called when tapping the previous button.
  /// Can be called externally.
  void previous() => _step(-1);

  /// Called when tapping the dismiss button.
  /// Can be called externally.
  void dismiss() => _show(null);

  void _step(int delta) {
    if (!_visible) return;
    final flow = currentFlow;
    final index = flow.indexOf(_current!);
    final next = index + delta;
    _show(index < 0 || next < 0 || next >= flow.length ? null : flow[next]);
  }

  /// Shows [target], or hides the overlay when it is null.
  void _show(HotspotTargetState? target) {
    if (!mounted) return;
    final wasVisible = _visible;
    setState(() {
      _visible = target != null;
      // Keep the previous target for the fade-out, unless it left the flow.
      if (target != null || !currentFlow.contains(_current)) _current = target;
    });
    _visible ? _fade.forward() : _fade.reverse();

    if (!wasVisible && _visible) {
      _lastFocusNode = FocusManager.instance.primaryFocus?..unfocus();
    } else if (wasVisible && !_visible) {
      final focus = _lastFocusNode;
      _lastFocusNode = null;
      if (focus?.context?.mounted ?? false) focus!.requestFocus();
    }
  }

  /// Registers a [HotspotTarget]. Called by [HotspotTargetState].
  void attachTarget(HotspotTargetState target) {
    _targets.add(target);
    _scheduleSync();
  }

  /// Unregisters a [HotspotTarget]. Called by [HotspotTargetState].
  void detachTarget(HotspotTargetState target) {
    _targets.remove(target);
    _scheduleSync();
  }

  /// Targets attach and detach while the tree is building or being
  /// finalized, when setState isn't allowed, so catch up after the frame.
  void _scheduleSync() {
    if (_current == null || _syncScheduled) return;
    _syncScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _syncScheduled = false;
      if (!mounted || _current == null) return;
      if (currentFlow.contains(_current)) {
        setState(() {}); // step index or count may have changed
      } else {
        dismiss();
      }
    });
  }

  void _onFadeStatus(AnimationStatus status) {
    if (status == AnimationStatus.dismissed && mounted && _current != null) {
      setState(() => _current = null);
    }
  }

  Color get bg =>
      widget.backgroundColor ?? Theme.of(context).colorScheme.surfaceBright;

  Color get fg =>
      widget.foregroundColor ?? Theme.of(context).colorScheme.onSurface;

  @override
  Widget build(BuildContext context) {
    final target = _current;

    return Provider<HotspotProviderState>(
      create: (_) => this,
      child: Material(
        child: Stack(
          children: [
            RepaintBoundary(
              child: widget.child,
            ),
            Positioned.fill(
              child: IgnorePointer(
                ignoring: !_visible,
                child: FadeTransition(
                  opacity: _opacity,
                  child: target == null
                      ? const SizedBox.shrink()
                      : PaintBoundsBuilder(
                          builder: (context, paintBounds) {
                            // Measured during build, so the target may have
                            // left the tree earlier in this frame.
                            final targetBounds = target.tryGlobalPaintBounds;
                            if (targetBounds == null) {
                              return const SizedBox.shrink();
                            }
                            final delegate = CalloutLayoutDelegate(
                              tailSize: widget.tailSize,
                              tailInsets: widget.tailInsets,
                              paintBounds: paintBounds,
                              targetBounds: targetBounds,
                              hotspotPadding: widget.padding,
                              bodyMargin: widget.bodyMargin,
                              bodyWidth: widget.bodyWidth,
                              hotspotSize: target.widget.hotspotSize,
                              hotspotOffset: target.widget.hotspotOffset,
                            );

                            return buildHotspotAndCallout(
                              context: context,
                              delegate: delegate,
                              currentTarget: target,
                            );
                          },
                        ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Build the hotspot and callout
  Widget buildHotspotAndCallout({
    required BuildContext context,
    required CalloutLayoutDelegate delegate,
    required HotspotTargetState currentTarget,
  }) {
    // Animation builders can outlive the target element during this frame.
    final targetWidget = currentTarget.widget;
    final flow = currentFlow;
    return Stack(
      children: [
        /// Skrim with hotspot cutout
        Positioned.fill(
          child: GestureDetector(
            onTap: widget.dismissibleSkrim
                ? () {
                    dismiss();
                  }
                : null,
            child: TweenAnimationBuilder<Rect?>(
              curve: widget.curve,
              tween: RectTween(end: delegate.hotspotBounds),
              duration: widget.duration,
              builder: (context, t, child) {
                return CustomPaint(
                  painter: HotspotPainter(
                    hotspotBounds: t!,
                    shapeBorder: widget.hotspotShapeBorder,
                    skrimColor: widget.skrimColor ??
                        Theme.of(context).colorScheme.scrim.withOpacity(0.4),
                  ),
                );
              },
            ),
          ),
        ),

        /// Callout painter
        Positioned.fill(
          child: Stack(
            children: [
              /// Callout tail
              TweenAnimationBuilder<Rect?>(
                curve: widget.curve,
                duration: widget.duration,
                tween: RectTween(
                  end: delegate.tailBounds,
                ),
                builder: (context, t, child) {
                  return CustomPaint(
                    painter: CalloutTailPainter(
                      tailBounds: t!,
                      color: bg,
                    ),
                  );
                },
              ),

              /// Callout body
              TweenAnimationBuilder<Rect?>(
                curve: widget.curve,
                duration: widget.duration,
                tween: RectTween(
                  end: delegate.bodyContainerBounds,
                ),
                builder: (context, t, child) {
                  return Positioned.fromRect(
                    rect: t!,
                    child: AnimatedContainer(
                      curve: widget.curve,
                      duration: widget.duration,
                      height: delegate.bodyContainerHeight,
                      width: delegate.bodyWidth,
                      alignment: delegate.targetIsAboveCenter
                          ? Alignment.topCenter
                          : Alignment.bottomCenter,

                      /// Absorb tap events so we don't dismiss when tapping on the callout body.
                      /// Without this, the tap event is passed through to the skrim GestureDetector
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: Container(
                          decoration: BoxDecoration(color: bg),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              /// Callout body
                              Padding(
                                padding: widget.bodyPadding,
                                child: AnimatedSize(
                                  duration: widget.duration,
                                  alignment: Alignment.topCenter,
                                  curve: widget.curve,
                                  child: targetWidget.calloutBody,
                                ),
                              ),

                              /// Callout controls
                              actionBuilder(
                                context,
                                CalloutActionController(
                                  dismiss: dismiss,
                                  next: next,
                                  previous: previous,
                                  index: max(0, flow.indexOf(currentTarget)),
                                  pages: flow.length,
                                  foregroundColor: fg,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// A function that contains all the data needed to build the
/// action section of a callout body.
typedef CalloutActionBuilder = Widget Function(
    BuildContext context, CalloutActionController controller);

class CalloutActionController {
  /// A stateless controller that passes events back to [HotspotProvider]
  /// while providing key metrics to the builder.
  CalloutActionController({
    required this.dismiss,
    required this.next,
    required this.previous,
    required this.index,
    required this.pages,
    required this.foregroundColor,
  });

  final Color? foregroundColor;

  /// Dismiss the callout.
  final VoidCallback dismiss;

  /// Go to the next [HotspotTarget]
  final VoidCallback next;

  /// Go to the previous [HotspotTarget]
  final VoidCallback previous;

  /// The current target's index.
  final int index;

  /// The total number of targets.
  final int pages;

  /// Convenience getter for if we're currently on the last page.
  bool get isLastPage => index + 1 == pages;

  /// Convenience getter for if we're currently on the first page.
  bool get isFirstPage => index == 0;
}
