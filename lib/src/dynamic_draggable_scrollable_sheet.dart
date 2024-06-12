import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

class DynamicDraggableScrollableController extends ChangeNotifier {
  _DynamicDraggableScrollableSheetScrollController? _attachedController;
  final Set<AnimationController> _animationControllers =
      <AnimationController>{};

  /// Get the current pixel height of the attached sheet.
  double get pixels {
    _assertAttached();
    return _attachedController!.extent.currentPixels;
  }

  List<double> get snapPixels {
    _assertAttached();
    return _attachedController!.extent.snapPixels;
  }

  double? get contentPixels {
    _assertAttached();
    return _attachedController!.extent.contentPixels;
  }

  /// Returns Whether any [DraggableScrollableController] objects have attached themselves to the
  /// [DynamicDraggableScrollableSheet].
  ///
  /// If this is false, then members that interact with the [ScrollPosition],
  /// such as [sizeToPixels], [size], [animateTo], and [jumpTo], must not be
  /// called.
  bool get isAttached =>
      _attachedController != null && _attachedController!.hasClients;

  /// Animates the attached sheet from its current size to the given [size], a
  /// fractional value of the parent container's height.
  ///
  /// Any active sheet animation is canceled. If the sheet's internal scrollable
  /// is currently animating (e.g. responding to a user fling), that animation is
  /// canceled as well.
  ///
  /// An animation will be interrupted whenever the user attempts to scroll
  /// manually, whenever another activity is started, or when the sheet hits its
  /// max or min size (e.g. if you animate to 1 but the max size is .8, the
  /// animation will stop playing when it reaches .8).
  ///
  /// The duration must not be zero. To jump to a particular value without an
  /// animation, use [jumpTo].
  ///
  /// The sheet will not snap after calling [animateTo] even if [DynamicDraggableScrollableSheet.snap]
  /// is true. Snapping only occurs after user drags.
  ///
  /// When calling [animateTo] in widget tests, `await`ing the returned
  /// [Future] may cause the test to hang and timeout. Instead, use
  /// [WidgetTester.pumpAndSettle].
  Future<void> animateTo(
    double pixels, {
    required Duration duration,
    required Curve curve,
  }) async {
    _assertAttached();
    assert(duration != Duration.zero);
    final AnimationController animationController =
        AnimationController.unbounded(
      vsync: _attachedController!.position.context.vsync,
      value: _attachedController!.extent.currentPixels,
    );
    _animationControllers.add(animationController);
    _attachedController!.position.goIdle();
    // This disables any snapping until the next user interaction with the sheet.
    _attachedController!.extent.hasDragged = false;
    _attachedController!.extent.hasChanged = true;

    _attachedController!.extent.startActivity(onCanceled: () {
      // Don't stop the controller if it's already finished and may have been disposed.
      if (animationController.isAnimating) {
        animationController.stop();
      }
    });

    animationController.addListener(() {
      _attachedController!.extent.updatePixels(
        animationController.value,
        _attachedController!.position.context.notificationContext!,
      );
    });

    await animationController.animateTo(
      clampDouble(
        pixels,
        _attachedController!.extent.minPixels,
        _attachedController!.extent.maxPixels,
      ),
      duration: duration,
      curve: curve,
    );
  }

  /// Jumps the attached sheet from its current size to the given [pixels], a
  /// fractional value of the parent container's height.
  ///
  /// If [pixels] is outside of a the attached sheet's min or max child size,
  /// [jumpTo] will jump the sheet to the nearest valid size instead.
  ///
  /// Any active sheet animation is canceled. If the sheet's inner scrollable
  /// is currently animating (e.g. responding to a user fling), that animation is
  /// canceled as well.
  ///
  /// The sheet will not snap after calling [jumpTo] even if [DynamicDraggableScrollableSheet.snap]
  /// is true. Snapping only occurs after user drags.
  void jumpTo(double pixels) {
    _assertAttached();
    assert(pixels >= 0 && pixels <= 1);
    // Call start activity to interrupt any other playing activities.
    _attachedController!.extent.startActivity(onCanceled: () {});
    _attachedController!.position.goIdle();
    _attachedController!.extent.hasDragged = false;
    _attachedController!.extent.hasChanged = true;
    _attachedController!.extent.updatePixels(
      pixels,
      _attachedController!.position.context.notificationContext!,
    );
  }

  /// Reset the attached sheet to its initial size (see: [DynamicDraggableScrollableSheet.initialChildSize]).
  void reset() {
    _assertAttached();
    _attachedController!.reset();
  }

  void _assertAttached() {
    assert(
      isAttached,
      'DraggableScrollableController is not attached to a sheet. A DraggableScrollableController '
      'must be used in a DraggableScrollableSheet before any of its methods are called.',
    );
  }

