// 提供播放列表标签筛选、分组、颜色和保存选择模型。

import 'package:nampack/nampack.dart';

enum PlaylistTagFilterState { none, included, excluded }

sealed class PlaylistTagKey {
  const PlaylistTagKey();

  String get path;
}

class PlaylistUserTag extends PlaylistTagKey {
  @override
  final String path;

  const PlaylistUserTag(this.path);

  @override
  bool operator ==(Object other) => other is PlaylistUserTag && other.path == path;

  @override
  int get hashCode => path.hashCode;
}

enum PlaylistVirtualTag implements PlaylistTagKey {
  pinned,
  untagged,
  m3u,
  remote;

  @override
  String get path => name;
}

class PlaylistTagsSelection {
  final Set<PlaylistTagKey> included;
  final Set<PlaylistTagKey> excluded;

  const PlaylistTagsSelection({this.included = const {}, this.excluded = const {}});

  @override
  bool operator ==(Object other) => other is PlaylistTagsSelection && _setsEqual(included, other.included) && _setsEqual(excluded, other.excluded);

  @override
  int get hashCode => Object.hashAll(included) ^ Object.hashAll(excluded);
}

class PlaylistTagChip {
  final PlaylistTagKey key;
  final PlaylistTagFilterState state;
  final int count;
  final int depth;
  final String? label;
  final int? color;

  const PlaylistTagChip({
    required this.key,
    required this.state,
    required this.count,
    this.depth = 0,
    this.label,
    this.color,
  });
}

class PlaylistTagInfo {
  final String path;
  final int count;
  final int? color;
  final List<PlaylistTagInfo> nested;

  const PlaylistTagInfo({required this.path, required this.count, this.color, this.nested = const []});
}

class PlaylistTagSection {
  final PlaylistTagKey key;
  final List<String> names;
  final int? color;

  const PlaylistTagSection({required this.key, required this.names, this.color});
}

class PlaylistTagsFilter {
  static const separator = '/';

  final Iterable<String> Function() _allNames;
  final Iterable<String> Function(String name) _tagsForName;
  final bool Function(String name, PlaylistVirtualTag tag) _matchesVirtual;
  final void Function() _onChanged;
  final Map<String, int> _colors = {};
  final List<String> _tagOrder = [];

  final Rx<int> revision = 0.obs;
  final List<PlaylistTagsSelection> savedSelections = [];
  PlaylistTagsSelection selection = const PlaylistTagsSelection();

  PlaylistTagsFilter({
    Iterable<String> Function()? allNames,
    Iterable<String> Function(String name)? tagsForName,
    bool Function(String name, PlaylistVirtualTag tag)? matchesVirtual,
    void Function()? onChanged,
  }) : _allNames = allNames ?? _emptyNames,
       _tagsForName = tagsForName ?? _emptyTags,
       _matchesVirtual = matchesVirtual ?? _neverMatchesVirtual,
       _onChanged = onChanged ?? _noChange;

  bool get isActive => selection.included.isNotEmpty || selection.excluded.isNotEmpty;

  List<String> get allPaths {
    final paths = <String>{};
    for (final name in _allNames()) {
      paths.addAll(expandTags(_tagsForName(name)));
    }
    final result = paths.toList();
    result.sort(_comparePaths);
    return result;
  }

  // 标准化标签路径并去重。
  static List<String> normalizeTags(Iterable<String> items) {
    final normalized = <String>[];
    final added = <String>{};
    for (final item in items) {
      final value = item.split(separator).map((part) => part.trim()).where((part) => part.isNotEmpty).join(separator);
      if (value.isNotEmpty && added.add(value)) normalized.add(value);
    }
    return normalized;
  }

  // 展开嵌套标签的所有父路径。
  static List<String> expandTags(Iterable<String> items) {
    final expanded = <String>[];
    final added = <String>{};
    for (final item in normalizeTags(items)) {
      final parts = item.split(separator);
      for (var i = 1; i <= parts.length; i++) {
        final path = parts.take(i).join(separator);
        if (added.add(path)) expanded.add(path);
      }
    }
    return expanded;
  }

