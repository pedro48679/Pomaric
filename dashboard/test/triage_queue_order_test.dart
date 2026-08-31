import 'package:flutter_test/flutter_test.dart';
import 'package:dashboard/models/models.dart';
import 'package:dashboard/providers/dashboard_provider.dart';

// Reproduz o Bug #1: uma maçã enviada da Grelha para a triagem tem de aparecer
// no topo da fila, não na posição que ocupava no lote.

Apple a(String id) => Apple(id: id, frames: const []);

List<String> ids(List<Apple> apples) => apples.map((x) => x.id).toList();

void main() {
  group('orderTriageQueue', () {
    // O lote, na ordem cronológica, com a Healthy escolhida (h1) em 4º lugar,
    // tal como no bug reportado.
    final loteOrder = [a('u1'), a('u2'), a('u3'), a('h1'), a('u4')];

    test('maçã forçada sobe da 4ª posição para o topo', () {
      final out = orderTriageQueue(loteOrder, {'h1'}, {});
      expect(out.first.id, 'h1');
    });

    test('a forçada mais recente fica em primeiro', () {
      // Ordem de inserção no Set: h1 primeiro, u4 a seguir (mais recente).
      final out = orderTriageQueue(loteOrder, {'h1', 'u4'}, {});
      expect(ids(out).take(2).toList(), ['u4', 'h1']);
    });

    test('forçadas > pending da BD > incertas por heurística', () {
      // u1 e u2 são incertas por heurística (já em matched), u3 vem da BD,
      // h1 foi forçada na Grelha.
      final out = orderTriageQueue(loteOrder, {'h1'}, {'u3'});
      expect(out.first.id, 'h1'); // forçada no topo
      expect(out[1].id, 'u3'); // pending logo a seguir
      // as restantes (incertas) mantêm a ordem do lote entre si
      expect(ids(out).sublist(2), ['u1', 'u2', 'u4']);
    });

    test('sem forçadas nem pending preserva a ordem do lote', () {
      final out = orderTriageQueue(loteOrder, {}, {});
      expect(ids(out), ['u1', 'u2', 'u3', 'h1', 'u4']);
    });
  });
}