  void _attach(
      _DynamicDraggableScrollableSheetScrollController scrollController) {
    assert(_attachedController == null,
        'Draggable scrollable controller is already attached to a sheet.');
    _attachedController = scrollController;
    _attachedController!.extent._currentPixels.addListener(notifyListeners);
    _attachedController!.onPositionDetached = _disposeAnimationControllers;
  }

  void _onExtentReplaced(_DynamicDraggableSheetExtent previousExtent) {
    // When the extent has been replaced, the old extent is already disposed and
    // the controller will point to a new extent. We have to add our listener to
    // the new extent.
    _attachedController!.extent._currentPixels.addListener(notifyListeners);
    if (previousExtent.currentPixels !=
        _attachedController!.extent.currentPixels) {
      // The listener won't fire for a change in size between two extent
      // objects so we have to fire it manually here.
      notifyListeners();
    }
  }

  void _detach({bool disposeExtent = false}) {
    if (disposeExtent) {
      _attachedController?.extent.dispose();
    } else {
      _attachedController?.extent._currentPixels
          .removeListener(notifyListeners);
    }
    _disposeAnimationControllers();
    _attachedController = null;
  }

  void _disposeAnimationControllers() {
    for (final AnimationController animationController
        in _animationControllers) {
      animationController.dispose();
    }
    _animationControllers.clear();
  }
}

/// A [ScrollController] suitable for use in a [ScrollableWidgetBuilder] created
/// by a [DynamicDraggableScrollableSheet].
///
/// If a [DynamicDraggableScrollableSheet] contains content that is exceeds the height
/// of its container, this controller will allow the sheet to both be dragged to
/// fill the container and then scroll the child content.
///
/// See also:
///
///  * [_DynamicDraggableScrollableSheetScrollPosition], which manages the positioning logic for
///    this controller.
///  * [PrimaryScrollController], which can be used to establish a
///    [_DynamicDraggableScrollableSheetScrollController] as the primary controller for
///    descendants.
class _DynamicDraggableScrollableSheetScrollController
    extends ScrollController {
  _DynamicDraggableScrollableSheetScrollController({
    required this.extent,
  });

  _DynamicDraggableSheetExtent extent;
  VoidCallback? onPositionDetached;

  @override
  _DynamicDraggableScrollableSheetScrollPosition createScrollPosition(
    ScrollPhysics physics,
    ScrollContext context,
    ScrollPosition? oldPosition,
  ) {
    return _DynamicDraggableScrollableSheetScrollPosition(
      physics: physics.applyTo(const AlwaysScrollableScrollPhysics()),
      context: context,
      oldPosition: oldPosition,
      getExtent: () => extent,
    );
  }

  @override
  void debugFillDescription(List<String> description) {
    super.debugFillDescription(description);
    description.add('extent: $extent');
  }

  @override
  _DynamicDraggableScrollableSheetScrollPosition get position =>
      super.position as _DynamicDraggableScrollableSheetScrollPosition;

  void reset() {
    extent._cancelActivity?.call();
    extent.hasDragged = false;
    extent.hasChanged = false;

    // jumpTo can result in trying to replace semantics during build.
    // Just animate really fast.
    // Avoid doing it at all if the offset is already 0.0.
    if (offset != 0.0) {
      animateTo(
        0.0,
        duration: const Duration(milliseconds: 1),
        curve: Curves.linear,
      );
    }

    extent.updatePixels(
      extent.initialPixels,
      position.context.notificationContext!,
    );
  }

  @override
  void detach(ScrollPosition position) {
    onPositionDetached?.call();
    super.detach(position);
  }
}

