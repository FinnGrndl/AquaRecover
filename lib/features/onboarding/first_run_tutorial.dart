import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';

import '../../l10n/l10n.dart';
import '../../shared/reduce_motion.dart';
import '../../shared/widgets/app_tooltip.dart';

Future<void> showFirstRunTutorial(BuildContext context) {
  return showCupertinoModalPopup<void>(
    context: context,
    barrierDismissible: false,
    semanticsDismissible: false,
    barrierColor: CupertinoColors.black.withValues(alpha: .46),
    filter: ui.ImageFilter.blur(sigmaX: 5, sigmaY: 5),
    builder: (_) => const FirstRunTutorial(),
  );
}

class FirstRunTutorial extends StatefulWidget {
  const FirstRunTutorial({super.key});

  @override
  State<FirstRunTutorial> createState() => _FirstRunTutorialState();
}

class _FirstRunTutorialState extends State<FirstRunTutorial> {
  static const _pageCount = 4;

  final PageController _pageController = PageController();
  int _page = 0;
  int _batchCount = 1;
  int _selectedTool = 0;
  bool _splitPreview = false;
  bool _showingOriginal = false;
  final Set<int> _exportDestinations = {0};

  bool get _isLastPage => _page == _pageCount - 1;

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final regularWidth = media.size.width >= 600;
    final horizontalMargin = regularWidth ? 28.0 : 12.0;
    final availableHeight = math.max(
      0.0,
      media.size.height - media.padding.vertical - (regularWidth ? 56 : 20),
    );
    final sheetHeight = math.min(regularWidth ? 680.0 : 640.0, availableHeight);
    final radius = BorderRadius.circular(regularWidth ? 30 : 28);
    final highContrast = MediaQuery.highContrastOf(context);

