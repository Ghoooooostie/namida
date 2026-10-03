// 为 Namida 保留 playlist_manager 的核心模型与管理器契约。

library;

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:nampack/nampack.dart';

import 'src/playlist_tags.dart';

export 'package:nampack/nampack.dart' show Rx, Rxn, RxBaseCore;
export 'src/playlist_tags.dart';

/// ---------------------------------------------------------------- Model

mixin PlaylistItemWithDate {}

class PlaylistID {
  final String id;

  const PlaylistID({required this.id});

  @override
  String toString() => id;

  @override
  bool operator ==(Object other) => other is PlaylistID && other.id == id;

  @override
  int get hashCode => id.hashCode;
}

const _unsetPlaylistValue = Object();

class GeneralPlaylist<E, S> {
  final String name;
  final List<E> tracks;
  final int creationDate;
  final int modifiedDate;
  final String? m3uPath;
  final String? comment;
  final List<String> moods;
  final List<String> tags;
  final bool isFav;
  final bool isPinned;
  final List<S>? sortsType;
  final bool sortReverse;
  final dynamic remoteSource;

  const GeneralPlaylist({
    required this.name,
    this.tracks = const [],
    this.creationDate = 0,
    this.modifiedDate = 0,
    this.m3uPath,
    this.comment = '',
    this.moods = const [],
    this.tags = const [],
    this.isFav = false,
    this.isPinned = false,
    this.sortsType,
    this.sortReverse = false,
    this.remoteSource,
  });

  bool get isReadOnly => m3uPath?.isNotEmpty == true || remoteSource != null;

  /// 返回用于列表副标题的标签和心情文本。
  String toTagsAndMoodsText() => [...tags, ...moods].where((e) => e.isNotEmpty).join(' · ');

  GeneralPlaylist<E, S> copyWith({
    String? name,
    List<E>? tracks,
    int? creationDate,
    int? modifiedDate,
    Object? m3uPath = _unsetPlaylistValue,
    String? comment,
    List<String>? moods,
    List<String>? tags,
    bool? isFav,
    bool? isPinned,
    List<S>? sortsType,
    bool? sortReverse,
    Object? remoteSource = _unsetPlaylistValue,
  }) => GeneralPlaylist<E, S>(
    name: name ?? this.name,
    tracks: tracks ?? this.tracks,
    creationDate: creationDate ?? this.creationDate,
    modifiedDate: modifiedDate ?? this.modifiedDate,
    m3uPath: identical(m3uPath, _unsetPlaylistValue) ? this.m3uPath : m3uPath as String?,
    comment: comment ?? this.comment,
    moods: moods ?? this.moods,
    tags: tags ?? this.tags,
    isFav: isFav ?? this.isFav,
    isPinned: isPinned ?? this.isPinned,
    sortsType: sortsType ?? this.sortsType,
    sortReverse: sortReverse ?? this.sortReverse,
    remoteSource: identical(remoteSource, _unsetPlaylistValue) ? this.remoteSource : remoteSource,
  );

  Map<String, dynamic> toJson(
    Map<String, dynamic> Function(E item) itemToJson,
    dynamic Function(List<S> sorts) sortToJson, {
    bool includeTracks = true,
  }) => {
    'name': name,
    if (includeTracks) 'tracks': tracks.map(itemToJson).toList(),
    'creationDate': creationDate,
    'modifiedDate': modifiedDate,
    'm3uPath': m3uPath,
    'comment': comment,
    'moods': moods,
    'tags': tags,
    'isFav': isFav,
    'isPinned': isPinned,
    if (sortsType != null) 'sortsType': sortToJson(sortsType!),
    'sortReverse': sortReverse,
  };

  factory GeneralPlaylist.fromJson(
    Map<String, dynamic> json,
    E Function(Map<String, dynamic> value) itemFromJson,
    List<S>? Function(dynamic value) sortFromJson,
  ) {
    final tracksRaw = json['tracks'];
    final sortsRaw = json['sortsType'];
    return GeneralPlaylist<E, S>(
      name: json['name'] as String? ?? '',
      tracks: tracksRaw is List ? tracksRaw.whereType<Map>().map((value) => itemFromJson(value.cast<String, dynamic>())).toList() : <E>[],
      creationDate: json['creationDate'] as int? ?? 0,
      modifiedDate: json['modifiedDate'] as int? ?? 0,
      m3uPath: json['m3uPath'] as String?,
      comment: json['comment'] as String? ?? '',
      moods: (json['moods'] as List?)?.whereType<String>().toList() ?? const [],
      tags: (json['tags'] as List?)?.whereType<String>().toList() ?? const [],
      isFav: json['isFav'] as bool? ?? false,
      isPinned: json['isPinned'] as bool? ?? false,
      sortsType: sortsRaw == null ? null : sortFromJson(sortsRaw),
      sortReverse: json['sortReverse'] as bool? ?? false,
    );
  }
}