/// A scroll position that manages scroll activities for
/// [_DynamicDraggableScrollableSheetScrollController].
///
/// This class is a concrete subclass of [ScrollPosition] logic that handles a
/// single [ScrollContext], such as a [Scrollable]. An instance of this class
/// manages [ScrollActivity] instances, which changes the
/// [_DynamicDraggableSheetExtent.currentSize] or visible content offset in the
/// [Scrollable]'s [Viewport]
///
/// See also:
///
///  * [_DynamicDraggableScrollableSheetScrollController], which uses this as its [ScrollPosition].
class _DynamicDraggableScrollableSheetScrollPosition
    extends ScrollPositionWithSingleContext {
  _DynamicDraggableScrollableSheetScrollPosition({
    required super.physics,
    required super.context,
    super.oldPosition,
    required this.getExtent,
  });

  VoidCallback? _dragCancelCallback;
  bool _shouldApplyUserOffset = false;
  final _DynamicDraggableSheetExtent Function() getExtent;
  final Set<AnimationController> _ballisticControllers =
      <AnimationController>{};
  bool get listShouldScroll => pixels > 0.0;

  _DynamicDraggableSheetExtent get extent => getExtent();

  @override
  void absorb(ScrollPosition other) {
    super.absorb(other);
    assert(_dragCancelCallback == null);

    if (other is! _DynamicDraggableScrollableSheetScrollPosition) {
      return;
    }

    if (other._dragCancelCallback != null) {
      _dragCancelCallback = other._dragCancelCallback;
      other._dragCancelCallback = null;
    }
  }

  @override
  void beginActivity(ScrollActivity? newActivity) {
    // Cancel the running ballistic simulations
    for (final AnimationController ballisticController
        in _ballisticControllers) {
      ballisticController.stop();
    }

    super.beginActivity(newActivity);
  }

  @override
  void applyUserOffset(double delta) {
    if (!_shouldApplyUserOffset) return;

    if (!listShouldScroll &&
        (!(extent.isAtMin || extent.isAtMax) ||
            (extent.isAtMin && delta < 0) ||
            (extent.isAtMax && delta > 0))) {
      extent.addPixelDelta(-delta, context.notificationContext!);
    } else {
      super.applyUserOffset(delta);
    }
  }

  bool get _isAtSnapSize {
    return extent.snapPixels.any(
      (double snapSize) {
        return (extent.currentPixels - snapSize).abs() <=
            physics.toleranceFor(this).distance;
      },
    );
  }

  bool get _shouldSnap => extent.snap && extent.hasDragged && !_isAtSnapSize;

  @override
  void dispose() {
    for (final AnimationController ballisticController
        in _ballisticControllers) {
      ballisticController.dispose();
    }
    _ballisticControllers.clear();
    super.dispose();
  }

  @override
  void goBallistic(double velocity) {
    if ((velocity == 0.0 && !_shouldSnap) ||
        (velocity < 0.0 && listShouldScroll) ||
        (velocity > 0.0 && extent.isAtMax)) {
      super.goBallistic(velocity);
      return;
    }
    // Scrollable expects that we will dispose of its current _dragCancelCallback
    _dragCancelCallback?.call();
    _dragCancelCallback = null;

    late final Simulation simulation;
    if (extent.snap) {
      // Snap is enabled, simulate snapping instead of clamping scroll.
      simulation = _SnappingSimulation(
        position: extent.currentPixels,
        initialVelocity: velocity,
        pixelSnapSize: extent.snapPixels,
        snapAnimationDuration: extent.snapAnimationDuration,
        tolerance: physics.toleranceFor(this),
      );
    } else {
      // The iOS bouncing simulation just isn't right here - once we delegate
      // the ballistic back to the ScrollView, it will use the right simulation.
      simulation = ClampingScrollSimulation(
        // Run the simulation in terms of pixels, not extent.
        position: extent.currentPixels,
        velocity: velocity,
        tolerance: physics.toleranceFor(this),
      );
    }

    final AnimationController ballisticController =
        AnimationController.unbounded(
      debugLabel: objectRuntimeType(this, '_DraggableScrollableSheetPosition'),
      vsync: context.vsync,
    );
    _ballisticControllers.add(ballisticController);

    double lastPosition = extent.currentPixels;
    void tick() {
      final double delta = ballisticController.value - lastPosition;
      lastPosition = ballisticController.value;
      extent.addPixelDelta(delta, context.notificationContext!);
      if ((velocity > 0 && extent.isAtMax) ||
          (velocity < 0 && extent.isAtMin)) {
        // Make sure we pass along enough velocity to keep scrolling - otherwise
        // we just "bounce" off the top making it look like the list doesn't
        // have more to scroll.
        velocity = ballisticController.velocity +
            (physics.toleranceFor(this).velocity *
                ballisticController.velocity.sign);
        super.goBallistic(velocity);
        ballisticController.stop();
      } else if (ballisticController.isCompleted) {
        super.goBallistic(0);
      }
    }

    ballisticController
      ..addListener(tick)
      ..animateWith(simulation).whenCompleteOrCancel(
        () {
          if (_ballisticControllers.contains(ballisticController)) {
            _ballisticControllers.remove(ballisticController);
            ballisticController.dispose();
          }
        },
      );
  }

  @override
  Drag drag(DragStartDetails details, VoidCallback dragCancelCallback) {
    // Save this so we can call it later if we have to [goBallistic] on our own.
    _dragCancelCallback = dragCancelCallback;
    _shouldApplyUserOffset = extent.currentPixels >= extent.snapPixels[1];
    return super.drag(details, dragCancelCallback);
  }
}

/// Manages state between [_DynamicDraggableScrollableSheetState],
/// [_DraggableScrollableSheetScrollController], and
/// [_DraggableScrollableSheetScrollPosition].
///
/// The State knows the pixels available along the axis the widget wants to
/// scroll, but expects to get a fraction of those pixels to render the sheet.
///
/// The ScrollPosition knows the number of pixels a user wants to move the sheet.
///
/// The [currentSize] will never be null.
/// The [availablePixels] will never be null, but may be `double.infinity`.
class _DynamicDraggableSheetExtent {
  _DynamicDraggableSheetExtent({
    required this.minPixels,
    required this.maxPixels,
    required this.contentPixels,
    required this.snap,
    required this.snapPixels,
    required this.initialPixels,
    this.snapAnimationDuration,
    ValueNotifier<double>? currentPixels,
    bool? hasDragged,
    bool? hasChanged,
    this.shouldCloseOnMinExtent = true,
  })  : assert(minPixels >= 0),
        assert(maxPixels >= 0),
        assert(minPixels <= maxPixels),
        assert(initialPixels <= maxPixels),
        _currentPixels = currentPixels ?? ValueNotifier<double>(initialPixels),
        availablePixels = double.infinity,
        hasDragged = hasDragged ?? false,
        hasChanged = hasChanged ?? false;

