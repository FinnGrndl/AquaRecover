import 'package:flutter/cupertino.dart';

import '../../core/logbook/dive_log.dart';
import '../../l10n/l10n.dart';
import '../timeline/timeline_theme.dart';
import 'logbook_controller.dart';
import 'logbook_widgets.dart';
import '../../shared/widgets/sheet_width.dart';
import '../../shared/widgets/app_dialog.dart';

/// Adds a dive by hand or edits one.
class DiveEditPage extends StatefulWidget {
  const DiveEditPage({
    super.key,
    required this.controller,
    required this.dive,
    this.site,
    this.onDeleted,
  });

  final LogbookController controller;
  final Dive dive;
  final DiveSite? site;

  /// Called after the dive was deleted and this page closed.
  final VoidCallback? onDeleted;

  @override
  State<DiveEditPage> createState() => _DiveEditPageState();
}

class _DiveEditPageState extends State<DiveEditPage> {
  late DateTime _start = widget.dive.start;
  late final _number = _text(widget.dive.number.toString());
  late final _site = _text(widget.site?.name);
  late final _lat = _text(widget.site?.latitude?.toString());
  late final _lon = _text(widget.site?.longitude?.toString());
  late final _depth = _text(widget.dive.maxDepth?.toString());
  late final _minutes = _text(widget.dive.duration?.inMinutes.toString());
  late final _temp = _text(widget.dive.waterTemperature?.toString());
  late final _buddy = _text(widget.dive.buddy);
  late final _notes = _text(widget.dive.notes);

  static TextEditingController _text(String? value) =>
      TextEditingController(text: value ?? '');

  bool get _exists => widget.controller.dive(widget.dive.id) != null;

