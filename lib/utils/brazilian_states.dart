// The 27 Brazilian states/federal units, plus a normalizer that maps
// messy real-world text (what a reverse-geocoding service returns, which
// is free text written by humans) onto one canonical name.
//
// WHY this lives in its own file: both the location flow (automatic state
// detection) and the settings screen (manual state picker) need the exact
// same list and the exact same spelling. Keeping one canonical source
// avoids the two flows ever disagreeing on what "the state" is called —
// which would silently break the Radio Browser search (it matches on the
// `state` field as free text, so "SP" and "São Paulo" would return
// different, non-overlapping results if we were not consistent).

/// One Brazilian state, with the exact name Nice Radio uses when
/// querying the Radio Browser API's `state` filter.
class BrazilianState {
  final String name;
  final String abbreviation;

  const BrazilianState(this.name, this.abbreviation);
}

class BrazilianStates {
  BrazilianStates._();

  static const List<BrazilianState> all = [
    BrazilianState('Acre', 'AC'),
    BrazilianState('Alagoas', 'AL'),
    BrazilianState('Amapá', 'AP'),
    BrazilianState('Amazonas', 'AM'),
    BrazilianState('Bahia', 'BA'),
    BrazilianState('Ceará', 'CE'),
    BrazilianState('Distrito Federal', 'DF'),
    BrazilianState('Espírito Santo', 'ES'),
    BrazilianState('Goiás', 'GO'),
    BrazilianState('Maranhão', 'MA'),
    BrazilianState('Mato Grosso', 'MT'),
    BrazilianState('Mato Grosso do Sul', 'MS'),
    BrazilianState('Minas Gerais', 'MG'),
    BrazilianState('Pará', 'PA'),
    BrazilianState('Paraíba', 'PB'),
    BrazilianState('Paraná', 'PR'),
    BrazilianState('Pernambuco', 'PE'),
    BrazilianState('Piauí', 'PI'),
    BrazilianState('Rio de Janeiro', 'RJ'),
    BrazilianState('Rio Grande do Norte', 'RN'),
    BrazilianState('Rio Grande do Sul', 'RS'),
    BrazilianState('Rondônia', 'RO'),
    BrazilianState('Roraima', 'RR'),
    BrazilianState('Santa Catarina', 'SC'),
    BrazilianState('São Paulo', 'SP'),
    BrazilianState('Sergipe', 'SE'),
    BrazilianState('Tocantins', 'TO'),
  ];

  /// Turns free text (e.g. what `geocoding` returns for
  /// `Placemark.administrativeArea`) into one of [all]'s canonical names,
  /// or `null` if nothing matches closely enough.
  ///
  /// WHY this exists: reverse-geocoding services do not agree on format —
  /// some return "São Paulo", others "SP", others "State of São Paulo".
  /// We only trust an exact (accent/case-insensitive) match on the full
  /// name or the abbreviation; anything looser risks silently resolving
  /// to the wrong state, which the user would only notice much later as
  /// "why am I seeing the wrong stations".
  static String? normalize(String? raw) {
    if (raw == null || raw.trim().isEmpty) return null;
    final cleaned = _foldForComparison(raw);

    for (final state in all) {
      if (_foldForComparison(state.name) == cleaned ||
          _foldForComparison(state.abbreviation) == cleaned) {
        return state.name;
      }
    }
    return null;
  }

  /// Lowercases and strips accents so comparisons are not tripped up by
  /// e.g. "Sao Paulo" vs "São Paulo".
  static String _foldForComparison(String input) {
    const withAccents = 'áàâãäéèêëíìîïóòôõöúùûüçñÁÀÂÃÄÉÈÊËÍÌÎÏÓÒÔÕÖÚÙÛÜÇÑ';
    const withoutAccents = 'aaaaaeeeeiiiiooooouuuucnAAAAAEEEEIIIIOOOOOUUUUCN';

    final buffer = StringBuffer();
    for (final char in input.trim().toLowerCase().split('')) {
      final index = withAccents.indexOf(char);
      buffer.write(index == -1 ? char : withoutAccents[index]);
    }
    return buffer.toString();
  }
}
