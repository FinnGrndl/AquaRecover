Future<List<R>> mapWithConcurrencyLimit<T, R>(
  Iterable<T> items, {
  required int maxConcurrent,
  required Future<R> Function(T item) operation,
}) async {
  if (maxConcurrent < 1) {
    throw ArgumentError.value(
      maxConcurrent,
      'maxConcurrent',
      'must be at least one',
    );
  }
  final input = items.toList(growable: false);
  final output = <R>[];
  for (var start = 0; start < input.length; start += maxConcurrent) {
    final end = (start + maxConcurrent).clamp(0, input.length);
    output.addAll(
      await Future.wait([
        for (var index = start; index < end; index++) operation(input[index]),
      ]),
    );
  }
  return output;
}
