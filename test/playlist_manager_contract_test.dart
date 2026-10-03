// ignore_for_file: non_constant_identifier_names

// 验证本地 playlist_manager 保留应用依赖的核心模型契约。

import 'package:flutter_test/flutter_test.dart';
import 'package:playlist_manager/playlist_manager.dart';

enum _Sort { title }

class _Item with PlaylistItemWithDate {
  final String id;

  const _Item(this.id);
}

class _Manager extends PlaylistManager<_Item, String, _Sort> {
  @override
  RegExp get cleanupFilenameRegex => RegExp(r'[^a-z]');

  @override
  String identifyBy(_Item item) => item.id;

  @override
  String get playlistsDirectory => '';

  @override
  String get playlistsArtworksDirectory => '';

  @override
  String get playlistsMetadataDirectory => '';

  @override
  String get favouritePlaylistPath => '';

  @override
  String get EMPTY_NAME => 'empty';

  @override
  String get NAME_CONTAINS_BAD_CHARACTER => 'bad';

  @override
  String get SAME_NAME_EXISTS => 'same';

  @override
  String get NAME_IS_NOT_ALLOWED => 'not allowed';

  @override
  String get PLAYLIST_NAME_FAV => 'favourites';

  @override
  String get PLAYLIST_NAME_HISTORY => 'history';

  @override
  String get PLAYLIST_NAME_MOST_PLAYED => 'most played';

  @override
  Map<String, dynamic> itemToJson(_Item item) => {'id': item.id};

  @override
  Future<Map<String, GeneralPlaylist<_Item, _Sort>>> prepareAllPlaylistsFunction() async => {};

  @override
  Future<void> prepareDefaultPlaylistsFileAsync() async {}

  @override
  Future<GeneralPlaylist<_Item, _Sort>?> prepareFavouritePlaylistFunction() async => null;
}

