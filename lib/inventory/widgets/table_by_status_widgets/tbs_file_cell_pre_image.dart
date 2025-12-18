part of '../table_by_status.dart';

class _FileCell extends StatelessWidget {
  const _FileCell({this.url, this.isImagePreferred = false});
  final String? url;
  final bool isImagePreferred;

  bool get _isImage {
    final u = url ?? '';
    if (u.isEmpty) return false;
    try {
      final path = Uri.parse(u).path.toLowerCase();
      return path.endsWith('.png') ||
          path.endsWith('.jpg') ||
          path.endsWith('.jpeg') ||
          path.endsWith('.gif') ||
          path.endsWith('.webp');
    } catch (_) {
      final lu = u.toLowerCase();
      return RegExp(r'\.(png|jpe?g|gif|webp)(\?.*)?$').hasMatch(lu);
    }
  }

  Future<void> _open() async {
    final u = url;
    if (u == null || u.isEmpty) return;
    final uri = Uri.parse(u);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (url == null || url!.isEmpty) return const Text('—');

    final showImage = isImagePreferred && _isImage;

    if (showImage) {
      final imgUrl = () {
        final u = url!;
        try {
          final uri = Uri.parse(u);
          final fixed = Uri(
            scheme: uri.scheme,
            userInfo: uri.userInfo.isEmpty ? null : uri.userInfo,
            host: uri.host,
            port: uri.hasPort ? uri.port : null,
            path: uri.path,
            query: uri.query.isEmpty ? null : uri.query,
            fragment: uri.fragment.isEmpty ? null : uri.fragment,
          ).toString();
          return fixed;
        } catch (_) {
          return Uri.encodeFull(u);
        }
      }();

      return _HoverableImageThumb(
        imgUrl: imgUrl,
        onTap: _open,
      );
    }

    return IconButton(
      icon: const Iconify(Mdi.file_document),
      tooltip: 'Open document',
      onPressed: _open,
    );
  }
}

class _HoverableImageThumb extends StatefulWidget {
  const _HoverableImageThumb({
    required this.imgUrl,
    this.onTap,
  });

  final String imgUrl;
  final VoidCallback? onTap;

  @override
  State<_HoverableImageThumb> createState() => _HoverableImageThumbState();
}

class _HoverableImageThumbState extends State<_HoverableImageThumb> {
  OverlayEntry? _overlayEntry;

  void _showPreview(PointerEnterEvent event) {
    if (_overlayEntry != null) return;

    final overlay = Overlay.of(context);
    final offset = event.position;

    _overlayEntry = OverlayEntry(
      builder: (ctx) {
        return Positioned(
          left: offset.dx + 12,
          top: offset.dy + 12,
          child: IgnorePointer(
            ignoring: true,
            child: Material(
              elevation: 6,
              borderRadius: BorderRadius.circular(8),
              clipBehavior: Clip.antiAlias,
              child: Container(
                constraints: const BoxConstraints(
                  maxWidth: 320,
                  maxHeight: 320,
                ),
                child: Image.network(
                  widget.imgUrl,
                  fit: BoxFit.contain,
                  filterQuality: FilterQuality.medium,
                ),
              ),
            ),
          ),
        );
      },
    );

    overlay.insert(_overlayEntry!);
  }

  void _hidePreview([PointerExitEvent? event]) {
    _overlayEntry?.remove();
    _overlayEntry = null;
  }

  @override
  void dispose() {
    _hidePreview();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: _showPreview,
      onExit: _hidePreview,
      child: InkWell(
        onTap: widget.onTap,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: Image.network(
            widget.imgUrl,
            height: 32,
            width: 32,
            fit: BoxFit.cover,
            gaplessPlayback: true,
            filterQuality: FilterQuality.low,
            cacheWidth: 64,
            loadingBuilder: (ctx, child, progress) {
              if (progress == null) return child;
              return const SizedBox(
                height: 32,
                width: 32,
                child: Center(
                  child: SizedBox(
                    height: 14,
                    width: 14,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                ),
              );
            },
            errorBuilder: (_, __, ___) => const SizedBox(
              height: 32,
              width: 32,
              child: Icon(Icons.broken_image, size: 18),
            ),
          ),
        ),
      ),
    );
  }
}
