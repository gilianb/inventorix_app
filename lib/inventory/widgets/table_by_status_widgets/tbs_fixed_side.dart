// ignore_for_file: deprecated_member_use

part of '../table_by_status.dart';

enum _FixedSide { left, right }

class _FixedSideColumn extends StatelessWidget {
  const _FixedSideColumn({
    required this.width,
    required this.headerHeight,
    required this.rowHeight,
    required this.side,
    required this.header,
    required this.rows,
  });

  final double width;
  final double headerHeight;
  final double rowHeight;
  final _FixedSide side;
  final Widget header;
  final List<Widget> rows;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    final shadow = side == _FixedSide.left
        ? [
            BoxShadow(
              color: Colors.black.withOpacity(0.06),
              blurRadius: 8,
              offset: const Offset(2, 0),
            )
          ]
        : [
            BoxShadow(
              color: Colors.black.withOpacity(0.06),
              blurRadius: 8,
              offset: const Offset(-2, 0),
            )
          ];

    return SizedBox(
      width: width,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: cs.surface,
          boxShadow: shadow,
          border: Border(
            right: side == _FixedSide.left
                ? BorderSide(color: cs.outlineVariant.withOpacity(.55))
                : BorderSide.none,
            left: side == _FixedSide.right
                ? BorderSide(color: cs.outlineVariant.withOpacity(.55))
                : BorderSide.none,
          ),
        ),
        child: Column(
          children: [
            Container(
              height: headerHeight,
              alignment: Alignment.center,
              color: cs.surfaceVariant.withOpacity(.40),
              child: header,
            ),
            ...rows,
          ],
        ),
      ),
    );
  }
}