  VoidCallback? _cancelActivity;

  final double minPixels;
  final double maxPixels;
  final double? contentPixels;
  final bool snap;
  final List<double> snapPixels;
  final Duration? snapAnimationDuration;
  final double initialPixels;
  final bool shouldCloseOnMinExtent;
  final ValueNotifier<double> _currentPixels;
  double availablePixels;

  // Used to disable snapping until the user has dragged on the sheet.
  bool hasDragged;

  // Used to determine if the sheet should move to a new initial size when it
  // changes.
  // We need both `hasChanged` and `hasDragged` to achieve the following
  // behavior:
  //   1. The sheet should only snap following user drags (as opposed to
  //      programmatic sheet changes). See docs for `animateTo` and `jumpTo`.
  //   2. The sheet should move to a new initial child size on rebuild iff the
  //      sheet has not changed, either by drag or programmatic control. See
  //      docs for `initialChildSize`.
  bool hasChanged;

  bool get isAtMin => minPixels >= _currentPixels.value;
  bool get isAtMax => maxPixels <= _currentPixels.value;

  double get currentPixels => _currentPixels.value;

  /// Start an activity that affects the sheet and register a cancel call back
  /// that will be called if another activity starts.
  ///
  /// The `onCanceled` callback will get called even if the subsequent activity
  /// started after this one finished, so `onCanceled` must be safe to call at
  /// any time.
  void startActivity({required VoidCallback onCanceled}) {
    _cancelActivity?.call();
    _cancelActivity = onCanceled;
  }

  /// The scroll position gets inputs in terms of pixels, but the size is
  /// expected to be expressed as a number between 0..1.
  ///
  /// This should only be called to respond to a user drag. To update the
  /// size in response to a programmatic call, use [updateSize] directly.
  void addPixelDelta(double delta, BuildContext context) {
    // Stop any playing sheet animations.
    _cancelActivity?.call();
    _cancelActivity = null;
    // The user has interacted with the sheet, set `hasDragged` to true so that
    // we'll snap if applicable.
    hasDragged = true;
    hasChanged = true;

    if (availablePixels == 0) {
      return;
    }

    updatePixels(currentPixels + delta, context);
  }

  /// Set the size to the new value. [newSize] should be a number between
  /// [minSize] and [maxSize].
  ///
  /// This can be triggered by a programmatic (e.g. controller triggered) change
  /// or a user drag.
  void updatePixels(double newPixels, BuildContext context) {
    final clampedPixels = clampDouble(newPixels, minPixels, maxPixels);

    if (_currentPixels.value == clampedPixels) {
      return;
    }

    _currentPixels.value = clampedPixels;

    DynamicDraggableScrollableNotification(
      minExtent: minPixels,
      maxExtent: maxPixels,
      extent: currentPixels,
      initialExtent: initialPixels,
      context: context,
      shouldCloseOnMinExtent: shouldCloseOnMinExtent,
    ).dispatch(context);
  }

  void dispose() {
    _currentPixels.dispose();
  }

  _DynamicDraggableSheetExtent copyWith({
    required double minPixels,
    required double maxPixels,
    required double? contentPixels,
    required bool snap,
    required List<double> snapPixels,
    required double initialPixels,
    Duration? snapAnimationDuration,
    bool shouldCloseOnMinExtent = true,
  }) {
    return _DynamicDraggableSheetExtent(
      minPixels: minPixels,
      maxPixels: maxPixels,
      contentPixels: contentPixels,
      snap: snap,
      snapPixels: snapPixels,
      snapAnimationDuration: snapAnimationDuration,
      initialPixels: initialPixels,
      // Set the current size to the possibly updated initial size if the sheet
      // hasn't changed yet.
      currentPixels: ValueNotifier<double>(
        hasChanged
            ? clampDouble(_currentPixels.value, minPixels, maxPixels)
            : initialPixels,
      ),
      hasDragged: hasDragged,
      hasChanged: hasChanged,
      shouldCloseOnMinExtent: shouldCloseOnMinExtent,
    );
  }
}