  // 生成界面显示的标签筛选芯片。
  List<PlaylistTagChip> computeChips() {
    final chips = <PlaylistTagChip>[];
    for (final path in allPaths) {
      final key = PlaylistUserTag(path);
      chips.add(
        PlaylistTagChip(
          key: key,
          state: _stateOf(key),
          count: _allNames().where((name) => expandTags(_tagsForName(name)).contains(path)).length,
          depth: path.split(separator).length - 1,
          label: path.split(separator).last,
          color: colorOf(path),
        ),
      );
    }
    for (final tag in PlaylistVirtualTag.values) {
      final count = _allNames().where((name) => _matchesVirtual(name, tag)).length;
      if (count > 0) chips.add(PlaylistTagChip(key: tag, state: _stateOf(tag), count: count));
    }
    return chips;
  }

  // 切换包含条件。
  void toggleIncluded(PlaylistTagKey key) {
    final included = {...selection.included};
    final excluded = {...selection.excluded}..remove(key);
    included.contains(key) ? included.remove(key) : included.add(key);
    _setSelection(PlaylistTagsSelection(included: included, excluded: excluded));
  }

  // 切换排除条件。
  void toggleExcluded(PlaylistTagKey key) {
    final included = {...selection.included}..remove(key);
    final excluded = {...selection.excluded};
    excluded.contains(key) ? excluded.remove(key) : excluded.add(key);
    _setSelection(PlaylistTagsSelection(included: included, excluded: excluded));
  }

  // 清除当前筛选。
  void clear() => _setSelection(const PlaylistTagsSelection());

  // 保存当前筛选。
  void saveCurrentSelection() {
    if (isActive && !savedSelections.contains(selection)) {
      savedSelections.add(selection);
      refresh();
    }
  }

  // 应用已保存的筛选。
  void applySelection(PlaylistTagsSelection value) => _setSelection(value);

  // 删除已保存的筛选。
  void removeSavedSelection(PlaylistTagsSelection value) {
    savedSelections.remove(value);
    refresh();
  }

  // 根据当前包含和排除条件过滤播放列表名称。
  List<String> apply(Iterable<String> names) {
    if (!isActive) return names.toList();
    return names.where((name) {
      final included = selection.included.every((key) => _matches(name, key));
      final excluded = selection.excluded.any((key) => _matches(name, key));
      return included && !excluded;
    }).toList();
  }

  // 按顶层标签和虚拟标签对播放列表分组。
  List<PlaylistTagSection> groupByTopLevelTag(Iterable<String> names) {
    final sections = <PlaylistTagKey, List<String>>{};
    for (final name in names) {
      final topLevel = normalizeTags(_tagsForName(name)).map((tag) => tag.split(separator).first).toSet();
      if (topLevel.isEmpty) (sections[PlaylistVirtualTag.untagged] ??= []).add(name);
      for (final tag in topLevel) {
        (sections[PlaylistUserTag(tag)] ??= []).add(name);
      }
      for (final tag in [PlaylistVirtualTag.pinned, PlaylistVirtualTag.m3u, PlaylistVirtualTag.remote]) {
        if (_matchesVirtual(name, tag)) (sections[tag] ??= []).add(name);
      }
    }
    return sections.entries.map((entry) => PlaylistTagSection(key: entry.key, names: entry.value, color: entry.key is PlaylistUserTag ? colorOf(entry.key.path) : null)).toList();
  }

