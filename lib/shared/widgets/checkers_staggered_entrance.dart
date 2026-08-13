import 'package:flutter/material.dart';

class CheckersStaggeredEntrance extends StatefulWidget {
  const CheckersStaggeredEntrance({
    required this.children,
    super.key,
    this.initialOffset = const Offset(0, -24),
    this.itemDelay = const Duration(milliseconds: 120),
    this.itemDuration = const Duration(milliseconds: 460),
    this.curve = Curves.easeOutCubic,
    this.crossAxisAlignment = CrossAxisAlignment.center,
  });

  final List<Widget> children;
  final Offset initialOffset;
  final Duration itemDelay;
  final Duration itemDuration;
  final Curve curve;
  final CrossAxisAlignment crossAxisAlignment;

  @override
  State<CheckersStaggeredEntrance> createState() =>
      _CheckersStaggeredEntranceState();
}

class _CheckersStaggeredEntranceState extends State<CheckersStaggeredEntrance>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    final totalDuration =
        widget.itemDuration +
        (widget.itemDelay * (widget.children.length - 1).clamp(0, 1000));

    _controller = AnimationController(vsync: this, duration: totalDuration)
      ..forward();
  }

  @override
  void didUpdateWidget(covariant CheckersStaggeredEntrance oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.children.length != widget.children.length ||
        oldWidget.itemDelay != widget.itemDelay ||
        oldWidget.itemDuration != widget.itemDuration) {
      final totalDuration =
          widget.itemDuration +
          (widget.itemDelay * (widget.children.length - 1).clamp(0, 1000));
      _controller
        ..duration = totalDuration
        ..forward(from: 0);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final totalMilliseconds = _controller.duration!.inMilliseconds;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: widget.crossAxisAlignment,
      children: [
        for (var index = 0; index < widget.children.length; index++)
          _AnimatedEntranceItem(
            animation: _controller,
            begin:
                (widget.itemDelay.inMilliseconds * index) / totalMilliseconds,
            end:
                ((widget.itemDelay.inMilliseconds * index) +
                    widget.itemDuration.inMilliseconds) /
                totalMilliseconds,
            initialOffset: widget.initialOffset,
            curve: widget.curve,
            child: widget.children[index],
          ),
      ],
    );
  }
}

class _AnimatedEntranceItem extends StatelessWidget {
  const _AnimatedEntranceItem({
    required this.animation,
    required this.begin,
    required this.end,
    required this.initialOffset,
    required this.curve,
    required this.child,
  });

  final Animation<double> animation;
  final double begin;
  final double end;
  final Offset initialOffset;
  final Curve curve;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final itemAnimation = CurvedAnimation(
      parent: animation,
      curve: Interval(begin, end.clamp(0.0, 1.0), curve: curve),
    );

    return AnimatedBuilder(
      animation: itemAnimation,
      child: child,
      builder: (context, child) {
        return Opacity(
          opacity: itemAnimation.value,
          child: Transform.translate(
            offset: Offset.lerp(
              initialOffset,
              Offset.zero,
              itemAnimation.value,
            )!,
            child: child,
          ),
        );
      },
    );
  }
}
