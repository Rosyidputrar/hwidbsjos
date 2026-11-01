import 'package:flutter_test/flutter_test.dart';
import 'package:rynex/agent/models.dart';

/// Favorites keep starring order (not catalog order) and skip keys whose
/// model left the catalog; storage keeps those keys, so this only filters
/// what the sheet shows.
void main() {
  ModelInfo model(String provider, String id) => ModelInfo({
    'provider': provider,
    'id': id,
    'name': id,
  });

  test('follows starring order, not catalog order', () {
    final models = [model('rynex', 'a'), model('rynex', 'b'), model('rynex', 'c')];
    final favs = favoriteModelsInOrder(models, ['rynex/c', 'rynex/a']);
    expect(favs.map((m) => m.key).toList(), ['rynex/c', 'rynex/a']);
  });

  test('skips keys missing from the catalog', () {
    final models = [model('rynex', 'a')];
    final favs = favoriteModelsInOrder(models, ['rynex/gone', 'rynex/a']);
    expect(favs.map((m) => m.key).toList(), ['rynex/a']);
  });

  test('dedupes repeated keys and handles empty input', () {
    final models = [model('rynex', 'a')];
    expect(favoriteModelsInOrder(models, ['rynex/a', 'rynex/a']).length, 1);
    expect(favoriteModelsInOrder(models, []), isEmpty);
    expect(favoriteModelsInOrder([], ['rynex/a']), isEmpty);
  });
}