    return SafeArea(
      minimum: EdgeInsets.symmetric(
        horizontal: horizontalMargin,
        vertical: regularWidth ? 20 : 8,
      ),
      child: Align(
        alignment: regularWidth ? Alignment.center : Alignment.bottomCenter,
        child: SizedBox(
          key: const Key('first_run_tutorial'),
          width: math.min(560, media.size.width - horizontalMargin * 2),
          height: sheetHeight,
          child: ClipRRect(
            borderRadius: radius,
            child: BackdropFilter(
              filter: ui.ImageFilter.blur(sigmaX: 28, sigmaY: 28),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: const Color(
                    0xff171a1f,
                  ).withValues(alpha: highContrast ? .99 : .94),
                  borderRadius: radius,
                  border: Border.all(
                    color: CupertinoColors.white.withValues(
                      alpha: highContrast ? .32 : .18,
                    ),
                  ),
                ),
                child: CupertinoTheme(
                  data: CupertinoTheme.of(context).copyWith(
                    brightness: Brightness.dark,
                    primaryColor: CupertinoColors.activeBlue,
                  ),
                  child: Column(
                    children: [
                      _header(context),
                      Expanded(child: _pages()),
                      _footer(context),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _header(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 10, 10, 2),
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(9),
            child: Image.asset(
              'assets/branding/aquarecover_app_icon.png',
              width: 34,
              height: 34,
              fit: BoxFit.cover,
              semanticLabel: context.l10n.appIconLabel,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              context.l10n.quickTour,
              style: const TextStyle(
                color: CupertinoColors.white,
                fontSize: 17,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          CupertinoButton(
            key: const Key('tutorial_skip'),
            minimumSize: const Size(44, 44),
            padding: const EdgeInsets.symmetric(horizontal: 10),
            onPressed: () => Navigator.of(context).pop(),
            child: Text(context.l10n.skip),
          ),
        ],
      ),
    );
  }

  Widget _pages() {
    final l10n = context.l10n;
    return PageView(
      key: const Key('tutorial_pages'),
      controller: _pageController,
      onPageChanged: (page) {
        HapticFeedback.selectionClick();
        setState(() => _page = page);
      },
      children: [
        _TutorialPage(
          key: const Key('tutorial_page_welcome'),
          icon: CupertinoIcons.wand_stars,
          title: l10n.tourWelcomeTitle,
          body: l10n.tourWelcomeBody,
          child: const _WorkflowOverview(),
        ),
        _TutorialPage(
          key: const Key('tutorial_page_import'),
          icon: CupertinoIcons.photo_on_rectangle,
          title: l10n.tourImportTitle,
          body: l10n.tourImportBody,
          child: _ImportDemo(
            count: _batchCount,
            onChanged: (count) {
              HapticFeedback.selectionClick();
              setState(() => _batchCount = count);
            },
          ),
        ),
        _TutorialPage(
          key: const Key('tutorial_page_edit'),
          icon: CupertinoIcons.slider_horizontal_3,
          title: l10n.tourEditTitle,
          body: l10n.tourEditBody,
          child: _EditorDemo(
            selectedTool: _selectedTool,
            split: _splitPreview,
            showingOriginal: _showingOriginal,
            onToolChanged: (tool) {
              HapticFeedback.selectionClick();
              setState(() => _selectedTool = tool);
            },
            onToggleSplit: () {
              HapticFeedback.selectionClick();
              setState(() => _splitPreview = !_splitPreview);
            },
            onOriginalChanged: (show) =>
                setState(() => _showingOriginal = show),
          ),
        ),
        _TutorialPage(
          key: const Key('tutorial_page_export'),
          icon: CupertinoIcons.arrow_up_square,
          title: l10n.tourExportTitle,
          body: l10n.tourExportBody,
          child: _ExportDemo(
            selected: _exportDestinations,
            onToggle: _toggleExportDestination,
          ),
        ),
      ],
    );
  }

  Widget _footer(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 0, 18, 12),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _TutorialPageControl(
            key: const Key('tutorial_page_control'),
            count: _pageCount,
            selectedIndex: _page,
            onSelected: _goToPage,
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              if (_page > 0) ...[
                AppTooltip(
                  message: context.l10n.previousPage,
                  child: Semantics(
                    button: true,
                    label: context.l10n.previousPage,
                    excludeSemantics: true,
                    child: CupertinoButton(
                      key: const Key('tutorial_back'),
                      minimumSize: const Size(48, 48),
                      padding: EdgeInsets.zero,
                      color: CupertinoColors.white.withValues(alpha: .10),
                      borderRadius: BorderRadius.circular(15),
                      onPressed: () => _goToPage(_page - 1),
                      child: const Icon(CupertinoIcons.chevron_back),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
              ],
              Expanded(
                child: CupertinoButton.filled(
                  key: const Key('tutorial_next'),
                  minimumSize: const Size.fromHeight(48),
                  borderRadius: BorderRadius.circular(15),
                  onPressed: _isLastPage
                      ? () => Navigator.of(context).pop()
                      : () => _goToPage(_page + 1),
                  child: Text(
                    _isLastPage ? context.l10n.startEditing : context.l10n.next,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  void _goToPage(int page) {
    if (reduceMotionOf(context)) {
      _pageController.jumpToPage(page);
    } else {
      _pageController.animateToPage(
        page,
        duration: const Duration(milliseconds: 280),
        curve: Curves.easeOutCubic,
      );
    }
  }

  void _toggleExportDestination(int destination) {
    HapticFeedback.selectionClick();
    setState(() {
      if (_exportDestinations.contains(destination)) {
        if (_exportDestinations.length > 1) {
          _exportDestinations.remove(destination);
        }
      } else {
        _exportDestinations.add(destination);
      }
    });
  }
}

class _TutorialPage extends StatelessWidget {
  const _TutorialPage({
    super.key,
    required this.icon,
    required this.title,
    required this.body,
    required this.child,
  });

  final IconData icon;
  final String title;
  final String body;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      label: title,
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(24, 14, 24, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Align(
              child: Container(
                width: 68,
                height: 68,
                decoration: BoxDecoration(
                  color: CupertinoColors.activeBlue.withValues(alpha: .16),
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: CupertinoColors.activeBlue.withValues(alpha: .34),
                  ),
                ),
                child: Icon(icon, size: 31, color: CupertinoColors.activeBlue),
              ),
            ),
            const SizedBox(height: 18),
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: CupertinoColors.white,
                fontSize: 28,
                height: 1.12,
                fontWeight: FontWeight.w700,
                letterSpacing: -.55,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              body,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: CupertinoColors.white.withValues(alpha: .68),
                fontSize: 15,
                height: 1.38,
              ),
            ),
            const SizedBox(height: 22),
            child,
          ],
        ),
      ),
    );
  }
}

class _TutorialPageControl extends StatelessWidget {
  const _TutorialPageControl({
    super.key,
    required this.count,
    required this.selectedIndex,
    required this.onSelected,
  });

  final int count;
  final int selectedIndex;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        for (var index = 0; index < count; index++)
          Semantics(
            button: true,
            selected: index == selectedIndex,
            label: context.l10n.tutorialPageOf(index + 1, count),
            child: CupertinoButton(
              minimumSize: const Size(44, 44),
              padding: EdgeInsets.zero,
              onPressed: () => onSelected(index),
              child: AnimatedContainer(
                duration: motionDuration(
                  context,
                  const Duration(milliseconds: 180),
                ),
                width: index == selectedIndex ? 18 : 7,
                height: 7,
                margin: const EdgeInsets.symmetric(horizontal: 2),
                decoration: BoxDecoration(
                  color: index == selectedIndex
                      ? CupertinoColors.white
                      : CupertinoColors.white.withValues(alpha: .30),
                  borderRadius: BorderRadius.circular(99),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _WorkflowOverview extends StatelessWidget {
  const _WorkflowOverview();

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: _WorkflowStep(
                icon: CupertinoIcons.photo_on_rectangle,
                label: l10n.workflowImport,
              ),
            ),
            const _WorkflowArrow(),
            Expanded(
              child: _WorkflowStep(
                icon: CupertinoIcons.slider_horizontal_3,
                label: l10n.workflowEdit,
              ),
            ),
            const _WorkflowArrow(),
            Expanded(
              child: _WorkflowStep(
                icon: CupertinoIcons.arrow_up_square,
                label: l10n.workflowExport,
              ),
            ),
          ],
        ),
        const SizedBox(height: 18),
        _Callout(icon: CupertinoIcons.lock_shield, text: l10n.onDevicePrivacy),
      ],
    );
  }
}

class _WorkflowStep extends StatelessWidget {
  const _WorkflowStep({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Icon(icon, color: CupertinoColors.white, size: 25),
        const SizedBox(height: 8),
        Text(
          label,
          style: const TextStyle(
            color: CupertinoColors.white,
            fontSize: 13,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}

class _WorkflowArrow extends StatelessWidget {
  const _WorkflowArrow();

  @override
  Widget build(BuildContext context) => Icon(
    CupertinoIcons.chevron_forward,
    size: 15,
    color: CupertinoColors.white.withValues(alpha: .34),
  );
}

class _ImportDemo extends StatelessWidget {
  const _ImportDemo({required this.count, required this.onChanged});

  final int count;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return _DemoSurface(
      child: Column(
        children: [
          SizedBox(
            width: double.infinity,
            child: CupertinoSlidingSegmentedControl<int>(
              key: const Key('tutorial_batch_picker'),
              groupValue: count,
              backgroundColor: const Color(0x1fffffff),
              thumbColor: const Color(0x8a0a84ff),
              children: {
                1: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  child: Text(
                    context.l10n.onePhoto,
                    style: const TextStyle(color: CupertinoColors.white),
                  ),
                ),
                3: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  child: Text(
                    context.l10n.batch,
                    style: const TextStyle(color: CupertinoColors.white),
                  ),
                ),
              },
              onValueChanged: (value) {
                if (value != null) onChanged(value);
              },
            ),
          ),
          const SizedBox(height: 18),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: List.generate(
              count,
              (index) => Container(
                key: Key('tutorial_queue_item_$index'),
                width: 54,
                height: 62,
                margin: const EdgeInsets.symmetric(horizontal: 4),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: index.isEven
                        ? const [Color(0xff0b7893), Color(0xff083b64)]
                        : const [Color(0xff185f78), Color(0xff154856)],
                  ),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: CupertinoColors.white.withValues(alpha: .18),
                  ),
                ),
                child: const Icon(
                  CupertinoIcons.photo,
                  color: CupertinoColors.white,
                  size: 23,
                ),
              ),
            ),
          ),
          const SizedBox(height: 14),
          AnimatedSwitcher(
            duration: motionDuration(
              context,
              const Duration(milliseconds: 180),
            ),
            child: Text(
              count == 1
                  ? context.l10n.tourOnePhotoHint
                  : context.l10n.tourBatchHint,
              key: ValueKey(count),
              textAlign: TextAlign.center,
              style: TextStyle(
                color: CupertinoColors.white.withValues(alpha: .72),
                fontSize: 13,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _EditorDemo extends StatelessWidget {
  const _EditorDemo({
    required this.selectedTool,
    required this.split,
    required this.showingOriginal,
    required this.onToolChanged,
    required this.onToggleSplit,
    required this.onOriginalChanged,
  });

  static List<(IconData, String, String)> _toolsIn(AppLocalizations l10n) => [
    (CupertinoIcons.rectangle_grid_2x2, l10n.toolPresets, l10n.tourPresetsHint),
    (CupertinoIcons.slider_horizontal_3, l10n.toolAdjust, l10n.tourAdjustHint),
    (CupertinoIcons.crop_rotate, l10n.toolCrop, l10n.tourCropHint),
    (CupertinoIcons.sparkles, l10n.toolLut, l10n.tourLutHint),
  ];

  final int selectedTool;
  final bool split;
  final bool showingOriginal;
  final ValueChanged<int> onToolChanged;
  final VoidCallback onToggleSplit;
  final ValueChanged<bool> onOriginalChanged;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final tools = _toolsIn(l10n);
    final active = tools[selectedTool];
    return Column(
      children: [
        _DemoSurface(
          padding: EdgeInsets.zero,
          child: GestureDetector(
            key: const Key('tutorial_compare_demo'),
            behavior: HitTestBehavior.opaque,
            onLongPressStart: (_) => onOriginalChanged(true),
            onLongPressEnd: (_) => onOriginalChanged(false),
            child: SizedBox(
              height: 126,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(17),
                    child: Row(
                      children: [
                        if (split) ...[
                          const Expanded(child: _DemoImage(original: true)),
                          Container(
                            width: 1,
                            color: CupertinoColors.white.withValues(alpha: .75),
                          ),
                        ],
                        Expanded(child: _DemoImage(original: showingOriginal)),
                      ],
                    ),
                  ),
                  Positioned(
                    top: 8,
                    right: 8,
                    // Hover only: touch and hold here is the demo's
                    // hold-to-compare gesture.
                    child: AppTooltip(
                      trigger: AppTooltipTrigger.hoverOnly,
                      message: split
                          ? l10n.showEditedPreview
                          : l10n.showSplitPreview,
                      child: Semantics(
                        button: true,
                        selected: split,
                        label: split
                            ? l10n.showEditedPreview
                            : l10n.showSplitPreview,
                        child: CupertinoButton(
                          key: const Key('tutorial_compare_toggle'),
                          minimumSize: const Size(44, 44),
                          padding: EdgeInsets.zero,
                          color: const Color(0xff161a20).withValues(alpha: .82),
                          borderRadius: BorderRadius.circular(22),
                          onPressed: onToggleSplit,
                          child: Icon(
                            split
                                ? CupertinoIcons.photo
                                : CupertinoIcons.square_split_2x1,
                            size: 19,
                          ),
                        ),
                      ),
                    ),
                  ),
                  Positioned(
                    left: 10,
                    bottom: 8,
                    child: _DemoLabel(
                      label: showingOriginal
                          ? l10n.original
                          : split
                          ? l10n.originalSlashEdited
                          : l10n.compareEdited,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            for (var index = 0; index < tools.length; index++) ...[
              if (index > 0) const SizedBox(width: 6),
              Expanded(
                child: _DemoToolButton(
                  index: index,
                  icon: tools[index].$1,
                  label: tools[index].$2,
                  selected: index == selectedTool,
                  onPressed: () => onToolChanged(index),
                ),
              ),
            ],
          ],
        ),
        const SizedBox(height: 10),
        Text(
          '${active.$2}: ${active.$3}',
          key: const Key('tutorial_tool_description'),
          textAlign: TextAlign.center,
          style: TextStyle(
            color: CupertinoColors.white.withValues(alpha: .68),
            fontSize: 13,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          l10n.tourCompareHint,
          textAlign: TextAlign.center,
          style: TextStyle(
            color: CupertinoColors.systemGrey.resolveFrom(context),
            fontSize: 12,
          ),
        ),
      ],
    );
  }
}

class _DemoImage extends StatelessWidget {
  const _DemoImage({required this.original});

  final bool original;

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      key: Key(
        original ? 'tutorial_original_preview' : 'tutorial_edited_preview',
      ),
      duration: motionDuration(context, const Duration(milliseconds: 180)),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: original
              ? const [Color(0xff274b5d), Color(0xff1e3647), Color(0xff5b5360)]
              : const [Color(0xff0788a0), Color(0xff0b547f), Color(0xff8d6348)],
        ),
      ),
      child: Center(
        child: Icon(
          CupertinoIcons.photo,
          size: 38,
          color: CupertinoColors.white.withValues(alpha: original ? .46 : .82),
        ),
      ),
    );
  }
}

class _DemoLabel extends StatelessWidget {
  const _DemoLabel({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: CupertinoColors.black.withValues(alpha: .58),
        borderRadius: BorderRadius.circular(99),
      ),
      child: Text(
        label,
        style: const TextStyle(
          color: CupertinoColors.white,
          fontSize: 11,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class _DemoToolButton extends StatelessWidget {
  const _DemoToolButton({
    required this.index,
    required this.icon,
    required this.label,
    required this.selected,
    required this.onPressed,
  });

  final int index;
  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: selected,
      label: context.l10n.editorToolNamed(label),
      child: CupertinoButton(
        key: Key('tutorial_tool_$index'),
        minimumSize: const Size(44, 54),
        padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 7),
        color: selected
            ? CupertinoColors.activeBlue.withValues(alpha: .28)
            : CupertinoColors.white.withValues(alpha: .07),
        borderRadius: BorderRadius.circular(13),
        onPressed: onPressed,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 18),
            const SizedBox(height: 4),
            Text(
              label,
              maxLines: 1,
              style: const TextStyle(
                color: CupertinoColors.white,
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ExportDemo extends StatelessWidget {
  const _ExportDemo({required this.selected, required this.onToggle});

  final Set<int> selected;
  final ValueChanged<int> onToggle;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final destinations = [
      (CupertinoIcons.photo_on_rectangle, l10n.destinationPhotos),
      (CupertinoIcons.tray, 'AquaRecover'),
      (CupertinoIcons.folder, l10n.destinationFiles),
    ];
    return Column(
      children: [
        Row(
          children: [
            for (var index = 0; index < destinations.length; index++) ...[
              if (index > 0) const SizedBox(width: 8),
              Expanded(
                child: Semantics(
                  button: true,
                  selected: selected.contains(index),
                  label: l10n.exportDestinationNamed(destinations[index].$2),
                  child: CupertinoButton(
                    key: Key('tutorial_export_destination_$index'),
                    minimumSize: const Size(44, 92),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 4,
                      vertical: 12,
                    ),
                    color: selected.contains(index)
                        ? CupertinoColors.activeBlue.withValues(alpha: .30)
                        : CupertinoColors.white.withValues(alpha: .07),
                    borderRadius: BorderRadius.circular(16),
                    onPressed: () => onToggle(index),
                    child: Column(
                      children: [
                        Icon(destinations[index].$1, size: 23),
                        const SizedBox(height: 8),
                        Text(
                          destinations[index].$2,
                          maxLines: 1,
                          style: const TextStyle(
                            color: CupertinoColors.white,
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
        const SizedBox(height: 16),
        _Callout(
          icon: CupertinoIcons.check_mark_circled_solid,
          text: l10n.tourExportCallout,
        ),
      ],
    );
  }
}

class _DemoSurface extends StatelessWidget {
  const _DemoSurface({
    required this.child,
    this.padding = const EdgeInsets.all(16),
  });

  final Widget child;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: padding,
      decoration: BoxDecoration(
        color: CupertinoColors.white.withValues(alpha: .07),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: CupertinoColors.white.withValues(alpha: .12)),
      ),
      child: child,
    );
  }
}

class _Callout extends StatelessWidget {
  const _Callout({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: CupertinoColors.activeBlue.withValues(alpha: .10),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: CupertinoColors.activeBlue, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                color: CupertinoColors.white.withValues(alpha: .76),
                fontSize: 13,
                height: 1.35,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