// 覆盖播放列表模型、序列化和收藏查询。
void main() {
  test('通用播放列表保留字段并支持 JSON 往返', () {
    final playlist = GeneralPlaylist<_Item, _Sort>(
      name: 'mix',
      tracks: const [_Item('a')],
      creationDate: 10,
      modifiedDate: 20,
      comment: 'comment',
      moods: const ['calm'],
      tags: const ['night'],
      isFav: false,
      isPinned: true,
      m3uPath: 'mix.m3u',
      sortsType: const [_Sort.title],
      sortReverse: true,
    );

    final json = playlist.toJson(
      (item) => {'id': item.id},
      (sorts) => sorts.map((sort) => sort.name).toList(),
    );
    final restored = GeneralPlaylist<_Item, _Sort>.fromJson(
      json,
      (value) => _Item(value['id'] as String),
      (value) => (value as List).map((name) => _Sort.values.byName(name as String)).toList(),
    );

    expect(restored.name, 'mix');
    expect(restored.tracks.single.id, 'a');
    expect(restored.moods, ['calm']);
    expect(restored.tags, ['night']);
    expect(restored.isPinned, isTrue);
    expect(restored.sortsType, [_Sort.title]);
    expect(restored.sortReverse, isTrue);
    expect(restored.isReadOnly, isTrue);
  });

  test('收藏列表按原始条目标识查询', () {
    final favourite = FavouritePlaylist<_Item, String, _Sort>(
      name: 'favourites',
      tracks: const [_Item('a')],
      identifyBy: (item) => item.id,
    );

    expect(favourite.isSubItemFavourite('a'), isTrue);
    expect(favourite.isSubItemFavourite('b'), isFalse);
    expect(favourite.firstItemForSubItem('a')?.item.id, 'a');
  });

  test('重复项动作提供项目当前使用的选项', () {
    expect(
      PlaylistAddDuplicateAction.valuesForAdd,
      containsAll([
        PlaylistAddDuplicateAction.justAddEverything,
        PlaylistAddDuplicateAction.addAllAndRemoveOldOnes,
        PlaylistAddDuplicateAction.addOnlyMissing,
        PlaylistAddDuplicateAction.mergeAndSortByAddedDate,
        PlaylistAddDuplicateAction.deleteAndCreateNewPlaylist,
      ]),
    );
  });

  test('管理器可新增、追加、替换和切换收藏', () async {
    final manager = _Manager();
    final playlist = await manager.addNewPlaylistRaw(
      'mix',
      tracks: const ['a'],
      convertItem: (id, dateAdded, playlistID) => _Item(id),
      actionIfAlreadyExists: () async => PlaylistAddDuplicateAction.addOnlyMissing,
    );

    expect(playlist.tracks.map((item) => item.id), ['a']);

    await manager.addTracksToPlaylistRaw(
      playlist,
      const ['b'],
      () async => PlaylistAddDuplicateAction.addOnlyMissing,
      (id, dateAdded) => _Item(id),
    );
    expect(manager.getPlaylist('mix')!.tracks.map((item) => item.id), ['a', 'b']);

    await manager.replaceTheseTracksInPlaylists(
      (item) => item.id == 'b',
      (item) => const _Item('c'),
    );
    expect(manager.getPlaylist('mix')!.tracks.map((item) => item.id), ['a', 'c']);

    expect(manager.toggleTrackFavourite(const _Item('a')), isTrue);
    expect(manager.favouritesPlaylist.isSubItemFavourite('a'), isTrue);
    expect(manager.toggleTrackFavourite(const _Item('a')), isFalse);
    expect(manager.favouritesPlaylist.isSubItemFavourite('a'), isFalse);
  });

  test('标签筛选支持嵌套路径、排除条件和颜色', () {
    final manager = _Manager();
    manager.playlistsMap.value = {
      'gym': const GeneralPlaylist<_Item, _Sort>(name: 'gym', tags: ['gym/cardio']),
      'rock': const GeneralPlaylist<_Item, _Sort>(name: 'rock', tags: ['rock']),
    };
    final filter = manager.tagsFilter;

    expect(PlaylistTagsFilter.normalizeTags([' gym / cardio ', 'gym/cardio', 'rock']), ['gym/cardio', 'rock']);
    expect(PlaylistTagsFilter.expandTags(['gym/cardio']), ['gym', 'gym/cardio']);

    filter.toggleIncluded(const PlaylistUserTag('gym'));
    expect(filter.apply(['gym', 'rock']), ['gym']);

    filter.toggleExcluded(const PlaylistUserTag('gym/cardio'));
    expect(filter.apply(['gym', 'rock']), isEmpty);

    filter.setColor('gym', 0xFF112233);
    expect(filter.colorOf('gym'), 0xFF112233);
    expect(filter.colorsOf(['gym/cardio']), [0xFF112233]);

    manager.renameTag('gym', 'fitness');
    expect(manager.getPlaylist('gym')!.tags, ['fitness/cardio']);

    manager.removeTag('fitness');
    expect(manager.getPlaylist('gym')!.tags, isEmpty);
  });

  test('管理器维护删除、置顶和自定义排序状态', () async {
    final manager = _Manager();
    manager.playlistsMap.value = {
      'a': const GeneralPlaylist<_Item, _Sort>(name: 'a', tracks: [_Item('1'), _Item('2')]),
      'b': const GeneralPlaylist<_Item, _Sort>(name: 'b'),
    };

    await manager.removeTracksFromPlaylist(manager.getPlaylist('a')!, [0]);
    expect(manager.getPlaylist('a')!.tracks.map((item) => item.id), ['2']);

    manager.updatePlaylistsMetadata({'a': const PlaylistMetadataEdit(isPinned: true)});
    expect(manager.getPlaylist('a')!.isPinned, isTrue);

    manager.ensureCustomOrderValid(removeNonExistent: true);
    expect(manager.getCustomIndicesOrderListRx().value, ['a', 'b']);
    manager.onPlaylistReorder(0, 2);
    expect(manager.getCustomIndicesOrderListRx().value, ['b', 'a']);
  });
}
