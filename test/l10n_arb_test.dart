import 'dart:convert';
import 'dart:io';

import 'package:aqua_recover/l10n/app_localizations.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

/// Every language has every string of the English template, with the same
/// placeholders, so no screen falls back to English or drops a value.
void main() {
  final template = _arb('app_en.arb');
  final languages = Directory('lib/l10n')
      .listSync()
      .map((entry) => entry.uri.pathSegments.last)
      .where((name) => name.startsWith('app_') && name.endsWith('.arb'))
      .toList();

  test('the app ships English and German', () {
    expect(languages, containsAll(['app_en.arb', 'app_de.arb']));
    expect(
      AppLocalizations.supportedLocales,
      containsAll([const Locale('en'), const Locale('de')]),
    );
  });

  for (final file in languages.where((name) => name != 'app_en.arb')) {
    group(file, () {
      final arb = _arb(file);

      test('has exactly the template keys', () {
        expect(
          _messageKeys(arb).toSet().difference(_messageKeys(template).toSet()),
          isEmpty,
          reason: 'keys missing from app_en.arb',
        );
        expect(
          _messageKeys(template).toSet().difference(_messageKeys(arb).toSet()),
          isEmpty,
          reason: 'untranslated keys',
        );
      });

      test('uses the same placeholders as the template', () {
        for (final key in _messageKeys(template)) {
          final english = _placeholders(template[key] as String);
          final translated = _placeholders(arb[key] as String? ?? '');
          expect(translated, english, reason: key);
          final declared =
              ((template['@$key'] as Map?)?['placeholders'] as Map?)?.keys
                  .toSet() ??
              <Object?>{};
          expect(declared, english, reason: '@$key placeholders');
        }
      });

      test('keeps plural forms complete', () {
        for (final key in _messageKeys(template)) {
          final english = template[key] as String;
          if (!english.contains(', plural,')) continue;
          final translated = arb[key] as String;
          expect(translated, contains(', plural,'), reason: key);
          expect(translated, contains('other{'), reason: key);
        }
      });
    });
  }
}

Map<String, Object?> _arb(String name) =>
    (jsonDecode(File('lib/l10n/$name').readAsStringSync()) as Map)
        .cast<String, Object?>();

Iterable<String> _messageKeys(Map<String, Object?> arb) =>
    arb.keys.where((key) => !key.startsWith('@'));

/// The argument names in an ICU message, plural and select branches
/// included, without the branch selectors and branch text themselves.
Set<String> _placeholders(String message) {
  final names = <String>{};
  // Quoted text is literal in ICU messages.
  final text = message.replaceAll(RegExp(r"'[^']*'"), '');
  var i = 0;

  late void Function() argument;
  // Plain text with arguments, up to the closing brace of a branch.
  void body() {
    while (i < text.length && text[i] != '}') {
      if (text[i] == '{') {
        i++;
        argument();
      }
      i++;
    }
  }

  argument = () {
    final head = RegExp(
      r'\s*(\w+)\s*(?:,\s*(\w+)\s*(,)?)?\s*',
    ).matchAsPrefix(text, i)!;
    names.add(head[1]!);
    i = head.end;
    if (head[3] != null) {
      // selector{body} pairs until the argument's closing brace.
      while (text[i] != '}') {
        final selector = RegExp(r'\s*=?\w+\s*\{').matchAsPrefix(text, i);
        if (selector == null) {
          i++;
          continue;
        }
        i = selector.end;
        body();
        i++;
        while (i < text.length && text[i] == ' ') {
          i++;
        }
      }
    }
  };

  body();
  return names;
}