class _SnappingSimulation extends Simulation {
  _SnappingSimulation({
    required this.position,
    required double initialVelocity,
    required List<double> pixelSnapSize,
    Duration? snapAnimationDuration,
    super.tolerance,
  }) {
    _pixelSnapSize = _getSnapSize(initialVelocity, pixelSnapSize);

    if (snapAnimationDuration != null &&
        snapAnimationDuration.inMilliseconds > 0) {
      velocity = (_pixelSnapSize - position) *
          1000 /
          snapAnimationDuration.inMilliseconds;
    }
    // Check the direction of the target instead of the sign of the velocity because
    // we may snap in the opposite direction of velocity if velocity is very low.
    else if (_pixelSnapSize < position) {
      velocity = math.min(-minimumSpeed, initialVelocity);
    } else {
      velocity = math.max(minimumSpeed, initialVelocity);
    }
  }

  final double position;
  late final double velocity;

  // A minimum speed to snap at. Used to ensure that the snapping animation
  // does not play too slowly.
  static const double minimumSpeed = 1600.0;

  late final double _pixelSnapSize;

  @override
  double dx(double time) {
    if (isDone(time)) {
      return 0;
    }
    return velocity;
  }

  @override
  bool isDone(double time) {
    return x(time) == _pixelSnapSize;
  }

  @override
  double x(double time) {
    final double newPosition = position + velocity * time;
    if ((velocity >= 0 && newPosition > _pixelSnapSize) ||
        (velocity < 0 && newPosition < _pixelSnapSize)) {
      // We're passed the snap size, return it instead.
      return _pixelSnapSize;
    }
    return newPosition;
  }

  // Find the two closest snap sizes to the position. If the velocity is
  // non-zero, select the size in the velocity's direction. Otherwise,
  // the nearest snap size.
  double _getSnapSize(double initialVelocity, List<double> pixelSnapSizes) {
    final int indexOfNextSize =
        pixelSnapSizes.indexWhere((double size) => size >= position);
    if (indexOfNextSize == 0) {
      return pixelSnapSizes.first;
    }
    final double nextSize = pixelSnapSizes[indexOfNextSize];
    final double previousSize = pixelSnapSizes[indexOfNextSize - 1];
    if (initialVelocity.abs() <= tolerance.velocity) {
      // If velocity is zero, snap to the nearest snap size with the minimum velocity.
      if (position - previousSize < nextSize - position) {
        return previousSize;
      } else {
        return nextSize;
      }
    }
    // Snap forward or backward depending on current velocity.
    if (initialVelocity < 0.0) {
      return pixelSnapSizes[indexOfNextSize - 1];
    }
    return pixelSnapSizes[indexOfNextSize];
  }
}

/// A [Notification] related to the extent, which is the size, and scroll
/// offset, which is the position of the child list, of the
/// [DynamicDraggableScrollableSheet].
///
/// [DynamicDraggableScrollableSheet] widgets notify their ancestors when the size of
/// the sheet changes. When the extent of the sheet changes via a drag,
/// this notification bubbles up through the tree, which means a given
/// [NotificationListener] will receive notifications for all descendant
/// [DynamicDraggableScrollableSheet] widgets. To focus on notifications from the
/// nearest [DynamicDraggableScrollableSheet] descendant, check that the [depth]
/// property of the notification is zero.
///
/// When an extent notification is received by a [NotificationListener], the
/// listener will already have completed build and layout, and it is therefore
/// too late for that widget to call [State.setState]. Any attempt to adjust the
/// build or layout based on an extent notification would result in a layout
/// that lagged one frame behind, which is a poor user experience. Extent
/// notifications are used primarily to drive animations. The [Scaffold] widget
/// listens for extent notifications and responds by driving animations for the
/// [FloatingActionButton] as the bottom sheet scrolls up.
class DynamicDraggableScrollableNotification extends Notification
    with ViewportNotificationMixin {
  /// Creates a notification that the extent of a [DynamicDraggableScrollableSheet] has
  /// changed.
  ///
  /// All parameters are required. The [minExtent] must be >= 0. The [maxExtent]
  /// must be <= 1.0. The [extent] must be between [minExtent] and [maxExtent].
  DynamicDraggableScrollableNotification({
    required this.extent,
    required this.minExtent,
    required this.maxExtent,
    required this.initialExtent,
    required this.context,
    this.shouldCloseOnMinExtent = true,
  })  : assert(0.0 <= minExtent),
        assert(0.0 <= maxExtent),
        assert(minExtent <= extent),
        assert(minExtent <= initialExtent),
        assert(extent <= maxExtent),
        assert(initialExtent <= maxExtent);

  /// The current value of the extent, between [minExtent] and [maxExtent].
  final double extent;

  /// The minimum value of [extent], which is >= 0.
  final double minExtent;

  /// The maximum value of [extent].
  final double maxExtent;

  /// The initially requested value for [extent].
  final double initialExtent;

  /// The build context of the widget that fired this notification.
  ///
  /// This can be used to find the sheet's render objects to determine the size
  /// of the viewport, for instance. A listener can only assume this context
  /// is live when it first gets the notification.
  final BuildContext context;

  /// Whether the widget that fired this notification, when dragged (or flung)
  /// to minExtent, should cause its parent sheet to close.
  ///
  /// It is up to parent classes to properly read and handle this value.
  final bool shouldCloseOnMinExtent;

  @override
  void debugFillDescription(List<String> description) {
    super.debugFillDescription(description);
    description.add(
        'minExtent: $minExtent, extent: $extent, maxExtent: $maxExtent, initialExtent: $initialExtent');
  }
}

