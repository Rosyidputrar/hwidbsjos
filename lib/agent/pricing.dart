/// Money formatting. Costs are pi's own figures in USD, computed by the
/// host from each model's pricing (see agent/src/providers.ts); the app
/// only displays them.
library;

/// Compact USD formatting: adaptive decimals, trailing zeros trimmed.
/// 0.10545 -> "$0.105", 0.0079 -> "$0.0079", 658.69 -> "$659".
String formatUsd(num v) => v < 0 ? '-${formatUsd(-v)}' : '\$${formatNumber(v)}';

/// A plain compact number with adaptive decimals (no unit), for editable
/// fields: 0.10545 -> "0.105", 658.69 -> "659".
String formatNumber(num v) {
  final abs = v.abs();
  final digits = abs >= 100 ? 0 : abs >= 1 ? 2 : abs >= 0.01 ? 3 : 4;
  var s = v.toStringAsFixed(digits);
  if (s.contains('.')) {
    s = s.replaceAll(RegExp(r'\.?0+$'), '');
    if (s.endsWith('.')) s = s.substring(0, s.length - 1);
  }
  return s;
}
