import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';

import '../../../core/models/raw_video_descriptor.dart';
import '../../../l10n/l10n.dart';
import '../../../shared/widgets/app_dialog.dart';

class RawVideoDialog extends StatefulWidget {
  const RawVideoDialog({super.key, required this.initial});
  final RawVideoDescriptor initial;
  static Future<RawVideoDescriptor?> show(
    BuildContext context, {
    required RawVideoDescriptor initial,
  }) => showAppDialog<RawVideoDescriptor>(
    context: context,
    builder: (_) => RawVideoDialog(initial: initial),
  );
  @override
  State<RawVideoDialog> createState() => _RawVideoDialogState();
}

class _RawVideoDialogState extends State<RawVideoDialog> {
  late final TextEditingController _width;
  late final TextEditingController _height;
  late final TextEditingController _fps;
  late String _pixelFormat;
  String? _error;
  @override
  void initState() {
    super.initState();
    _width = TextEditingController(text: widget.initial.width.toString());
    _height = TextEditingController(text: widget.initial.height.toString());
    _fps = TextEditingController(text: widget.initial.frameRate.toString());
    _pixelFormat = widget.initial.pixelFormat;
  }

  @override
  void dispose() {
    _width.dispose();
    _height.dispose();
    _fps.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return CupertinoAlertDialog(
      title: Text(l10n.rawVideoSettings),
      content: Padding(
        padding: const EdgeInsets.only(top: 12),
        child: Column(
          children: [
            _field(l10n.width, _width),
            _field(l10n.height, _height),
            _field(l10n.frameRate, _fps, decimal: true),
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              alignment: WrapAlignment.center,
              children: [
                for (final format in RawVideoDescriptor.commonPixelFormats)
                  // A 44 pt touch target around the small chip.
                  CupertinoButton(
                    minimumSize: const Size(
                      kMinInteractiveDimensionCupertino,
                      kMinInteractiveDimensionCupertino,
                    ),
                    padding: EdgeInsets.zero,
                    onPressed: () => setState(() => _pixelFormat = format),
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: _pixelFormat == format
                            ? CupertinoTheme.of(
                                context,
                              ).primaryColor.withValues(alpha: 0.16)
                            : CupertinoColors.systemGrey5.resolveFrom(context),
                        borderRadius: BorderRadius.circular(99),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 6,
                        ),
                        child: Text(
                          format,
                          style: const TextStyle(fontSize: 11),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  _error!,
                  style: const TextStyle(
                    color: CupertinoColors.destructiveRed,
                    fontSize: 12,
                  ),
                ),
              ),
          ],
        ),
      ),
      actions: [
        CupertinoDialogAction(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.cancel),
        ),
        CupertinoDialogAction(
          isDefaultAction: true,
          onPressed: _submit,
          child: Text(l10n.continueAction),
        ),
      ],
    );
  }

  Widget _field(
    String label,
    TextEditingController controller, {
    bool decimal = false,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: CupertinoTextField(
        controller: controller,
        placeholder: label,
        keyboardType: decimal
            ? const TextInputType.numberWithOptions(decimal: true)
            : TextInputType.number,
        inputFormatters: [
          FilteringTextInputFormatter.allow(
            decimal ? RegExp(r'[0-9.]') : RegExp(r'[0-9]'),
          ),
        ],
        prefix: Padding(
          padding: const EdgeInsets.only(left: 8),
          child: Text('$label: '),
        ),
      ),
    );
  }

  void _submit() {
    final l10n = context.l10n;
    final width = int.tryParse(_width.text.trim());
    final height = int.tryParse(_height.text.trim());
    final frameRate = double.tryParse(_fps.text.trim());
    if (width == null || height == null || frameRate == null) {
      setState(() => _error = l10n.rawVideoNumbersRequired);
      return;
    }
    // The same limits as validateForProcessing, in the app language.
    final message = switch ((width, height, frameRate)) {
      _
          when width < RawVideoDescriptor.minDimension ||
              height < RawVideoDescriptor.minDimension =>
        l10n.rawVideoTooSmall,
      _
          when width > RawVideoDescriptor.maxDimension ||
              height > RawVideoDescriptor.maxDimension =>
        l10n.rawVideoTooLarge(RawVideoDescriptor.maxDimension),
      _ when width * height > RawVideoDescriptor.maxPixels =>
        l10n.rawVideoTooManyPixels(RawVideoDescriptor.maxPixels),
      _
          when !frameRate.isFinite ||
              frameRate < RawVideoDescriptor.minFrameRate ||
              frameRate > RawVideoDescriptor.maxFrameRate =>
        l10n.rawVideoFrameRateRange(
          l10n.decimal(RawVideoDescriptor.minFrameRate, digits: 0),
          l10n.decimal(RawVideoDescriptor.maxFrameRate, digits: 0),
        ),
      _ => null,
    };
    if (message != null) {
      setState(() => _error = message);
      return;
    }
    try {
      final descriptor = RawVideoDescriptor(
        width: width,
        height: height,
        frameRate: frameRate,
        pixelFormat: _pixelFormat,
      );
      descriptor.validateForProcessing();
      Navigator.of(context).pop(descriptor);
    } on Object catch (error) {
      setState(
        () => _error = error.toString().replaceAll(RegExp(r'[\r\n]+'), ' '),
      );
    }
  }
}
