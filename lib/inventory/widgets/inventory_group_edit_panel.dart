import 'package:flutter/material.dart';

import '../ui/ix/ix.dart';
import '../utils/status_utils.dart';

class InventoryGroupEditPanel extends StatelessWidget {
  const InventoryGroupEditPanel({
    super.key,
    required this.enabled,
    required this.totalLines,
    required this.groupMode,
    required this.selectedCount,
    required this.onToggleGroupMode,
    required this.onClearSelection,
    required this.statuses,
    required this.newStatus,
    required this.onNewStatusChanged,
    required this.commentCtrl,
    required this.applying,
    required this.onApply,
  });

  final bool enabled;
  final int totalLines;

  final bool groupMode;
  final int selectedCount;
  final VoidCallback onToggleGroupMode;
  final VoidCallback onClearSelection;

  final List<String> statuses;
  final String? newStatus;
  final ValueChanged<String?> onNewStatusChanged;
  final TextEditingController commentCtrl;

  final bool applying;
  final VoidCallback onApply;

  @override
  Widget build(BuildContext context) {
    if (!enabled) return const SizedBox.shrink();
    final cs = Theme.of(context).colorScheme;

    return Padding(
      padding: IxSpace.page,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 10,
            runSpacing: 10,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(
                'Lines ($totalLines)',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w900,
                    ),
              ),
              OutlinedButton.icon(
                icon: Icon(groupMode ? Icons.group_off : Icons.group),
                label: Text(groupMode ? 'Exit group edit' : 'Edit group'),
                onPressed: onToggleGroupMode,
              ),
              if (groupMode) ...[
                IxPill(
                  label: '$selectedCount selected',
                  icon: Icons.check_circle,
                  color:
                      selectedCount > 0 ? IxColors.green : cs.onSurfaceVariant,
                ),
                if (selectedCount > 0)
                  TextButton.icon(
                    onPressed: onClearSelection,
                    icon: const Icon(Icons.clear_all),
                    label: const Text('Clear'),
                  ),
              ],
            ],
          ),
          const SizedBox(height: 10),
          AnimatedSize(
            duration: IxMotion.normal,
            curve: Curves.easeOutCubic,
            alignment: Alignment.topCenter,
            child: groupMode
                ? IxCard(
                    key: const ValueKey('group-edit-card'),
                    padding: IxSpace.card,
                    showDecorations: false,
                    borderColor: cs.outlineVariant.withOpacity(.45),
                    gradient: [
                      cs.surfaceContainerHighest.withOpacity(.65),
                      cs.surface.withOpacity(.02),
                    ],
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Wrap(
                          spacing: 12,
                          runSpacing: 12,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            SizedBox(
                              width: 280,
                              child: DropdownButtonFormField<String>(
                                isExpanded: true,
                                value: newStatus,
                                items: statuses.map((s) {
                                  final c = statusColor(context, s);
                                  return DropdownMenuItem<String>(
                                    value: s,
                                    child: Row(
                                      children: [
                                        Container(
                                          width: 10,
                                          height: 10,
                                          decoration: BoxDecoration(
                                            color: c,
                                            shape: BoxShape.circle,
                                          ),
                                        ),
                                        const SizedBox(width: 10),
                                        Text(
                                          s.toUpperCase(),
                                          style: TextStyle(
                                            fontWeight: FontWeight.w800,
                                            color: c,
                                          ),
                                        ),
                                      ],
                                    ),
                                  );
                                }).toList(),
                                onChanged: onNewStatusChanged,
                                decoration: ixDecoration(
                                  context,
                                  labelText: 'New status',
                                  hintText: 'Pick a status',
                                  prefixIcon: const Icon(Icons.flag_outlined),
                                ),
                              ),
                            ),
                            SizedBox(
                              width: 360,
                              child: TextField(
                                controller: commentCtrl,
                                decoration: ixDecoration(
                                  context,
                                  labelText: 'Comment (optional)',
                                  hintText: 'Reason, tracking, batch ref...',
                                  prefixIcon: const Icon(Icons.notes_outlined),
                                ),
                              ),
                            ),
                            FilledButton.icon(
                              onPressed: (newStatus != null &&
                                      selectedCount > 0 &&
                                      !applying)
                                  ? onApply
                                  : null,
                              icon: applying
                                  ? const SizedBox(
                                      height: 16,
                                      width: 16,
                                      child: CircularProgressIndicator(
                                          strokeWidth: 2),
                                    )
                                  : const Icon(Icons.done_all),
                              label: Text('Apply to $selectedCount line(s)'),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        Row(
                          children: [
                            Icon(Icons.info_outline,
                                size: 18, color: cs.onSurfaceVariant),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                'Only the status is modified. A log entry is saved for all affected items.',
                                style: Theme.of(context)
                                    .textTheme
                                    .bodySmall
                                    ?.copyWith(
                                      color: cs.onSurfaceVariant,
                                    ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  )
                : const SizedBox.shrink(),
          ),
        ],
      ),
    );
  }
}
