/// Ids of every category below [id], at any depth.
Set<String> categoryDescendants(
  List<Map<String, dynamic>> categories,
  String id,
) {
  final children = <String, List<String>>{};
  for (final c in categories) {
    final parent = c['parentId']?.toString();
    if (parent != null) {
      children.putIfAbsent(parent, () => []).add(c['id'].toString());
    }
  }
  final found = <String>{};
  final pending = [...?children[id]];
  while (pending.isNotEmpty) {
    final next = pending.removeLast();
    if (found.add(next)) pending.addAll(children[next] ?? const []);
  }
  return found;
}

/// Categories that may become the parent of [selfId] (null when adding):
/// not itself, not one of its descendants (a cycle), and active unless
/// already selected.
List<Map<String, dynamic>> parentCandidates(
  List<Map<String, dynamic>> categories, {
  String? selfId,
  String? currentParentId,
}) {
  final excluded = selfId == null
      ? <String>{}
      : {selfId, ...categoryDescendants(categories, selfId)};
  final options = [
    for (final c in categories)
      if (!excluded.contains(c['id'].toString()) &&
          (c['isActive'] != false || c['id'].toString() == currentParentId))
        c,
  ];
  options.sort(
    (a, b) =>
        '${a['name']}'.toLowerCase().compareTo('${b['name']}'.toLowerCase()),
  );
  return options;
}