/// A container for a [Scrollable] that responds to drag gestures by resizing
/// the scrollable until a limit is reached, and then scrolling.
///
/// {@youtube 560 315 https://www.youtube.com/watch?v=Hgw819mL_78}
///
/// This widget can be dragged along the vertical axis between its
/// [minChildSize], which defaults to `0.25` and [maxChildSize], which defaults
/// to `1.0`. These sizes are percentages of the height of the parent container.
///
/// The widget coordinates resizing and scrolling of the widget returned by
/// builder as the user drags along the horizontal axis.
///
/// The widget will initially be displayed at its initialChildSize which
/// defaults to `0.5`, meaning half the height of its parent. Dragging will work
/// between the range of minChildSize and maxChildSize (as percentages of the
/// parent container's height) as long as the builder creates a widget which
/// uses the provided [ScrollController]. If the widget created by the
/// [ScrollableWidgetBuilder] does not use the provided [ScrollController], the
/// sheet will remain at the initialChildSize.
///
/// By default, the widget will stay at whatever size the user drags it to. To
/// make the widget snap to specific sizes whenever they lift their finger
/// during a drag, set [snap] to `true`. The sheet will snap between
/// [minChildSize] and [maxChildSize]. Use [snapSizes] to add more sizes for
/// the sheet to snap between.
///
/// The snapping effect is only applied on user drags. Programmatically
/// manipulating the sheet size via [DraggableScrollableController.animateTo] or
/// [DraggableScrollableController.jumpTo] will ignore [snap] and [snapSizes].
///
/// By default, the widget will expand its non-occupied area to fill available
/// space in the parent. If this is not desired, e.g. because the parent wants
/// to position sheet based on the space it is taking, the [expand] property
/// may be set to false.
///
/// {@tool snippet}
///
/// This is a sample widget which shows a [ListView] that has 25 [ListTile]s.
/// It starts out as taking up half the body of the [Scaffold], and can be
/// dragged up to the full height of the scaffold or down to 25% of the height
/// of the scaffold. Upon reaching full height, the list contents will be
/// scrolled up or down, until they reach the top of the list again and the user
/// drags the sheet back down.
///
/// ```dart
/// class HomePage extends StatelessWidget {
///   const HomePage({super.key});
///
///   @override
///   Widget build(BuildContext context) {
///     return Scaffold(
///       appBar: AppBar(
///         title: const Text('DraggableScrollableSheet'),
///       ),
///       body: SizedBox.expand(
///         child: DraggableScrollableSheet(
///           builder: (BuildContext context, ScrollController scrollController) {
///             return Container(
///               color: Colors.blue[100],
///               child: ListView.builder(
///                 controller: scrollController,
///                 itemCount: 25,
///                 itemBuilder: (BuildContext context, int index) {
///                   return ListTile(title: Text('Item $index'));
///                 },
///               ),
///             );
///           },
///         ),
///       ),
///     );
///   }
/// }
/// ```
/// {@end-tool}
class DynamicDraggableScrollableSheet extends StatefulWidget {
  /// Creates a widget that can be dragged and scrolled in a single gesture.
  ///
  /// The [builder], [initialChildSize], [minChildSize], [maxChildSize] and
  /// [expand] parameters must not be null.
  const DynamicDraggableScrollableSheet({
    super.key,
    required this.initialChildSize,
    required this.minChildSize,
    required this.maxChildSize,
    this.expand = true,
    this.snapAnimationDuration,
    this.controller,
    this.shouldCloseOnMinExtent = true,
    required this.builder,
  })  : assert(minChildSize >= 0.0),
        assert(maxChildSize >= 0.0),
        assert(minChildSize <= initialChildSize),
        assert(initialChildSize <= maxChildSize),
        assert(snapAnimationDuration == null ||
            snapAnimationDuration > Duration.zero);

  /// The initial fractional value of the parent container's height to use when
  /// displaying the widget.
  ///
  /// Rebuilding the sheet with a new [initialChildSize] will only move
  /// the sheet to the new value if the sheet has not yet been dragged since it
  /// was first built or since the last call to [DraggableScrollableActuator.reset].
  ///
  /// The default value is `0.5`.
  final double initialChildSize;

  /// The minimum fractional value of the parent container's height to use when
  /// displaying the widget.
  ///
  /// The default value is `0.25`.
  final double minChildSize;

  /// The maximum fractional value of the parent container's height to use when
  /// displaying the widget.
  ///
  /// The default value is `1.0`.
  final double maxChildSize;

  /// Whether the widget should expand to fill the available space in its parent
  /// or not.
  ///
  /// In most cases, this should be true. However, in the case of a parent
  /// widget that will position this one based on its desired size (such as a
  /// [Center]), this should be set to false.
  ///
  /// The default value is true.
  final bool expand;

