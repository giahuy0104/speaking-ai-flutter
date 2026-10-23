import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../tool/check_architecture_boundaries.dart' as architecture;

void main() {
  test('feature and audio boundaries remain isolated', () {
    final violations = architecture.checkArchitectureBoundaries(
      Directory.current,
    );

    expect(
      violations,
      isEmpty,
      reason: violations.map((violation) => violation.toString()).join('\n'),
    );
  });

  test('migrated Settings layers retain platform and dependency boundaries', () {
    final root = Directory.systemTemp.createTempSync('settings-boundaries-');
    addTearDown(() => root.deleteSync(recursive: true));
    Directory('${root.path}/lib/features').createSync(recursive: true);
    final sources = {
      'lib/presentation/settings/screen/invalid.dart':
          "import '../../../features/conversation/presentation/conversation_controller.dart';\nfinal channel = MethodChannel('test');",
      'lib/data/settings/invalid.dart':
          "import '../../presentation/settings/bloc/settings_bloc.dart';",
      'lib/domain/settings/invalid.dart':
          "import '../../presentation/settings/bloc/settings_bloc.dart';",
    };
    for (final entry in sources.entries) {
      final file = File('${root.path}/${entry.key}');
      file.parent.createSync(recursive: true);
      file.writeAsStringSync(entry.value);
    }
    final violations = architecture.checkArchitectureBoundaries(root);
    expect(violations, hasLength(4));
    expect(
      violations.where((item) => item.message.contains('platform adapter')),
      hasLength(1),
    );
    expect(
      violations.where((item) => item.message.contains('audio/session port')),
      hasLength(1),
    );
    expect(
      violations.where(
        (item) => item.message.contains('logic layer imports presentation'),
      ),
      hasLength(2),
    );
  });
}
