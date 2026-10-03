import 'package:flutter_test/flutter_test.dart';

import 'package:namida/core/enums.dart';

void main() {
  test('maps the legacy YouTube library tab to podcasts', () {
    expect(decodeLibraryTabName('youtube'), LibraryTab.podcasts);
  });

  test('keeps podcast as the only replacement for duplicate legacy entries', () {
    final decoded = ['home', 'youtube', 'podcasts', 'tracks']
        .map(decodeLibraryTabName)
        .whereType<LibraryTab>()
        .toSet()
        .toList();

    expect(decoded, [LibraryTab.home, LibraryTab.podcasts, LibraryTab.tracks]);
  });

  test('ignores unknown legacy tabs', () {
    expect(decodeLibraryTabName('removed-tab'), isNull);
  });
}