  /// Defines a duration for the snap animations.
  ///
  /// If it's not set, then the animation duration is the distance to the snap
  /// target divided by the velocity of the widget.
  final Duration? snapAnimationDuration;

  /// A controller that can be used to programmatically control this sheet.
  final DynamicDraggableScrollableController? controller;

  /// Whether the sheet, when dragged (or flung) to its minimum size, should
  /// cause its parent sheet to close.
  ///
  /// Set on emitted [DraggableScrollableNotification]s. It is up to parent
  /// classes to properly read and handle this value.
  final bool shouldCloseOnMinExtent;

  /// The builder that creates a child to display in this widget, which will
  /// use the provided [ScrollController] to enable dragging and scrolling
  /// of the contents.
  final ScrollableWidgetBuilder builder;

  @override
  State<DynamicDraggableScrollableSheet> createState() =>
      _DynamicDraggableScrollableSheetState();
}

class _DynamicDraggableScrollableSheetState
    extends State<DynamicDraggableScrollableSheet> {
  late _DynamicDraggableScrollableSheetScrollController _scrollController;
  late _DynamicDraggableSheetExtent _extent;
  late double _contentSnapSize = widget.minChildSize;

  @override
  void initState() {
    super.initState();

    _extent = _DynamicDraggableSheetExtent(
      minPixels: widget.minChildSize,
      maxPixels: widget.maxChildSize,
      contentPixels: _contentSnapSize,
      snap: true,
      initialPixels: widget.initialChildSize,
      snapPixels: _impliedSnapSizes(),
      snapAnimationDuration: widget.snapAnimationDuration,
      shouldCloseOnMinExtent: widget.shouldCloseOnMinExtent,
    );

    _scrollController = _DynamicDraggableScrollableSheetScrollController(
      extent: _extent,
    );

    widget.controller?._attach(_scrollController);
  }

  List<double> _impliedSnapSizes() {
    final clampedSnapSize = clampDouble(
      _contentSnapSize,
      widget.minChildSize,
      widget.maxChildSize,
    );

    return <double>[
      widget.minChildSize,
      if (clampedSnapSize > widget.minChildSize &&
          clampedSnapSize < widget.maxChildSize)
        clampedSnapSize,
      widget.maxChildSize,
    ];
  }

  @override
  void didUpdateWidget(covariant DynamicDraggableScrollableSheet oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (widget.controller != oldWidget.controller) {
      oldWidget.controller?._detach();
      widget.controller?._attach(_scrollController);
    }

    _replaceExtent();
  }

  void _onContentExtentMeasured(double extent, bool shouldSetExtent) {
    if (extent == _contentSnapSize) return;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (shouldSetExtent) {
        DynamicDraggableScrollableNotification(
          minExtent: _extent.minPixels,
          maxExtent: _extent.maxPixels,
          extent: extent,
          initialExtent: _extent.initialPixels,
          context: context,
          shouldCloseOnMinExtent: widget.shouldCloseOnMinExtent,
        ).dispatch(context);
      }

      setState(() {
        _contentSnapSize = extent;
        _replaceExtent(shouldSetExtent ? extent : null);
      });
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // if (_InheritedResetNotifier.shouldReset(context)) {
    //   _scrollController.reset();
    // }
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<double>(
      valueListenable: _extent._currentPixels,
      builder: (BuildContext context, double currentPixels, Widget? child) =>
          LayoutBuilder(
        builder: (BuildContext context, BoxConstraints constraints) {
          _extent.availablePixels =
              widget.maxChildSize * constraints.biggest.height;
          final Widget sheet = Align(
            alignment: Alignment.bottomCenter,
            child: _DynamicDraggableScrollableSheetRenderObjectWidget(
              extent: _extent,
              onContentExtentMeasured: _onContentExtentMeasured,
              child: child,
            ),
          );

          return widget.expand ? SizedBox.expand(child: sheet) : sheet;
        },
      ),
      child: widget.builder(context, _scrollController),
    );
  }

  @override
  void dispose() {
    widget.controller?._detach(disposeExtent: true);
    _scrollController.dispose();
    super.dispose();
  }

  void _replaceExtent([double? newPixels]) {
    final _DynamicDraggableSheetExtent previousExtent = _extent;

    _extent = previousExtent.copyWith(
      minPixels: widget.minChildSize,
      maxPixels: widget.maxChildSize,
      contentPixels: _contentSnapSize,
      snap: true,
      snapPixels: _impliedSnapSizes(),
      snapAnimationDuration: widget.snapAnimationDuration,
      initialPixels: widget.initialChildSize,
    );

    if (newPixels != null) {
      _extent._currentPixels.value = newPixels;
    }

    // Modify the existing scroll controller instead of replacing it so that
    // developers listening to the controller do not have to rebuild their listeners.
    _scrollController.extent = _extent;
    // If an external facing controller was provided, let it know that the
    // extent has been replaced.
    widget.controller?._onExtentReplaced(previousExtent);
    previousExtent.dispose();
  }
}

