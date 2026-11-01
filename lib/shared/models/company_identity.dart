import 'dart:math' as math;

/// How a GSTIN on a bill relates to the scanning company.
enum GstinMatch { exact, samePan, none }

/// The scanning company's GSTINs and names, used to tell it apart from the
/// supplier on a bill. Mirrors `backend/app/services/party.py`.
class CompanyIdentity {
  CompanyIdentity({
    Iterable<String?> names = const [],
    Iterable<String?> gstins = const [],
  })  : names = [
          for (final name in names)
            if (name != null && normalizeName(name).isNotEmpty) name.trim(),
        ],
        gstins = {
          for (final gstin in gstins)
            if (gstin != null && compactGstin(gstin).length == 15)
              compactGstin(gstin),
        } {
    pans = {for (final gstin in this.gstins) gstin.substring(2, 12)};
  }

  static final CompanyIdentity empty = CompanyIdentity();

  final List<String> names;
  final Set<String> gstins;
  late final Set<String> pans;

  bool get isEmpty => names.isEmpty && gstins.isEmpty;

  static const _noiseWords = {
    'M', 'S', 'MS', 'M/S', 'MESSRS', 'THE', 'PVT', 'PRIVATE', 'LTD',
    'LIMITED', 'LLP', 'CO', 'COMPANY', 'CORP', 'CORPORATION', 'INC', 'OPC',
    'AND', '&', 'INDIA',
  };

  static String compactGstin(String value) =>
      value.toUpperCase().replaceAll(RegExp(r'[^A-Z0-9]'), '');

  static String normalizeName(String? value) {
    final text = (value ?? '')
        .toUpperCase()
        .replaceAll('M/S', ' ')
        .replaceAll(RegExp(r'[^A-Z0-9& ]'), ' ');
    return text
        .split(RegExp(r'\s+'))
        .where((word) => word.isNotEmpty && !_noiseWords.contains(word))
        .join(' ');
  }

  static bool namesMatch(String? a, String? b) {
    final left = normalizeName(a);
    final right = normalizeName(b);
    if (left.isEmpty || right.isEmpty) return false;
    if (left == right) return true;
    final shorter = left.length <= right.length ? left : right;
    final longer = left.length <= right.length ? right : left;
    // "SUNRISE TRADERS" inside "SUNRISE TRADERS HYDERABAD BRANCH"
    if (shorter.split(' ').length >= 2 && ' $longer '.contains(' $shorter ')) {
      return true;
    }
    return _similarity(left, right) >= 0.88;
  }

  GstinMatch gstinMatch(String? value) {
    if (value == null) return GstinMatch.none;
    final gstin = compactGstin(value);
    if (gstin.length != 15) return GstinMatch.none;
    if (gstins.contains(gstin)) return GstinMatch.exact;
    return pans.contains(gstin.substring(2, 12))
        ? GstinMatch.samePan
        : GstinMatch.none;
  }

  bool ownsName(String? value) => names.any((own) => namesMatch(value, own));

  /// 1 - edit distance / length of the longer string.
  static double _similarity(String a, String b) {
    final longest = math.max(a.length, b.length);
    if (longest == 0) return 1;
    var previous = List<int>.generate(b.length + 1, (i) => i);
    for (var i = 1; i <= a.length; i++) {
      final current = List<int>.filled(b.length + 1, 0)..[0] = i;
      for (var j = 1; j <= b.length; j++) {
        final cost = a.codeUnitAt(i - 1) == b.codeUnitAt(j - 1) ? 0 : 1;
        current[j] = math.min(
          math.min(current[j - 1] + 1, previous[j] + 1),
          previous[j - 1] + cost,
        );
      }
      previous = current;
    }
    return 1 - previous[b.length] / longest;
  }
}
