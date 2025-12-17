import 'package:flutter/material.dart';

class IxAnimatedNumberText extends StatefulWidget {
  const IxAnimatedNumberText({
    super.key,
    required this.value,
    this.fractionDigits = 2,
    this.prefix,
    this.suffix,
    this.style,
    this.duration = const Duration(milliseconds: 350),
    this.curve = Curves.easeOutCubic,
  });

  final num value;
  final int fractionDigits;
  final String? prefix;
  final String? suffix;
  final TextStyle? style;
  final Duration duration;
  final Curve curve;

  @override
  State<IxAnimatedNumberText> createState() => _IxAnimatedNumberTextState();
}

class _IxAnimatedNumberTextState extends State<IxAnimatedNumberText> {
  late double _from;

  @override
  void initState() {
    super.initState();
    _from = widget.value.toDouble();
  }

  @override
  void didUpdateWidget(covariant IxAnimatedNumberText oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.value != widget.value) {
      _from = oldWidget.value.toDouble();
    }
  }

  @override
  Widget build(BuildContext context) {
    final to = widget.value.toDouble();
    final prefix = widget.prefix ?? '';
    final suffix = widget.suffix ?? '';

    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: _from, end: to),
      duration: widget.duration,
      curve: widget.curve,
      builder: (context, v, _) {
        final txt = v.toStringAsFixed(widget.fractionDigits);
        return Text('$prefix$txt$suffix', style: widget.style);
      },
    );
  }
}