typedef _OnContentExtentMeasuredFn = void Function(
  double extent,
  bool shouldSetExtent,
);

class _DynamicDraggableScrollableSheetRenderObjectWidget
    extends SingleChildRenderObjectWidget {
  const _DynamicDraggableScrollableSheetRenderObjectWidget({
    super.key,
    super.child,
    required this.extent,
    required this.onContentExtentMeasured,
  });

  final _DynamicDraggableSheetExtent extent;
  final _OnContentExtentMeasuredFn onContentExtentMeasured;

  @override
  RenderObject createRenderObject(BuildContext context) {
    return _DynamicDraggableScrollableSheetRenderObject(
      extent: extent,
      onContentExtentMeasured: onContentExtentMeasured,
    );
  }

  @override
  void updateRenderObject(
    BuildContext context,
    _DynamicDraggableScrollableSheetRenderObject renderObject,
  ) {
    renderObject.extent = extent;
    renderObject.onContentExtentMeasured = onContentExtentMeasured;
  }
}

class _DynamicDraggableScrollableSheetRenderObject extends RenderProxyBox {
  _DynamicDraggableScrollableSheetRenderObject({
    required _DynamicDraggableSheetExtent extent,
    required _OnContentExtentMeasuredFn onContentExtentMeasured,
  })  : _extent = extent,
        _onContentExtentMeasured = onContentExtentMeasured;

  _DynamicDraggableSheetExtent _extent;
  _DynamicDraggableSheetExtent get extent => _extent;

  set extent(_DynamicDraggableSheetExtent value) {
    _extent = value;
    markNeedsLayout();
  }

  _OnContentExtentMeasuredFn _onContentExtentMeasured;
  _OnContentExtentMeasuredFn get onContentExtentMeasured =>
      _onContentExtentMeasured;

  set onContentExtentMeasured(_OnContentExtentMeasuredFn value) {
    _onContentExtentMeasured = value;
    markNeedsLayout();
  }

  _DynamicDraggableScrollableSheetContentRenderObject? _contentChild;

  void _attachContentChild(
    _DynamicDraggableScrollableSheetContentRenderObject child,
  ) {
    _contentChild = child;
  }

  void _detachContentChild(
    _DynamicDraggableScrollableSheetContentRenderObject child,
  ) {
    assert(_contentChild == child);
    _contentChild = null;
  }

  double? _previousContentExtent;

  @override
  void performLayout() {
    if (child == null) {
      size = constraints.smallest;
      return;
    }

    double? height;

    // Compute the dry extent of the content.
    final contentExtent = _contentChild
        ?.getDryLayout(
          constraints.copyWith(
              minHeight: _extent.minPixels, maxHeight: _extent.maxPixels),
        )
        .height;

    if (contentExtent != null) {
      late final bool wasExtentSetToContent;

      if (_previousContentExtent != null &&
          _extent.snapPixels.length == 3 &&
          contentExtent >= _extent.minPixels &&
          contentExtent <= _extent.maxPixels &&
          (_previousContentExtent! - _extent.currentPixels).abs() <= 1e-6) {
        height = contentExtent;
        wasExtentSetToContent = true;
      } else {
        wasExtentSetToContent = false;
      }

      _onContentExtentMeasured(contentExtent, wasExtentSetToContent);
    }

    height ??= _extent.currentPixels;

    child!.layout(
      constraints.copyWith(
        minHeight: height,
        maxHeight: height,
      ),
      parentUsesSize: true,
    );

    size = Size(
      child!.size.width,
      height,
    );

    _previousContentExtent = contentExtent;
  }
}

class DynamicDraggableScrollableSheetContent
    extends SingleChildRenderObjectWidget {
  const DynamicDraggableScrollableSheetContent({
    super.key,
    required super.child,
  });

  @override
  RenderObject createRenderObject(BuildContext context) {
    return _DynamicDraggableScrollableSheetContentRenderObject();
  }
}

class _DynamicDraggableScrollableSheetContentRenderObject
    extends RenderProxyBox {
  _DynamicDraggableScrollableSheetContentRenderObject();

  _DynamicDraggableScrollableSheetRenderObject? _sheetParent;

  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);

    // Find the parent [_DynamicDraggableScrollableSheetRenderObject] of this
    // render object.
    _findParent();
    _sheetParent?._attachContentChild(this);
  }

  @override
  void detach() {
    _sheetParent?._detachContentChild(this);
    super.detach();
  }

  /// Recursively finds the first parent that is of type
  /// [_DynamicDraggableScrollableSheetRenderObject].
  void _findParent() {
    var parent = this.parent;

    while (parent != null) {
      if (parent is _DynamicDraggableScrollableSheetRenderObject) {
        _sheetParent = parent;
        return;
      }

      parent = parent.parent;
    }
  }
}
