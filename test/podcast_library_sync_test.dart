import 'package:flutter_test/flutter_test.dart';

import 'package:namida/controller/directory_index.dart';
import 'package:namida/podcast/controller/podcast_library_sync.dart';

void main() {
  test('adds podcast download directory when existing scan folders do not cover it', () {
    final current = [DirectoryIndexLocal('/storage/emulated/0/Music')];

    final result = ensureDirectoryCovered(
      current,
      DirectoryIndexLocal('/storage/emulated/0/Namida/Podcast Downloads'),
    );

    expect(result.map((e) => e.sourceRaw), [
      '/storage/emulated/0/Music',
      '/storage/emulated/0/Namida/Podcast Downloads',
    ]);
  });

  test('does not duplicate a directory already covered by a parent scan folder', () {
    final current = [DirectoryIndexLocal('/storage/emulated/0/Namida')];

    final result = ensureDirectoryCovered(
      current,
      DirectoryIndexLocal('/storage/emulated/0/Namida/Podcast Downloads'),
    );

    expect(result, hasLength(1));
    expect(result.single.sourceRaw, '/storage/emulated/0/Namida');
  });
}