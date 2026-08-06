import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:path/path.dart' as p;

import '../../../core/models/media_job.dart';
import '../../../core/models/media_kind.dart';

class BatchEditCopySheet extends StatefulWidget {
  const BatchEditCopySheet({
    super.key,
    required this.source,
    required this.targets,
    required this.onApplySelected,
    required this.onApplyAll,
  });

  final MediaJob source;
  final List<MediaJob> targets;
  final Future<bool> Function(Set<String> targetIds) onApplySelected;
  final Future<bool> Function() onApplyAll;

  @override
  State<BatchEditCopySheet> createState() => _BatchEditCopySheetState();
}

class _BatchEditCopySheetState extends State<BatchEditCopySheet> {
  final Set<String> _selectedIds = {};
  bool _applying = false;

  @override
  Widget build(BuildContext context) {
    final height = MediaQuery.sizeOf(context).height * .78;
    return CupertinoPopupSurface(
      isSurfacePainted: true,
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: height,
          child: Column(
            children: [
              _header(context),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
                child: _sourceCard(context),
              ),
              Expanded(
                child: widget.targets.isEmpty
                    ? const Center(
                        child: Padding(
                          padding: EdgeInsets.all(24),
                          child: Text(
                            'There are no other photos in this batch.',
                            textAlign: TextAlign.center,
                          ),
                        ),
                      )
                    : ListView.separated(
                        key: const Key('batch_edit_target_list'),
                        padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
                        itemCount: widget.targets.length,
                        separatorBuilder: (_, _) => const SizedBox(height: 8),
                        itemBuilder: (context, index) =>
                            _targetTile(context, widget.targets[index]),
                      ),
              ),
              _actions(context),
            ],
          ),
        ),
      ),
    );
  }

  Widget _header(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 10, 10),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Copy edits',
                  style: CupertinoTheme.of(context).textTheme.navTitleTextStyle,
                ),
                const SizedBox(height: 2),
                Text(
                  'Choose the photos that should use these values.',
                  style: TextStyle(
                    color: CupertinoColors.secondaryLabel.resolveFrom(context),
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ),
          CupertinoButton(
            key: const Key('batch_edit_copy_done'),
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
            onPressed: _applying ? null : () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
        ],
      ),
    );
  }

  Widget _sourceCard(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: CupertinoTheme.of(context).primaryColor.withValues(alpha: .10),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: CupertinoTheme.of(context).primaryColor.withValues(alpha: .28),
        ),
      ),
      child: Row(
        children: [
          _thumbnail(context, widget.source, size: 48),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Copy from',
                  style: TextStyle(
                    color: CupertinoColors.activeBlue,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  widget.source.displayName ??
                      p.basename(widget.source.inputPath),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _targetTile(BuildContext context, MediaJob job) {
    final selected = _selectedIds.contains(job.id);
    final primary = CupertinoTheme.of(context).primaryColor;
    return Semantics(
      selected: selected,
      button: true,
      label:
          '${selected ? 'Deselect' : 'Select'} ${job.displayName ?? p.basename(job.inputPath)}',
      child: GestureDetector(
        key: Key('batch_edit_target_${job.id}'),
        behavior: HitTestBehavior.opaque,
        onTap: _applying
            ? null
            : () => setState(() {
                if (!selected) {
                  _selectedIds.add(job.id);
                } else {
                  _selectedIds.remove(job.id);
                }
              }),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.all(9),
          decoration: BoxDecoration(
            color: selected
                ? primary.withValues(alpha: .12)
                : CupertinoColors.secondarySystemGroupedBackground.resolveFrom(
                    context,
                  ),
            borderRadius: BorderRadius.circular(15),
            border: Border.all(
              color: selected
                  ? primary.withValues(alpha: .45)
                  : CupertinoColors.separator.resolveFrom(context),
            ),
          ),
          child: Row(
            children: [
              _thumbnail(context, job, size: 50),
              const SizedBox(width: 11),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      job.displayName ?? p.basename(job.inputPath),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      _details(job),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: CupertinoColors.secondaryLabel.resolveFrom(
                          context,
                        ),
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Icon(
                selected
                    ? CupertinoIcons.check_mark_circled_solid
                    : CupertinoIcons.circle,
                color: selected
                    ? primary
                    : CupertinoColors.tertiaryLabel.resolveFrom(context),
                size: 23,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _actions(BuildContext context) {
    final canApplySelected = _selectedIds.isNotEmpty && !_applying;
    final canApplyAll = widget.targets.isNotEmpty && !_applying;
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      decoration: BoxDecoration(
        color: CupertinoColors.systemBackground.resolveFrom(context),
        border: Border(
          top: BorderSide(color: CupertinoColors.separator.resolveFrom(context)),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: CupertinoButton(
              key: const Key('batch_edit_apply_all'),
              color: CupertinoColors.secondarySystemFill.resolveFrom(context),
              onPressed: canApplyAll ? _applyAll : null,
              child: const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(CupertinoIcons.rectangle_stack_badge_plus, size: 19),
                  SizedBox(width: 7),
                  Text('Apply to all'),
                ],
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: CupertinoButton.filled(
              key: const Key('batch_edit_apply_selected'),
              onPressed: canApplySelected ? _applySelected : null,
              child: _applying
                  ? const CupertinoActivityIndicator(
                      color: CupertinoColors.white,
                    )
                  : Text('Apply to ${_selectedIds.length}'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _thumbnail(BuildContext context, MediaJob job, {required double size}) {
    final placeholder = ColoredBox(
      color: CupertinoColors.systemGrey5.resolveFrom(context),
      child: Icon(
        job.kind.isVideo ? CupertinoIcons.film : CupertinoIcons.photo,
        color: CupertinoColors.secondaryLabel.resolveFrom(context),
        size: 21,
      ),
    );
    return ClipRRect(
      borderRadius: BorderRadius.circular(10),
      child: SizedBox(
        width: size,
        height: size,
        child: job.kind.isImage && !job.kind.isRaw
            ? Image.file(
                File(job.inputPath),
                fit: BoxFit.cover,
                cacheWidth: 140,
                errorBuilder: (_, _, _) => placeholder,
              )
            : placeholder,
      ),
    );
  }

  String _details(MediaJob job) => [
    job.status.label,
    if (job.metadata?.sizeLabel != null) job.metadata!.sizeLabel,
    if (job.metadata?.dimensionsLabel != null) job.metadata!.dimensionsLabel!,
  ].join(' · ');

  Future<void> _applySelected() async {
    setState(() => _applying = true);
    final applied = await widget.onApplySelected(Set.of(_selectedIds));
    if (!mounted) return;
    setState(() => _applying = false);
    if (applied) Navigator.of(context).pop();
  }

  Future<void> _applyAll() async {
    setState(() => _applying = true);
    final applied = await widget.onApplyAll();
    if (!mounted) return;
    setState(() => _applying = false);
    if (applied) Navigator.of(context).pop();
  }
}
