import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../shortcuts.dart';

/// キーボード操作の一覧。内容は [kShortcuts] から組み立てるので、
/// 実際の挙動とずれることがない。
class ShortcutsDialog extends StatelessWidget {
  const ShortcutsDialog({super.key});

  static Future<void> show(BuildContext context) {
    return showDialog<void>(
      context: context,
      builder: (_) => const ShortcutsDialog(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return AlertDialog(
      title: const Text('Keyboard shortcuts'),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final group in ShortcutGroup.values) ...[
                Padding(
                  padding: const EdgeInsets.only(top: 12, bottom: 6),
                  child: Text(
                    group.label,
                    style: theme.textTheme.labelLarge
                        ?.copyWith(color: theme.colorScheme.primary),
                  ),
                ),
                for (final s in kShortcuts.where((s) => s.group == group))
                  _ShortcutRow(spec: s),
              ],
            ],
          ),
        ),
      ),
      // バージョンは Close と同じ行に置く。内容領域に入れると一覧を押し出して
      // 最後の項目が見えなくなる（v0.7.1 で 9/E の行が隠れていた）。
      // actions は Row ではなく OverflowBar なので、Expanded は使えない。
      // 左右に振り分けるのは actionsAlignment で行う。
      actionsAlignment: MainAxisAlignment.spaceBetween,
      actions: [
        const _VersionLine(),
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Close'),
        ),
      ],
    );
  }
}

/// アプリ名とバージョン。不具合を報告するときにどのビルドか分かるように出す。
///
/// バージョンの数字はここに書かない。`pubspec.yaml` を唯一の定義とし、
/// 実行ファイルに埋め込まれた値を [PackageInfo] 経由で読む
/// （Windows は Runner.rc の `FLUTTER_VERSION` が pubspec 由来）。
/// ここに定数で持つとリリースのたびに書き換え忘れてずれる。
class _VersionLine extends StatefulWidget {
  const _VersionLine();

  @override
  State<_VersionLine> createState() => _VersionLineState();
}

class _VersionLineState extends State<_VersionLine> {
  String? _label;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final info = await PackageInfo.fromPlatform();
      if (!mounted) return;
      setState(() => _label = '${info.appName} v${info.version}');
    } catch (_) {
      // 取得できない環境（テストなど）では黙って出さない。
      // ここで落ちて一覧まで見られなくなる方が困る。
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // actions 行（OverflowBar）に置くので、内容ぶんの幅に収める。
    return Padding(
      padding: const EdgeInsets.only(left: 8),
      child: Text(
        _label ?? '',
        style: theme.textTheme.bodySmall
            ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
      ),
    );
  }
}

class _ShortcutRow extends StatelessWidget {
  const _ShortcutRow({required this.spec});

  final ShortcutSpec spec;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 96,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                spec.keyLabel,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: theme.colorScheme.onSurface,
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(top: 3),
              child: Text(
                spec.description,
                style: theme.textTheme.bodyMedium,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
