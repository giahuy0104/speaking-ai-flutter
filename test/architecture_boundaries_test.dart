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

  test('a member declared twice in one Swift type is reported', () async {
    // Swift is compiled only by CI. `swiftc -parse` accepts a type that
    // declares the same member twice, so this shipped once: RunnerTests had one
    // test declared twice and the whole iOS test target stopped building.
    final root = await Directory.systemTemp.createTemp('swift-duplicate');
    addTearDown(() => root.delete(recursive: true));
    await Directory('${root.path}/lib/features').create(recursive: true);
    await Directory('${root.path}/ios/RunnerTests').create(recursive: true);
    await File('${root.path}/ios/RunnerTests/RunnerTests.swift').writeAsString(
      '''
class RunnerTests: XCTestCase {
  func testSomething() {
  }

  func testSomething() {
  }
}
''',
    );

    final violations = architecture.checkArchitectureBoundaries(root);

    expect(
      violations.map((violation) => violation.toString()).join('\n'),
      contains('declares `testSomething()` twice'),
    );
  });

  test('the same member name in two Swift types is left alone', () async {
    // AppDelegate really does declare read() in two credential stores. A check
    // that cannot tell them apart would be turned off within a week.
    final root = await Directory.systemTemp.createTemp('swift-distinct');
    addTearDown(() => root.delete(recursive: true));
    await Directory('${root.path}/lib/features').create(recursive: true);
    await Directory('${root.path}/ios/Runner').create(recursive: true);
    await File('${root.path}/ios/Runner/Stores.swift').writeAsString('''
private final class FirstStore {
  func read() -> String? {
    return nil
  }
}

private final class SecondStore {
  func read() -> String? {
    return nil
  }
}
''');

    expect(architecture.checkArchitectureBoundaries(root), isEmpty);
  });
}
