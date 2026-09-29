import 'package:flutter/widgets.dart';

import 'hotspot_provider.dart';

/// Example of a page that has multiple hotspot targets.
///
/// ```dart
/// Scaffold(
///   appBar: AppBar(
///     leading: HotspotTarget(
///       order: 200,
///       calloutBody: buildCalloutBody(
///         Icons.exit_to_app,
///         'Back button',
///         'This is a Flutter back button.',
///       ),
///       child: BackButton(),
///     ),
///     title: HotspotTarget(
///       order: 100,
///       calloutBody: buildCalloutBody(
///         Icons.title,
///         'Title',
///         'This is the name of the route for this view.',
///       ),
///       child: Text('/hotspot'),
///     ),
///     actions: [
///       HotspotTarget(
///         order: 900,
///         calloutBody: buildCalloutBody(
///           Icons.tour,
///           'Take a Tour',
///           'Take this tour again at any time!',
///         ),
///         child: IconButton(
///           icon: Icon(Icons.play_arrow),
///           onPressed: () => HotspotProvider.of(context).startFlow(),
///         ),
///       ),
///     ],
///   ),
///   body: Stack(
///     children: [
///       //// Forth
///       SafeArea(
///         child: Align(
///           alignment: Alignment.bottomCenter,
///           child: HotspotTarget(
///             order: 500,
///             calloutBody: buildCalloutBody(
///               Icons.photo,
///               'This is an icon',
///               "It's placed at the bottom of this view so you can see the callout transition!",
///             ),
///             child: Icon(
///               Icons.people,
///               size: 42,
///             ),
///           ),
///         ),
///       )
///     ],
///   ),
/// )
/// ```
class HotspotTarget extends StatefulWidget {
  /// Tags a widget to be located, highlighted and called out
  /// as part of a hotspot flow.
  const HotspotTarget({
    Key? key,
    this.flow = 'main',
    required this.calloutBody,
    required this.order,
    required this.child,
    this.hotspotSize,
    this.hotspotOffset = Offset.zero,
    this.enabled = true,
  }) : super(key: key);

  /// Combines multiple hotspot targets into a single group.
  ///
  /// This allows multiple hotspot flows to exist in an app.
  ///
  /// Eg: "home-flow", "edit-flow", "transaction-flow"
  final String flow;

  /// The Widget to display in the callout body.
  ///
  /// Typically some kind of text describing the feature,
  /// maybe with an icon.
  final Widget calloutBody;

  /// The place in the flow order.
  final num order;

  /// The widget to highlight with the hotspot.
  final Widget child;

  /// Override the hotspot dimensions with a custom size.
  final Size? hotspotSize;

  /// Override the hotspot center with a custom offset.
  final Offset hotspotOffset;

  /// Whether this target takes part in hotspot flows.
  ///
  /// Toggling this keeps [child] and its state intact, unlike adding or
  /// removing the [HotspotTarget] around it.
  final bool enabled;

  @override
  HotspotTargetState createState() => HotspotTargetState();
}

class HotspotTargetState extends State<HotspotTarget> {
  HotspotProviderState? _provider;

  /// False between deactivation and reactivation, and after disposal.
  var _inTree = true;

  /// Registers with the nearest [HotspotProvider], leaving the previous one
  /// if this target was moved (GlobalKey) under a different provider.
  void _attach() {
    final provider = widget.enabled
        ? context.findAncestorStateOfType<HotspotProviderState>()
        : null;
    if (provider != _provider) _provider?.detachTarget(this);
    _provider = provider?..attachTarget(this);
  }

  @override
  void initState() {
    super.initState();
    _attach();
  }

  @override
  void didUpdateWidget(HotspotTarget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.enabled != widget.enabled) {
      _attach();
    } else if (oldWidget.flow != widget.flow ||
        oldWidget.order != widget.order) {
      _provider?.attachTarget(this);
    }
  }

  @override
  void activate() {
    super.activate();
    _inTree = true;
    _attach();
  }

  @override
  void deactivate() {
    _inTree = false;
    _provider?.detachTarget(this);
    _provider = null;
    super.deactivate();
  }

  /// The global paint bounds, or null when the target is not laid out in the
  /// tree (e.g. it is being removed or has not been laid out yet).
  Rect? get tryGlobalPaintBounds {
    if (!_inTree) return null;
    final box = context.findRenderObject();
    if (box is! RenderBox || !box.attached || !box.hasSize) return null;
    final bounds = box.paintBounds.shift(box.localToGlobal(Offset.zero));
    return bounds.isFinite ? bounds : null;
  }

  /// The global paint bounds, or [Rect.zero] when unavailable.
  /// Prefer [tryGlobalPaintBounds].
  Rect get globalPaintBounds => tryGlobalPaintBounds ?? Rect.zero;

  @override
  Widget build(BuildContext context) {
    return widget.child;
  }

  @override
  String toString({DiagnosticLevel minLevel = DiagnosticLevel.info}) => mounted
      ? 'HotspotTargetState(flow: ${widget.flow}, order: ${widget.order}, inTree: $_inTree)'
      : 'HotspotTargetState(disposed)';
}
