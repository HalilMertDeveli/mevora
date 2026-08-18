/// Cursor-based page. Discovery, chat, matches, and notifications all paginate
/// instead of loading unbounded lists.
class Page<T> {
  const Page({
    required this.items,
    this.nextCursor,
  });

  final List<T> items;
  final String? nextCursor;

  bool get hasMore => nextCursor != null && nextCursor!.isNotEmpty;

  Page<T> copyWith({
    List<T>? items,
    String? nextCursor,
  }) {
    return Page<T>(
      items: items ?? this.items,
      nextCursor: nextCursor ?? this.nextCursor,
    );
  }
}
