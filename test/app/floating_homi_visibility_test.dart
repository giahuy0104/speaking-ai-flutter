import 'package:ai_speaking_flutter_app/app/ai_speaking_app.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('HOMI floats everywhere except Home translation alone on the stack', () {
    // Before the first route is pushed nothing is shown.
    expect(showsFloatingHomi(routeCount: 0, homePage: 0), isFalse);
    expect(showsFloatingHomi(routeCount: 0, homePage: 1), isFalse);
    // Home's translation page hides it; Vocabulary shows it.
    expect(showsFloatingHomi(routeCount: 1, homePage: 0), isFalse);
    expect(showsFloatingHomi(routeCount: 1, homePage: 1), isTrue);
    // Any pushed screen (topic, lesson, settings) shows it.
    expect(showsFloatingHomi(routeCount: 2, homePage: 0), isTrue);
    expect(showsFloatingHomi(routeCount: 3, homePage: 1), isTrue);
  });
}
