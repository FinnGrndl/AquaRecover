import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';

class AppLicensePage extends StatefulWidget {
  const AppLicensePage({super.key});

  @override
  State<AppLicensePage> createState() => _AppLicensePageState();
}

class _AppLicensePageState extends State<AppLicensePage> {
  late final Future<List<_PackageLicense>> _licenses = _loadLicenses();

  @override
  Widget build(BuildContext context) {
    return CupertinoPageScaffold(
      navigationBar: const CupertinoNavigationBar(
        middle: Text('Open-source licenses'),
      ),
      child: SafeArea(
        child: FutureBuilder<List<_PackageLicense>>(
          future: _licenses,
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              return Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(
                    'The license list could not be loaded.',
                    style: CupertinoTheme.of(context).textTheme.textStyle,
                  ),
                ),
              );
            }
            final licenses = snapshot.data;
            if (licenses == null) {
              return const Center(child: CupertinoActivityIndicator());
            }
            return ListView.separated(
              padding: const EdgeInsets.fromLTRB(16, 20, 16, 32),
              itemCount: licenses.length + 1,
              separatorBuilder: (_, _) => const SizedBox(height: 8),
              itemBuilder: (context, index) {
                if (index == 0) {
                  return Padding(
                    padding: const EdgeInsets.fromLTRB(4, 0, 4, 12),
                    child: Text(
                      'AquaRecover 1.0.0 includes the following software. '
                      'Select a component to read its license text.',
                      style: CupertinoTheme.of(context).textTheme.textStyle
                          .copyWith(
                            color: CupertinoDynamicColor.resolve(
                              CupertinoColors.secondaryLabel,
                              context,
                            ),
                          ),
                    ),
                  );
                }
                final item = licenses[index - 1];
                return DecoratedBox(
                  decoration: BoxDecoration(
                    color: CupertinoDynamicColor.resolve(
                      CupertinoColors.secondarySystemGroupedBackground,
                      context,
                    ),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: CupertinoButton(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 14,
                    ),
                    onPressed: () => Navigator.of(context).push(
                      CupertinoPageRoute<void>(
                        builder: (_) => _LicenseDetailPage(license: item),
                      ),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            item.package,
                            style: CupertinoTheme.of(
                              context,
                            ).textTheme.textStyle,
                          ),
                        ),
                        Text(
                          '${item.texts.length}',
                          style: CupertinoTheme.of(context).textTheme.textStyle
                              .copyWith(
                                color: CupertinoDynamicColor.resolve(
                                  CupertinoColors.secondaryLabel,
                                  context,
                                ),
                              ),
                        ),
                        const SizedBox(width: 8),
                        const Icon(CupertinoIcons.chevron_forward, size: 17),
                      ],
                    ),
                  ),
                );
              },
            );
          },
        ),
      ),
    );
  }

  Future<List<_PackageLicense>> _loadLicenses() async {
    final byPackage = <String, Set<String>>{};
    await for (final entry in LicenseRegistry.licenses) {
      final text = entry.paragraphs
          .map((paragraph) => paragraph.text)
          .join('\n\n')
          .trim();
      if (text.isEmpty) continue;
      final packages = entry.packages.isEmpty
          ? const ['Other']
          : entry.packages;
      for (final package in packages) {
        byPackage.putIfAbsent(package, () => <String>{}).add(text);
      }
    }
    final result = byPackage.entries
        .map(
          (entry) => _PackageLicense(
            package: entry.key,
            texts: entry.value.toList(growable: false),
          ),
        )
        .toList(growable: false);
    result.sort(
      (a, b) => a.package.toLowerCase().compareTo(b.package.toLowerCase()),
    );
    return result;
  }
}

class _LicenseDetailPage extends StatelessWidget {
  const _LicenseDetailPage({required this.license});

  final _PackageLicense license;

  @override
  Widget build(BuildContext context) {
    return CupertinoPageScaffold(
      navigationBar: CupertinoNavigationBar(middle: Text(license.package)),
      child: SafeArea(
        child: ListView.separated(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 40),
          itemCount: license.texts.length,
          separatorBuilder: (_, _) => const Padding(
            padding: EdgeInsets.symmetric(vertical: 22),
            child: DecoratedBox(
              decoration: BoxDecoration(color: CupertinoColors.separator),
              child: SizedBox(height: 1),
            ),
          ),
          itemBuilder: (context, index) => Text(
            license.texts[index],
            style: CupertinoTheme.of(
              context,
            ).textTheme.textStyle.copyWith(fontSize: 13, height: 1.35),
          ),
        ),
      ),
    );
  }
}

class _PackageLicense {
  const _PackageLicense({required this.package, required this.texts});

  final String package;
  final List<String> texts;
}