class FavouriteItemMatch<E> {
  final E item;

  const FavouriteItemMatch(this.item);
}

class PlaylistMetadataEdit {
  final bool? isPinned;
  final List<String>? moods;
  final List<String>? tags;

  const PlaylistMetadataEdit({this.isPinned, this.moods, this.tags});
}

class FavouritePlaylist<E, T, S> extends GeneralPlaylist<E, S> {
  final T Function(E item)? _identifyBy;

  const FavouritePlaylist({
    required super.name,
    super.tracks,
    T Function(E item)? identifyBy,
  }) : _identifyBy = identifyBy,
       super(isFav: true);

  PlaylistID get playlistID => PlaylistID(id: name);

  // 判断收藏列表是否包含原始条目。
  bool isSubItemFavourite(T item) => tracks.any((entry) => (_identifyBy?.call(entry) ?? entry) == item);

  // 判断收藏列表是否包含完整条目。
  bool isItemFavourite(E item) => tracks.contains(item);

  // 返回匹配原始条目的收藏记录。
  FavouriteItemMatch<E>? firstItemForSubItem(T item) {
    for (final entry in tracks) {
      if ((_identifyBy?.call(entry) ?? entry) == item) return FavouriteItemMatch(entry);
    }
    return null;
  }
}

/// ---------------------------------------------------------------- Enums

enum PlaylistAddDuplicateAction {
  justAddEverything,
  addAllAndRemoveOldOnes,
  addOnlyMissing,
  mergeAndSortByAddedDate,
  deleteAndCreateNewPlaylist;

  static const valuesForAdd = values;
  static const valuesForAddExcludingAddEverything = [
    addAllAndRemoveOldOnes,
    addOnlyMissing,
    mergeAndSortByAddedDate,
    deleteAndCreateNewPlaylist,
  ];
}

enum PlaylistSortType {
  newest,
  oldest,
}

/// ---------------------------------------------------------------- Manager

abstract class PlaylistManager<E, T, S> {
  PlaylistManager();

  // ---------------- to be provided by namida

  RegExp get cleanupFilenameRegex;

  T identifyBy(E item);

  int? getMetadataEditDate(GeneralPlaylist<E, S> playlist) => null;

  String get playlistsDirectory;
  String get playlistsArtworksDirectory;
  String get playlistsMetadataDirectory;
  String get favouritePlaylistPath;

  bool get sortAfterPreparing => false;
  bool get addTracksAtBeginning => false;

  String get EMPTY_NAME;
  String get NAME_CONTAINS_BAD_CHARACTER;
  String get SAME_NAME_EXISTS;
  String get NAME_IS_NOT_ALLOWED;
  String get PLAYLIST_NAME_FAV;
  String get PLAYLIST_NAME_HISTORY;
  String get PLAYLIST_NAME_MOST_PLAYED;

  Map<String, dynamic> itemToJson(E item);

  dynamic sortToJson(List<S> items) => items.map((e) => (e as dynamic).name).toList();

  Future<Map<String, GeneralPlaylist<E, S>>> prepareAllPlaylistsFunction();

  Future<void> prepareDefaultPlaylistsFileAsync() async {}

  Future<GeneralPlaylist<E, S>?> prepareFavouritePlaylistFunction();

  Future<bool> writePlaylistToStorage(GeneralPlaylist<E, S> playlist) async => true;

  Future<void> removePlaylist(GeneralPlaylist<E, S> playlist) async {}

  Future<void> removePlaylists(List<String> names, {bool deleteM3UFiles = false}) async {}

  Future<bool> renamePlaylist(String playlistName, String newName) async => false;

  Future<bool> setArtworkForPlaylist(String playlistName, {required File? artworkFile, required Uint8List? artworkBytes}) async => false;

  bool canRemovePlaylist(GeneralPlaylist<E, S> playlist) => true;

  FutureOr<void> onPlaylistTracksChanged(GeneralPlaylist<E, S> playlist) async {}

  void onPlaylistRemovedFromMap(List<String> names) {}

