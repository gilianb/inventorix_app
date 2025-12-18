part of '../table_by_status.dart';

class _HeaderCell extends StatelessWidget {
  const _HeaderCell({
    required this.title,
    required this.isSorted,
    required this.ascending,
    required this.onTap,
  });

  final String title;
  final bool isSorted;
  final bool ascending;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme.labelLarge;

    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(
              child: Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: style?.copyWith(fontWeight: FontWeight.w700),
              ),
            ),
            const SizedBox(width: 6),
            if (isSorted)
              Icon(
                ascending ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down,
                size: 18,
                color: Theme.of(context).colorScheme.onSurface.withOpacity(.70),
              ),
          ],
        ),
      ),
    );
  }
}

class _ColumnResizeHandle extends StatefulWidget {
  const _ColumnResizeHandle({
    required this.height,
    required this.onDrag,
    required this.accent,
    this.subtle = false,
  });

  final double height;
  final ValueChanged<double> onDrag;
  final Color accent;
  final bool subtle;

  @override
  State<_ColumnResizeHandle> createState() => _ColumnResizeHandleState();
}

class _ColumnResizeHandleState extends State<_ColumnResizeHandle> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final lineColor =
        _hover ? widget.accent.withOpacity(.80) : Colors.black.withOpacity(.12);

    return MouseRegion(
      cursor: SystemMouseCursors.resizeColumn,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onHorizontalDragUpdate: (details) => widget.onDrag(details.delta.dx),
        child: SizedBox(
          width: _kColumnDividerWidth,
          height: widget.height,
          child: Center(
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 120),
              curve: Curves.easeOut,
              width: _hover ? 2.0 : 1.0,
              height:
                  widget.subtle ? widget.height * 0.55 : widget.height * 0.75,
              decoration: BoxDecoration(
                color: lineColor,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
