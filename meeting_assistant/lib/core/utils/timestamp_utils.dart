class TimestampUtils {
  static List<List<int>> getPairs(List<int> flatTimestamps) {
    final pairs = <List<int>>[];
    for (var i = 0; i < flatTimestamps.length; i += 2) {
      if (i + 1 < flatTimestamps.length) {
        pairs.add([flatTimestamps[i], flatTimestamps[i + 1]]);
      }
    }
    return pairs;
  }
}
