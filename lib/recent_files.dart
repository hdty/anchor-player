import 'dart:io';

import 'package:shared_preferences/shared_preferences.dart';

/// 最近開いたファイルの履歴。
///
/// 連番の教材を順に進める使い方なので、履歴が見えるだけで「次にどれをやるか」が
/// 分かる。ファイルダイアログを開かずに再開できるようにするのが目的。
class RecentFiles {
  const RecentFiles._(this.paths);

  /// 新しい順。先頭が最後に開いたファイル。
  final List<String> paths;

  static const _key = 'recent_files';

  /// 画面に出す件数。多すぎると空状態がうるさくなる。
  static const max = 5;

  static const empty = RecentFiles._(<String>[]);

  bool get isEmpty => paths.isEmpty;

  /// 保存された履歴を読む。存在しなくなったファイルは落とす
  /// （Android は選択のたびにキャッシュへ複製されるため、古い項目は消えていることがある）。
  static Future<RecentFiles> load() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getStringList(_key) ?? const <String>[];
    final alive = saved.where((p) => File(p).existsSync()).toList();
    if (alive.length != saved.length) {
      await prefs.setStringList(_key, alive);
    }
    return RecentFiles._(alive);
  }

  /// [path] を先頭に積んで保存する。同じものは重複させない。
  static Future<RecentFiles> add(String path) async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getStringList(_key) ?? const <String>[];
    final next = <String>[
      path,
      ...saved.where((p) => p != path),
    ].take(max).toList();
    await prefs.setStringList(_key, next);
    return RecentFiles._(next);
  }
}
