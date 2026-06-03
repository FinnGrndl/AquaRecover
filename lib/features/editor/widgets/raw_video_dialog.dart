import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';

import '../../../core/models/raw_video_descriptor.dart';

class RawVideoDialog extends StatefulWidget {
  const RawVideoDialog({super.key, required this.initial});
  final RawVideoDescriptor initial;
  static Future<RawVideoDescriptor?> show(BuildContext context, {required RawVideoDescriptor initial}) => showCupertinoDialog<RawVideoDescriptor>(context: context, builder: (_) => RawVideoDialog(initial: initial));
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
    return CupertinoAlertDialog(
      title: const Text('RAW video settings'),
      content: Padding(
        padding: const EdgeInsets.only(top: 12),
        child: Column(children: [
          _field('Width', _width),
          _field('Height', _height),
          _field('Frame rate', _fps, decimal: true),
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            alignment: WrapAlignment.center,
            children: [
              for (final format in RawVideoDescriptor.commonPixelFormats)
                CupertinoButton(
                  minimumSize: Size.zero,
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                  color: _pixelFormat == format ? CupertinoTheme.of(context).primaryColor.withValues(alpha: 0.16) : CupertinoColors.systemGrey5,
                  borderRadius: BorderRadius.circular(99),
                  onPressed: () => setState(() => _pixelFormat = format),
                  child: Text(format, style: const TextStyle(fontSize: 11)),
                ),
            ],
          ),
          if (_error != null) Padding(padding: const EdgeInsets.only(top: 8), child: Text(_error!, style: const TextStyle(color: CupertinoColors.destructiveRed, fontSize: 12))),
        ]),
      ),
      actions: [
        CupertinoDialogAction(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancel')),
        CupertinoDialogAction(isDefaultAction: true, onPressed: _submit, child: const Text('Continue')),
      ],
    );
  }
  Widget _field(String label, TextEditingController controller, {bool decimal = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: CupertinoTextField(
        controller: controller,
        placeholder: label,
        keyboardType: decimal ? const TextInputType.numberWithOptions(decimal: true) : TextInputType.number,
        inputFormatters: [FilteringTextInputFormatter.allow(decimal ? RegExp(r'[0-9.]') : RegExp(r'[0-9]'))],
        prefix: Padding(padding: const EdgeInsets.only(left: 8), child: Text('$label: ')),
      ),
    );
  }
  void _submit() {
    try {
      final descriptor = RawVideoDescriptor(width: int.parse(_width.text.trim()), height: int.parse(_height.text.trim()), frameRate: double.parse(_fps.text.trim()), pixelFormat: _pixelFormat);
      descriptor.validateForProcessing();
      Navigator.of(context).pop(descriptor);
    } on Object catch (error) {
      setState(() => _error = error.toString().replaceAll(RegExp(r'[\r\n]+'), ' '));
    }
  }
}