  void onPlaylistItemsSort(List<S> sorts, bool reverse, List<E> items) {}

  void onTagsFilterChanged() {}

  void onReadOnlyPlaylistError() {}

  void sortPlaylists() {}

  // ---------------- state

  final RxMap<String, GeneralPlaylist<E, S>> playlistsMap = <String, GeneralPlaylist<E, S>>{}.obs;
  late final Rx<FavouritePlaylist<E, T, S>> favouritesPlaylist = FavouritePlaylist<E, T, S>(name: PLAYLIST_NAME_FAV, identifyBy: identifyBy).obs;
  final RxList<String> _customIndicesOrderList = <String>[].obs;
  late final PlaylistTagsFilter tagsFilter = PlaylistTagsFilter(
    allNames: () => playlistsMap.value.keys,
    tagsForName: (name) => playlistsMap.value[name]?.tags ?? const [],
    matchesVirtual: (name, tag) {
      final playlist = playlistsMap.value[name];
      if (playlist == null) return false;
      return switch (tag) {
        PlaylistVirtualTag.pinned => playlist.isPinned,
        PlaylistVirtualTag.untagged => playlist.tags.isEmpty,
        PlaylistVirtualTag.m3u => playlist.m3uPath?.isNotEmpty == true,
        PlaylistVirtualTag.remote => playlist.remoteSource != null,
      };
    },
    onChanged: onTagsFilterChanged,
  );
  final Rx<bool> isLoading = false.obs;

  final Rx<bool> canReorderItems = true.obs;

  bool get isPlaylistsLoaded => !isLoading.value && playlistsMap.isNotEmpty;

  GeneralPlaylist<E, S>? getPlaylist(String name) => playlistsMap.value[name];

  File getArtworkFileForPlaylist(String playlistName) {
    return File('$playlistsArtworksDirectory/$playlistName.png');
  }

  FavouritePlaylist<E, T, S> get favouritePlaylist => favouritesPlaylist.value;

  List<GeneralPlaylist<E, S>> get playlistsList => playlistsMap.value.values.toList();