  @override
  void dispose() {
    for (final c in [
      _number,
      _site,
      _lat,
      _lon,
      _depth,
      _minutes,
      _temp,
      _buddy,
      _notes,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return TimelineTheme(
      child: CupertinoPageScaffold(
        backgroundColor: TimelineColors.background,
        navigationBar: CupertinoNavigationBar(
          backgroundColor: TimelineColors.background,
          leading: CupertinoButton(
            padding: EdgeInsets.zero,
            minimumSize: const Size(44, 44),
            onPressed: () => Navigator.of(context).pop(),
            child: Text(l10n.cancel),
          ),
          middle: Text(_exists ? l10n.editDive : l10n.newDive),
          trailing: CupertinoButton(
            key: const Key('dive_save'),
            padding: EdgeInsets.zero,
            minimumSize: const Size(44, 44),
            onPressed: _save,
            child: Text(
              l10n.save,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
        ),
        child: SafeArea(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
            children: [
              Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 600),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _field(l10n.diveNumber, _number, numeric: true),
                      _dateRow(),
                      _field(l10n.site, _site),
                      _field(l10n.latitude, _lat, numeric: true, signed: true),
                      _field(l10n.longitude, _lon, numeric: true, signed: true),
                      _field(l10n.maxDepthMeters, _depth, numeric: true),
                      _field(l10n.durationMinutes, _minutes, numeric: true),
                      _field(
                        l10n.waterTemperatureCelsius,
                        _temp,
                        numeric: true,
                        signed: true,
                      ),
                      _field(l10n.buddy, _buddy),
                      _field(l10n.notes, _notes, lines: 4),
                      if (_exists) ...[
                        const SizedBox(height: 24),
                        CupertinoButton(
                          minimumSize: const Size(44, 44),
                          onPressed: _delete,
                          child: Text(
                            l10n.deleteDive,
                            style: const TextStyle(
                              color: TimelineColors.danger,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _label(String text) => Padding(
    padding: const EdgeInsets.only(top: 12, bottom: 6),
    child: Text(
      text,
      style: const TextStyle(color: TimelineColors.secondaryText, fontSize: 13),
    ),
  );

  Widget _field(
    String label,
    TextEditingController controller, {
    bool numeric = false,
    bool signed = false,
    int lines = 1,
  }) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      ExcludeSemantics(child: _label(label)),
      Semantics(
        label: label,
        textField: true,
        child: CupertinoTextField(
          controller: controller,
          minLines: lines,
          maxLines: lines,
          padding: const EdgeInsets.all(12),
          style: const TextStyle(color: TimelineColors.text, fontSize: 17),
          keyboardType: numeric
              ? TextInputType.numberWithOptions(decimal: true, signed: signed)
              : (lines > 1 ? TextInputType.multiline : TextInputType.text),
          decoration: BoxDecoration(
            color: TimelineColors.fill,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: TimelineColors.stroke),
          ),
        ),
      ),
    ],
  );

  Widget _dateRow() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      ExcludeSemantics(child: _label(context.l10n.dateAndTime)),
      CupertinoButton(
        padding: const EdgeInsets.all(12),
        minimumSize: const Size(44, 44),
        color: TimelineColors.fill,
        borderRadius: BorderRadius.circular(10),
        onPressed: _pickDate,
        child: Align(
          alignment: Alignment.centerLeft,
          child: Text(
            formatDiveDate(context.l10n, _start),
            semanticsLabel: context.l10n.dateAndTimeValue(
              formatDiveDate(context.l10n, _start),
            ),
            style: const TextStyle(color: TimelineColors.text, fontSize: 17),
          ),
        ),
      ),
    ],
  );

  void _pickDate() {
    showCupertinoModalPopup<void>(
      context: context,
      builder: (popup) => SheetWidth(
        maxWidth: 520,
        child: Container(
          height: 300,
          color: const Color(0xff1c1c1e),
          child: SafeArea(
            top: false,
            child: Column(
              children: [
                Align(
                  alignment: Alignment.centerRight,
                  child: CupertinoButton(
                    minimumSize: const Size(44, 44),
                    onPressed: () => Navigator.of(popup).pop(),
                    child: Text(context.l10n.done),
                  ),
                ),
                Expanded(
                  child: CupertinoTheme(
                    data: timelineTheme(context),
                    child: CupertinoDatePicker(
                      initialDateTime: _start,
                      use24hFormat: true,
                      onDateTimeChanged: (t) => setState(() => _start = t),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  double? _num(TextEditingController c) =>
      double.tryParse(c.text.trim().replaceAll(',', '.'));

  Future<void> _save() async {
    final lat = _num(_lat);
    final lon = _num(_lon);
    if ((lat == null) != (lon == null) ||
        (lat != null && (lat.abs() > 90 || lon!.abs() > 180))) {
      await showAppDialog<void>(
        context: context,
        builder: (dialog) => CupertinoAlertDialog(
          title: Text(context.l10n.checkPosition),
          content: Text(context.l10n.checkPositionBody),
          actions: [
            CupertinoDialogAction(
              onPressed: () => Navigator.of(dialog).pop(),
              child: Text(context.l10n.ok),
            ),
          ],
        ),
      );
      return;
    }
    final minutes = _num(_minutes);
    final dive = Dive(
      id: widget.dive.id,
      number: _num(_number)?.round() ?? widget.dive.number,
      start: _start,
      maxDepth: _num(_depth),
      duration: minutes == null
          ? null
          : Duration(seconds: (minutes * 60).round()),
      waterTemperature: _num(_temp),
      buddy: _buddy.text.trim(),
      notes: _notes.text.trim(),
      samples: widget.dive.samples,
      media: widget.dive.media,
    );
    await widget.controller.saveDive(
      dive,
      siteName: _site.text,
      latitude: lat,
      longitude: lon,
    );
    if (mounted) Navigator.of(context).pop();
  }

  Future<void> _delete() async {
    final confirmed = await showAppDialog<bool>(
      context: context,
      builder: (dialog) => CupertinoAlertDialog(
        title: Text(context.l10n.deleteDiveTitle),
        content: Text(context.l10n.deleteDiveBody),
        actions: [
          CupertinoDialogAction(
            onPressed: () => Navigator.of(dialog).pop(false),
            child: Text(context.l10n.cancel),
          ),
          CupertinoDialogAction(
            isDestructiveAction: true,
            onPressed: () => Navigator.of(dialog).pop(true),
            child: Text(context.l10n.delete),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await widget.controller.deleteDive(widget.dive.id);
    if (!mounted) return;
    Navigator.of(context).pop();
    widget.onDeleted?.call();
  }
}
