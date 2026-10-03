import 'package:path/path.dart' as p;

import 'package:namida/controller/directory_index.dart';

/// 播客下载目录与本地媒体扫描目录之间的无副作用合并逻辑。
List<DirectoryIndex> ensureDirectoryCovered(
  Iterable<DirectoryIndex> directories,
  DirectoryIndex target,
) {
  final result = directories.toList();
  final targetPath = p.normalize(target.sourceRaw);
  if (targetPath.isEmpty) return result;

  final isCovered = result.any((directory) {
    final sourcePath = p.normalize(directory.sourceRaw);
    if (sourcePath.isEmpty || directory.type != DirectoryIndexType.local) return false;
    return p.equals(sourcePath, targetPath) || p.isWithin(sourcePath, targetPath);
  });
  if (!isCovered) result.add(target);
  return result;
}