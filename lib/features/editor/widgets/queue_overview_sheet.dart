import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:path/path.dart' as p;

import '../../../core/models/media_job.dart';
import '../../../core/models/media_kind.dart';

class QueueOverviewSheet extends StatefulWidget {
  const QueueOverviewSheet({
    super.key,
    required this.jobs,
    required this.selectedJobId,
    required this.busy,
    required this.onSelected,
    required this.onRemove,
  });

  final List<MediaJob> jobs;
  final String? selectedJobId;
  final bool busy;
  final ValueChanged<String> onSelected;
  final bool Function(String id) onRemove;

  @override
  State<QueueOverviewSheet> createState() => _QueueOverviewSheetState();
}

class _QueueOverviewSheetState extends State<QueueOverviewSheet> {
  late List<MediaJob> _jobs;
  late String? _selectedJobId;

  @override
  void initState() {
    super.initState();
    _jobs = [...widget.jobs];
    _selectedJobId = widget.selectedJobId;
  }

  @override
  Widget build(BuildContext context) {
    final screenHeight = MediaQuery.sizeOf(context).height;
    return CupertinoPopupSurface(
      isSurfacePainted: true,
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: screenHeight * .82,
          child: Column(
            children: [
              _header(context),
              if (widget.busy)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
                    decoration: BoxDecoration(
                      color: CupertinoColors.systemOrange.withValues(
                        alpha: .12,
                      ),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Text(
                      'The active item is locked. Ready items can still be removed.',
                      style: TextStyle(fontSize: 13),
                    ),
                  ),
                ),
              Expanded(
                child: _jobs.isEmpty
                    ? const Center(child: Text('No selected media.'))
                    : ListView.separated(
                        key: const Key('queue_overview_list'),
                        padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                        itemCount: _jobs.length,
                        separatorBuilder: (_, _) => const SizedBox(height: 8),
                        itemBuilder: (context, index) =>
                            _jobTile(context, _jobs[index], index),
                      ),
              ),
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
                  'Selection',
                  style: CupertinoTheme.of(context).textTheme.navTitleTextStyle,
                ),
                const SizedBox(height: 2),
                Text(
                  '${_jobs.length} item${_jobs.length == 1 ? '' : 's'} in the queue',
                  style: CupertinoTheme.of(context).textTheme.textStyle
                      .copyWith(
                        color: CupertinoColors.secondaryLabel.resolveFrom(
                          context,
                        ),
                        fontSize: 13,
                      ),
                ),
              ],
            ),
          ),
          CupertinoButton(
            key: const Key('queue_overview_done'),
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Done'),
          ),
        ],
      ),
    );
  }

  Widget _jobTile(BuildContext context, MediaJob job, int index) {
    final selected = job.id == _selectedJobId;
    final primary = CupertinoTheme.of(context).primaryColor;
    final canRemove = !widget.busy || job.status == JobStatus.pending;
    return Semantics(
      selected: selected,
      button: true,
      label:
          '${job.displayName ?? p.basename(job.inputPath)}, ${job.status.label}',
      child: GestureDetector(
        key: Key('queue_item_${job.id}'),
        behavior: HitTestBehavior.opaque,
        onTap: widget.busy
            ? null
            : () {
                setState(() => _selectedJobId = job.id);
                widget.onSelected(job.id);
                Navigator.of(context).pop();
              },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: selected
                ? primary.withValues(alpha: .12)
                : CupertinoColors.secondarySystemGroupedBackground.resolveFrom(
                    context,
                  ),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: selected
                  ? primary.withValues(alpha: .45)
                  : CupertinoColors.separator.resolveFrom(context),
            ),
          ),
          child: Row(
            children: [
              _thumbnail(context, job),
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
                      '${job.kind.label} · ${job.status.label}',
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
              _statusIcon(job),
              CupertinoButton(
                key: Key('queue_remove_${job.id}'),
                padding: const EdgeInsets.all(9),
                minimumSize: Size.zero,
                onPressed: canRemove ? () => _remove(job, index) : null,
                child: Icon(
                  CupertinoIcons.trash,
                  semanticLabel:
                      'Remove ${job.displayName ?? p.basename(job.inputPath)} from queue',
                  size: 19,
                  color: canRemove
                      ? CupertinoColors.destructiveRed
                      : CupertinoColors.systemGrey3.resolveFrom(context),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _thumbnail(BuildContext context, MediaJob job) {
    final placeholder = ColoredBox(
      color: CupertinoColors.systemGrey5.resolveFrom(context),
      child: Icon(
        job.kind.isVideo ? CupertinoIcons.film : CupertinoIcons.photo,
        color: CupertinoColors.secondaryLabel.resolveFrom(context),
        size: 23,
      ),
    );
    return ClipRRect(
      borderRadius: BorderRadius.circular(11),
      child: SizedBox(
        width: 58,
        height: 58,
        child: job.kind.isImage && !job.kind.isRaw
            ? Image.file(
                File(job.inputPath),
                fit: BoxFit.cover,
                cacheWidth: 160,
                errorBuilder: (_, _, _) => placeholder,
              )
            : placeholder,
      ),
    );
  }

  Widget _statusIcon(MediaJob job) {
    return switch (job.status) {
      JobStatus.processing => const Padding(
        padding: EdgeInsets.symmetric(horizontal: 7),
        child: CupertinoActivityIndicator(radius: 9),
      ),
      JobStatus.complete => const Icon(
        CupertinoIcons.check_mark_circled_solid,
        color: CupertinoColors.activeGreen,
        size: 20,
      ),
      JobStatus.failed => const Icon(
        CupertinoIcons.exclamationmark_triangle_fill,
        color: CupertinoColors.destructiveRed,
        size: 20,
      ),
      JobStatus.pending => const SizedBox(width: 20),
    };
  }

  void _remove(MediaJob job, int index) {
    if (!widget.onRemove(job.id)) return;
    setState(() {
      _jobs.removeAt(index);
      if (_selectedJobId == job.id) {
        _selectedJobId = _jobs.isEmpty
            ? null
            : _jobs[index.clamp(0, _jobs.length - 1)].id;
      }
    });
    if (_jobs.isEmpty && mounted) Navigator.of(context).pop();
  }
}