  Future<void> get waitForPlaylistsLoad async {
    while (!isPlaylistsLoaded) {
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
  }

  Future<void> get waitForFavouritePlaylistLoad => waitForPlaylistsLoad;

  RxList<String> get customIndicesOrderRx => _customIndicesOrderList;

  Map<String, int> Function() get computeTagsCounts => () {
    final counts = <String, int>{};
    for (final playlist in playlistsMap.value.values) {
      for (final tag in playlist.tags) counts[tag] = (counts[tag] ?? 0) + 1;
    }
    return counts;
  };

  Map<String, int> Function() get computeMoodsCounts => () {
    final counts = <String, int>{};
    for (final playlist in playlistsMap.value.values) {
      for (final mood in playlist.moods) counts[mood] = (counts[mood] ?? 0) + 1;
    }
    return counts;
  };

  String? validatePlaylistName(String? name) {
    if (name == null || name.trim().isEmpty) return EMPTY_NAME;
    if (name.contains(RegExp(r'[\\/:*?"<>|]'))) return NAME_CONTAINS_BAD_CHARACTER;
    if (playlistsMap.value.containsKey(name)) return SAME_NAME_EXISTS;
    return null;
  }

  bool isOneOfDefaultPlaylists(String name) => name == PLAYLIST_NAME_FAV || name == PLAYLIST_NAME_HISTORY || name == PLAYLIST_NAME_MOST_PLAYED;

  // 重命名标签及其所有子路径。
  Future<void> renameTag(String oldPath, String newPath) async {
    final normalized = PlaylistTagsFilter.normalizeTags([newPath]);
    if (normalized.isEmpty) return;
    final target = normalized.single;
    for (final entry in playlistsMap.value.entries.toList()) {
      final tags = entry.value.tags
          .map((tag) => tag == oldPath || tag.startsWith('$oldPath${PlaylistTagsFilter.separator}') ? '$target${tag.substring(oldPath.length)}' : tag)
          .toList();
      final updated = entry.value.copyWith(tags: PlaylistTagsFilter.normalizeTags(tags));
      playlistsMap.value[entry.key] = updated;
      await writePlaylistToStorage(updated);
    }
    tagsFilter.renamePath(oldPath, target);
  }

  // 删除标签及其所有子路径。
  Future<void> removeTag(String path) async {
    for (final entry in playlistsMap.value.entries.toList()) {
      final tags = entry.value.tags.where((tag) => tag != path && !tag.startsWith('$path${PlaylistTagsFilter.separator}')).toList();
      final updated = entry.value.copyWith(tags: tags);
      playlistsMap.value[entry.key] = updated;
      await writePlaylistToStorage(updated);
    }
    tagsFilter.removePath(path);
  }

  // 按索引删除播放列表条目。
  Future<void> removeTracksFromPlaylist(GeneralPlaylist<E, S> playlist, Iterable<int> indexes) async {
    final tracks = [...playlist.tracks];
    final sorted = indexes.toSet().where((index) => index >= 0 && index < tracks.length).toList()..sort((a, b) => b.compareTo(a));
    for (final index in sorted) {
      tracks.removeAt(index);
    }
    final updated = playlist.copyWith(tracks: tracks, modifiedDate: DateTime.now().millisecondsSinceEpoch);
    playlistsMap.value[playlist.name] = updated;
    await writePlaylistToStorage(updated);
    await onPlaylistTracksChanged(updated);
  }

  // 批量更新播放列表元数据。
  void updatePlaylistsMetadata(Map<String, PlaylistMetadataEdit> edits) {
    for (final entry in edits.entries) {
      final playlist = playlistsMap.value[entry.key];
      if (playlist == null) continue;
      final edit = entry.value;
      final updated = playlist.copyWith(isPinned: edit.isPinned, moods: edit.moods, tags: edit.tags);
      playlistsMap.value[entry.key] = updated;
      unawaited(writePlaylistToStorage(updated));
    }
    tagsFilter.refresh();
  }

  void updatePlaylistMetadata(String name, {bool? isPinned, List<String>? moods, List<String>? tags}) {
    updatePlaylistsMetadata({name: PlaylistMetadataEdit(isPinned: isPinned, moods: moods, tags: tags)});
  }

  Future<void> insertTracksInPlaylistWithEachIndex(GeneralPlaylist<E, S> playlist, Map<E, int> tracksAndIndexes) async {
    final tracks = [...playlist.tracks];
    final entries = tracksAndIndexes.entries.toList()..sort((a, b) => a.value.compareTo(b.value));
    for (final entry in entries) {
      final index = entry.value.clamp(0, tracks.length);
      tracks.insert(index, entry.key);
    }
    await updatePropertyInPlaylist(playlist.name, tracks: tracks);
  }

  Future<void> reorderTrack(GeneralPlaylist<E, S> playlist, int oldIndex, int newIndex) async {
    final tracks = [...playlist.tracks];
    if (oldIndex < 0 || oldIndex >= tracks.length) return;
    if (newIndex > oldIndex) newIndex--;
    final item = tracks.removeAt(oldIndex);
    tracks.insert(newIndex.clamp(0, tracks.length), item);
    await updatePropertyInPlaylist(playlist.name, tracks: tracks);
  }

  Future<void> reAddPlaylist(GeneralPlaylist<E, S> playlist, int modifiedDate, {Uint8List? artworkBytes}) async {
    await importPlaylistForce(playlist.copyWith(modifiedDate: modifiedDate));
    if (artworkBytes != null) {
      await setArtworkForPlaylist(playlist.name, artworkFile: null, artworkBytes: artworkBytes);
    }
  }

  Future<void> importTracksToPlaylist(GeneralPlaylist<E, S> playlist, Iterable<E> tracks) async {
    final current = playlist.tracks.toSet();
    final merged = [...playlist.tracks, ...tracks.where(current.add)];
    await updatePropertyInPlaylist(playlist.name, tracks: merged);
  }

  // 移除失效名称并补齐自定义排序列表。
  void ensureCustomOrderValid({bool removeNonExistent = false}) {
    final names = playlistsMap.value.keys.toSet();
    final order = [..._customIndicesOrderList.value];
    if (removeNonExistent) order.removeWhere((name) => !names.contains(name));
    for (final name in names) {
      if (!order.contains(name)) order.add(name);
    }
    _customIndicesOrderList.value = order;
  }

  // 返回自定义播放列表顺序。
  RxList<String> getCustomIndicesOrderListRx() => _customIndicesOrderList;

  // 更新自定义播放列表顺序。
  void onPlaylistReorder(int oldIndex, int newIndex) {
    final order = [..._customIndicesOrderList.value];
    if (oldIndex < 0 || oldIndex >= order.length) return;
    if (newIndex > oldIndex) newIndex--;
    final item = order.removeAt(oldIndex);
    final targetIndex = newIndex.clamp(0, order.length);
    order.insert(targetIndex, item);
    _customIndicesOrderList.value = order;
  }

  // 新建播放列表并按重复策略处理同名列表。
  Future<GeneralPlaylist<E, S>> addNewPlaylistRaw(
    String name, {
    required List<T> tracks,
    required E Function(T item, int dateAdded, PlaylistID playlistID) convertItem,
    int? creationDate,
    int? modifiedDate,
    String comment = '',
    List<String> moods = const [],
    List<String> tags = const [],
    bool isPinned = false,
    String? m3uPath,
    required FutureOr<PlaylistAddDuplicateAction?> Function() actionIfAlreadyExists,
  }) async {
    final existing = playlistsMap.value[name];
    final action = existing == null ? PlaylistAddDuplicateAction.deleteAndCreateNewPlaylist : await actionIfAlreadyExists();
    if (action == null && existing != null) return existing;
    var dateAdded = DateTime.now().millisecondsSinceEpoch;
    final playlistID = PlaylistID(id: name);
    final converted = tracks.map((item) => convertItem(item, dateAdded++, playlistID)).toList();
    final resolvedTracks = existing == null ? converted : _mergeItems(existing.tracks, converted, action!);
    final now = DateTime.now().millisecondsSinceEpoch;
    final playlist = GeneralPlaylist<E, S>(
      name: name,
      tracks: resolvedTracks,
      creationDate: creationDate ?? existing?.creationDate ?? now,
      modifiedDate: modifiedDate ?? now,
      comment: comment,
      moods: moods,
      tags: tags,
      isPinned: isPinned,
      m3uPath: m3uPath,
      sortsType: existing?.sortsType,
      sortReverse: existing?.sortReverse ?? false,
      remoteSource: existing?.remoteSource,
    );
    playlistsMap.value[name] = playlist;
    await writePlaylistToStorage(playlist);
    return playlist;
  }

  // 向已有播放列表追加条目并返回新增数量。
  Future<int?> addTracksToPlaylistRaw(
    GeneralPlaylist<E, S> playlist,
    List<T> tracks,
    FutureOr<PlaylistAddDuplicateAction?> Function() duplicateAction,
    E Function(T item, int dateAdded) convertItem,
  ) async {
    final action = await duplicateAction();
    if (action == null) return null;
    var dateAdded = DateTime.now().millisecondsSinceEpoch;
    final converted = tracks.map((item) => convertItem(item, dateAdded++)).toList();
    final merged = _mergeItems(playlist.tracks, converted, action);
    final added = merged.length - playlist.tracks.length;
    final updated = playlist.copyWith(tracks: merged, modifiedDate: DateTime.now().millisecondsSinceEpoch);
    playlistsMap.value[playlist.name] = updated;
    await writePlaylistToStorage(updated);
    await onPlaylistTracksChanged(updated);
    return added < 0 ? 0 : added;
  }

  // 根据重复策略合并条目。
  List<E> _mergeItems(List<E> current, List<E> incoming, PlaylistAddDuplicateAction action) {
    if (action == PlaylistAddDuplicateAction.deleteAndCreateNewPlaylist) return [...incoming];
    if (action == PlaylistAddDuplicateAction.justAddEverything) return [...current, ...incoming];
    final incomingIds = incoming.map(identifyBy).toSet();
    if (action == PlaylistAddDuplicateAction.addAllAndRemoveOldOnes) {
      return [
        ...current.where((item) => !incomingIds.contains(identifyBy(item))),
        ...incoming,
      ];
    }
    final existingIds = current.map(identifyBy).toSet();
    final missing = incoming.where((item) => existingIds.add(identifyBy(item))).toList();
    return [...current, ...missing];
  }

  // 切换收藏条目并返回切换后的收藏状态。
  bool toggleTrackFavourite(E item) {
    final current = favouritesPlaylist.value;
    final target = identifyBy(item);
    final tracks = [...current.tracks];
    final index = tracks.indexWhere((entry) => identifyBy(entry) == target);
    final isFavourite = index < 0;
    if (isFavourite) {
      tracks.add(item);
    } else {
      tracks.removeAt(index);
    }
    favouritesPlaylist.value = FavouritePlaylist<E, T, S>(name: current.name, tracks: tracks, identifyBy: identifyBy);
    return isFavourite;
  }

  Future<void> updatePropertyInPlaylist(
    String name, {
    List<E>? tracks,
    List<T>? tracksRaw,
    E Function(T item, int dateAdded)? convertItem,
    int? creationDate,
    int? modifiedDate,
    String? comment,
    List<String>? moods,
    List<String>? tags,
    bool? isPinned,
    Object? m3uPath = _unsetPlaylistValue,
    List<S>? itemsSortType,
    bool? itemsSortReverse,
    Object? remoteSource = _unsetPlaylistValue,
    bool tracksFromNewSource = false,
  }) async {
    final pl = playlistsMap.value[name];
    if (pl == null) return;
    List<E>? convertedTracks = tracks;
    if (convertedTracks == null && tracksRaw != null && convertItem != null) {
      var dateAdded = DateTime.now().millisecondsSinceEpoch;
      convertedTracks = tracksRaw.map((item) => convertItem(item, dateAdded++)).toList();
    }
    final updated = pl.copyWith(
      tracks: convertedTracks,
      creationDate: creationDate,
      modifiedDate: modifiedDate,
      comment: comment,
      moods: moods,
      tags: tags,
      isPinned: isPinned,
      m3uPath: m3uPath,
      sortsType: itemsSortType,
      sortReverse: itemsSortReverse,
      remoteSource: remoteSource,
    );
    playlistsMap.value[name] = updated;
    await writePlaylistToStorage(updated);
  }

  Future<bool> importPlaylistForce(GeneralPlaylist<E, S> playlist, {bool sortPlaylists = true, bool tracksFromNewSource = false}) async {
    playlistsMap.value[playlist.name] = playlist;
    final written = await writePlaylistToStorage(playlist);
    if (sortPlaylists) this.sortPlaylists();
    return written;
  }

  // 替换所有播放列表中满足条件的条目。
  Future<void> replaceTheseTracksInPlaylists(bool Function(E item) test, E Function(E item) replacement) async {
    for (final entry in playlistsMap.value.entries.toList()) {
      final updatedTracks = entry.value.tracks.map((item) => test(item) ? replacement(item) : item).toList();
      playlistsMap.value[entry.key] = entry.value.copyWith(tracks: updatedTracks);
    }
  }

  // 批量执行条目替换规则。
  Future<void> replaceTheseTracksInPlaylistsBulk(List<MapEntry<bool Function(E item), E Function(E item)>> replacements) async {
    for (final replacement in replacements) {
      await replaceTheseTracksInPlaylists(replacement.key, replacement.value);
    }
  }

  // 导入修改时间更新的播放列表。
  Future<void> importPlaylistsIfNewer(Iterable<GeneralPlaylist<E, S>> playlists) async {
    for (final playlist in playlists) {
      final existing = playlistsMap.value[playlist.name];
      if (existing == null || playlist.modifiedDate >= existing.modifiedDate) {
        await importPlaylistForce(playlist, sortPlaylists: false);
      }
    }
    sortPlaylists();
  }

  // 按播放列表已有排序规则整理新来源条目。
  GeneralPlaylist<E, S> ensureNewSourceItemsSorted(GeneralPlaylist<E, S> playlist) {
    final sorts = playlist.sortsType;
    if (sorts == null || sorts.isEmpty) return playlist;
    final tracks = [...playlist.tracks];
    onPlaylistItemsSort(sorts, playlist.sortReverse, tracks);
    return playlist.copyWith(tracks: tracks);
  }

  // 当前实现没有额外的重排锁状态。
  void resetCanReorder() {}

  Future<void> prepareAllPlaylistsFile() async {
    isLoading.value = true;
    final map = await prepareAllPlaylistsFunction();
    playlistsMap.value = map;
    final loadedFavourite = await prepareFavouritePlaylistFunction() ?? map[PLAYLIST_NAME_FAV];
    favouritesPlaylist.value = FavouritePlaylist<E, T, S>(
      name: loadedFavourite?.name ?? PLAYLIST_NAME_FAV,
      tracks: loadedFavourite?.tracks ?? const [],
      identifyBy: identifyBy,
    );
    isLoading.value = false;
  }
}

extension FavouritePlaylistRxUtils<E, T, S> on RxBaseCore<FavouritePlaylist<E, T, S>> {
  // 判断响应式收藏列表是否包含原始条目。
  bool isSubItemFavourite(T item) => value.isSubItemFavourite(item);

  // 判断响应式收藏列表是否包含完整条目。
  bool isItemFavourite(E item) => value.isItemFavourite(item);
}

extension PlaylistPinnedOrderUtils<E> on List<E> {
  /// 保留调用契约；具体置顶排序由上层列表管理器负责。
  void movePinnedFirst() {}
}
