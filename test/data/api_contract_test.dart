import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('application source imports data layer only through public barrel', () {
    final violations = <String>[];
    for (final entity
        in Directory('lib')
            .listSync(recursive: true)
            .whereType<File>()
            .where(
              (f) => f.path.endsWith('.dart') && !f.path.contains('/lib/data/'),
            )) {
      final source = entity.readAsStringSync();
      if (source.contains("package:assetra/data/src/") ||
          source.contains("package:assetra/data/models/") ||
          source.contains("package:assetra/data/portfolio_data_api.dart")) {
        violations.add(entity.path);
      }
    }
    expect(
      violations,
      isEmpty,
      reason: 'Other layers must import package:assetra/data/data.dart only',
    );
  });

  test('every public data API function documents its input and output', () {
    final source = File('lib/data/portfolio_data_api.dart').readAsStringSync();
    final publicFunctions = RegExp(
      r'^  (?:static )?Future<[^\n]+> [a-zA-Z]',
      multiLine: true,
    ).allMatches(source);

    for (final function in publicFunctions) {
      final preceding = source.substring(0, function.start).trimRight();
      final lines = preceding.split('\n');
      final documentation = <String>[];
      for (var index = lines.length - 1; index >= 0; index--) {
        final line = lines[index].trimLeft();
        if (!line.startsWith('///')) break;
        documentation.insert(0, line);
      }
      final text = documentation.join('\n');
      expect(
        text,
        allOf(
          contains('Parameters\n/// ----------'),
          contains('Returns\n/// -------'),
          contains('Raises\n/// ------'),
        ),
        reason: 'Public API function at offset ${function.start} needs Dartdoc',
      );
    }
  });
}