  // 返回标签管理页使用的顶层与嵌套统计。
  List<PlaylistTagInfo> listTopLevelTags() {
    final counts = <String, int>{};
    for (final name in _allNames()) {
      for (final path in expandTags(_tagsForName(name))) {
        counts[path] = (counts[path] ?? 0) + 1;
      }
    }
    final topPaths = counts.keys.where((path) => !path.contains(separator)).toList()..sort(_comparePaths);
    return topPaths.map((top) {
      final nested = counts.keys.where((path) => path.startsWith('$top$separator')).toList()..sort(_comparePaths);
      return PlaylistTagInfo(
        path: top,
        count: counts[top] ?? 0,
        color: colorOf(top),
        nested: nested.map((path) => PlaylistTagInfo(path: path, count: counts[path] ?? 0, color: colorOf(path))).toList(),
      );
    }).toList();
  }

  int? colorOf(String path) => _colors[path];

  // 返回标签路径及其最近父路径的颜色。
  List<int> colorsOf(Iterable<String> tags) {
    final colors = <int>[];
    for (final tag in normalizeTags(tags)) {
      final parts = tag.split(separator);
      int? color;
      for (var i = parts.length; i > 0 && color == null; i--) {
        color = _colors[parts.take(i).join(separator)];
      }
      if (color != null && !colors.contains(color)) colors.add(color);
    }
    return colors;
  }

  // 设置标签颜色。
  void setColor(String path, int? color) {
    color == null ? _colors.remove(path) : _colors[path] = color;
    refresh();
  }

  // 同步重命名标签颜色路径。
  void renamePath(String oldPath, String newPath) {
    final affected = _colors.entries.where((entry) => entry.key == oldPath || entry.key.startsWith('$oldPath$separator')).toList();
    for (final entry in affected) {
      _colors.remove(entry.key);
      _colors['$newPath${entry.key.substring(oldPath.length)}'] = entry.value;
    }
    refresh();
  }

  // 删除标签及其子路径颜色。
  void removePath(String path) {
    _colors.removeWhere((key, _) => key == path || key.startsWith('$path$separator'));
    refresh();
  }

  // 重排顶层标签。
  void reorderTopLevelTag(int oldIndex, int newIndex) {
    final current = listTopLevelTags().map((tag) => tag.path).toList();
    if (oldIndex < 0 || oldIndex >= current.length) return;
    if (newIndex > oldIndex) newIndex--;
    final item = current.removeAt(oldIndex);
    current.insert(newIndex.clamp(0, current.length), item);
    _tagOrder
      ..clear()
      ..addAll(current);
    refresh();
  }

  // 通知依赖标签数据的界面刷新。
  void refresh() {
    revision.value++;
    _onChanged();
  }

  PlaylistTagFilterState _stateOf(PlaylistTagKey key) {
    if (selection.included.contains(key)) return PlaylistTagFilterState.included;
    if (selection.excluded.contains(key)) return PlaylistTagFilterState.excluded;
    return PlaylistTagFilterState.none;
  }

  bool _matches(String name, PlaylistTagKey key) {
    return switch (key) {
      PlaylistUserTag(:final path) => expandTags(_tagsForName(name)).contains(path),
      PlaylistVirtualTag() => _matchesVirtual(name, key),
    };
  }

  void _setSelection(PlaylistTagsSelection value) {
    selection = value;
    refresh();
  }

  int _comparePaths(String a, String b) {
    final aIndex = _tagOrder.indexOf(a.split(separator).first);
    final bIndex = _tagOrder.indexOf(b.split(separator).first);
    if (aIndex >= 0 || bIndex >= 0) {
      if (aIndex < 0) return 1;
      if (bIndex < 0) return -1;
      if (aIndex != bIndex) return aIndex.compareTo(bIndex);
    }
    return a.compareTo(b);
  }
}

bool _setsEqual(Set<Object?> a, Set<Object?> b) => a.length == b.length && a.containsAll(b);
Iterable<String> _emptyNames() => const [];
Iterable<String> _emptyTags(String _) => const [];
bool _neverMatchesVirtual(String _, PlaylistVirtualTag __) => false;
void _noChange() {}
