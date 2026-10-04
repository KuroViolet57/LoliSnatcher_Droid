part of '../hitomi_handler.dart';

/// One node of hitomi's on-disk B-tree, used for free-text search.
@immutable
class HitomiIndexNode {
  const HitomiIndexNode({required this.keys, required this.datas, required this.subnodes});

  final List<Uint8List> keys;

  /// `(offset, length)` into the matching `.data` file.
  final List<({int offset, int length})> datas;
  final List<int> subnodes;

  bool get isLeaf => subnodes.every((a) => a == 0);
}
