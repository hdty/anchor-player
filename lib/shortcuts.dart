// キーボード操作の「唯一の定義」。
//
// 以前はキー判定の switch 文・SPEC.md の表・README の表の3箇所に同じ内容が
// 散らばっていてずれる余地があった。ここを直せば、実際の挙動もアプリ内の
// ショートカット一覧も同時に変わる。
import 'package:flutter/services.dart';

/// キーを押したときに起こす動作。
sealed class PlayerIntent {
  const PlayerIntent();
}

/// アンカーへ移動してそこから再生を続ける（コア機能）。
class JumpToAnchorIntent extends PlayerIntent {
  const JumpToAnchorIntent();
}

/// 再生 / 一時停止。
class TogglePlayIntent extends PlayerIntent {
  const TogglePlayIntent();
}

/// 現在の再生位置をアンカーにする。
class SetAnchorHereIntent extends PlayerIntent {
  const SetAnchorHereIntent();
}

/// 再生位置を相対移動する。
class SeekRelativeIntent extends PlayerIntent {
  const SeekRelativeIntent(this.delta);
  final Duration delta;
}

/// アンカーを相対移動する。押しっぱなしで連続実行される。
class NudgeAnchorIntent extends PlayerIntent {
  const NudgeAnchorIntent(this.delta);
  final Duration delta;
}

/// 一覧表示のときのまとまり。
enum ShortcutGroup {
  playback('Playback'),
  anchor('Anchor');

  const ShortcutGroup(this.label);
  final String label;
}

/// 1つのキーバインド。
class ShortcutSpec {
  const ShortcutSpec({
    required this.keys,
    required this.keyLabel,
    required this.description,
    required this.group,
    required this.intent,
  });

  /// 反応する論理キー（テンキーや代替キーを含む）。
  final List<LogicalKeyboardKey> keys;

  /// 一覧に出す表記。
  final String keyLabel;

  /// 一覧に出す説明。
  final String description;

  final ShortcutGroup group;
  final PlayerIntent intent;

  /// 押しっぱなしで連続実行するか（アンカー微調整のみ）。
  bool get repeatable => intent is NudgeAnchorIntent;
}

/// 定義表を読みやすくするための短縮名。
typedef _K = LogicalKeyboardKey;

/// 全キーバインド。一覧ダイアログはこの順で表示する。
const List<ShortcutSpec> kShortcuts = [
  ShortcutSpec(
    keys: [_K.space, _K.digit0, _K.numpad0],
    keyLabel: 'Space / 0',
    description: 'Jump to anchor and keep playing',
    group: ShortcutGroup.playback,
    intent: JumpToAnchorIntent(),
  ),
  ShortcutSpec(
    keys: [_K.enter, _K.numpadEnter],
    keyLabel: 'Enter',
    description: 'Play / pause',
    group: ShortcutGroup.playback,
    intent: TogglePlayIntent(),
  ),
  ShortcutSpec(
    keys: [_K.arrowLeft],
    keyLabel: '←',
    description: 'Back 10 s',
    group: ShortcutGroup.playback,
    intent: SeekRelativeIntent(Duration(seconds: -10)),
  ),
  ShortcutSpec(
    keys: [_K.arrowRight],
    keyLabel: '→',
    description: 'Forward 10 s',
    group: ShortcutGroup.playback,
    intent: SeekRelativeIntent(Duration(seconds: 10)),
  ),
  ShortcutSpec(
    keys: [_K.digit5, _K.numpad5, _K.keyS],
    keyLabel: '5 / S',
    description: 'Set anchor at the current position',
    group: ShortcutGroup.anchor,
    intent: SetAnchorHereIntent(),
  ),
  // 微調整は左列 = 前へ / 右列 = 後ろへ。テンキーの並びがそのまま方向になる。
  ShortcutSpec(
    keys: [_K.digit1, _K.numpad1, _K.keyZ],
    keyLabel: '1 / Z',
    description: 'Anchor −0.2 s (hold to repeat)',
    group: ShortcutGroup.anchor,
    intent: NudgeAnchorIntent(Duration(milliseconds: -200)),
  ),
  ShortcutSpec(
    keys: [_K.digit3, _K.numpad3, _K.keyC],
    keyLabel: '3 / C',
    description: 'Anchor +0.2 s (hold to repeat)',
    group: ShortcutGroup.anchor,
    intent: NudgeAnchorIntent(Duration(milliseconds: 200)),
  ),
  ShortcutSpec(
    keys: [_K.digit4, _K.numpad4, _K.keyA],
    keyLabel: '4 / A',
    description: 'Anchor −1 s (hold to repeat)',
    group: ShortcutGroup.anchor,
    intent: NudgeAnchorIntent(Duration(seconds: -1)),
  ),
  ShortcutSpec(
    keys: [_K.digit6, _K.numpad6, _K.keyD],
    keyLabel: '6 / D',
    description: 'Anchor +1 s (hold to repeat)',
    group: ShortcutGroup.anchor,
    intent: NudgeAnchorIntent(Duration(seconds: 1)),
  ),
  ShortcutSpec(
    keys: [_K.digit7, _K.numpad7, _K.keyQ],
    keyLabel: '7 / Q',
    description: 'Anchor −5 s (hold to repeat)',
    group: ShortcutGroup.anchor,
    intent: NudgeAnchorIntent(Duration(seconds: -5)),
  ),
  ShortcutSpec(
    keys: [_K.digit9, _K.numpad9, _K.keyE],
    keyLabel: '9 / E',
    description: 'Anchor +5 s (hold to repeat)',
    group: ShortcutGroup.anchor,
    intent: NudgeAnchorIntent(Duration(seconds: 5)),
  ),
];

/// 論理キー → バインド の逆引き。キー入力のたびに線形探索しないための表。
final Map<LogicalKeyboardKey, ShortcutSpec> kShortcutByKey = {
  for (final s in kShortcuts)
    for (final key in s.keys) key: s,
};
