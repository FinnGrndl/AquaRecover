import 'package:flutter/cupertino.dart';

class SettingSlider extends StatelessWidget {
  const SettingSlider({
    super.key,
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
    this.divisions,
    this.help,
    this.format,
    this.showHeader = true,
  });
  final String label;
  final double value;
  final double min;
  final double max;
  final int? divisions;
  final String? help;
  final ValueChanged<double>? onChanged;
  final String Function(double value)? format;
  final bool showHeader;

  @override
  Widget build(BuildContext context) {
    final valueText = format?.call(value) ?? value.toStringAsFixed(2);
    final secondary = CupertinoDynamicColor.resolve(
      CupertinoColors.secondaryLabel,
      context,
    );
    return Padding(
      padding: EdgeInsets.only(top: showHeader ? 8 : 4, bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (showHeader) ...[
            Row(
              children: [
                Expanded(
                  child: Text(
                    label,
                    style: CupertinoTheme.of(
                      context,
                    ).textTheme.textStyle.copyWith(fontWeight: FontWeight.w600),
                  ),
                ),
                Text(
                  valueText,
                  style: CupertinoTheme.of(
                    context,
                  ).textTheme.textStyle.copyWith(color: secondary),
                ),
              ],
            ),
            const SizedBox(height: 4),
          ],
          SizedBox(
            width: double.infinity,
            child: CupertinoSlider(
              value: value.clamp(min, max).toDouble(),
              min: min,
              max: max,
              divisions: divisions,
              onChanged: onChanged,
            ),
          ),
          if (help != null)
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: 1),
                  child: Icon(
                    CupertinoIcons.info_circle,
                    size: 14,
                    color: secondary,
                  ),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    help!,
                    style: CupertinoTheme.of(context).textTheme.textStyle
                        .copyWith(fontSize: 12, color: secondary),
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }
}
