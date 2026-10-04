/// 分页追加的合并逻辑（纯函数，便于单测）。
library;

/// 把 [incoming] 追加到 [current] 之后，按 [keyOf] 去重。
///
/// 返回合并后的列表与「本页真正新增的条数」。调用方用 [added] == 0
/// 判断「后端忽略了 page 或已到末尾」——若只看 `incoming.isNotEmpty`
/// 会在后端不认 page 时无限重复追加同一页。
({List<T> items, int added}) mergePage<T>(
  List<T> current,
  List<T> incoming,
  String Function(T) keyOf,
) {
  final seen = <String>{};
  for (final e in current) {
    seen.add(keyOf(e));
  }
  final fresh = <T>[];
  for (final e in incoming) {
    if (seen.add(keyOf(e))) fresh.add(e);
  }
  if (fresh.isEmpty) return (items: current, added: 0);
  return (items: <T>[...current, ...fresh], added: fresh.length);
}
