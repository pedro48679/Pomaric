import 'package:flutter_test/flutter_test.dart';
import 'package:dashboard/models/models.dart';
import 'package:dashboard/data/mappers/bi_adapters.dart';

// O SPC dá aos últimos 7 dias pelo menos 60% da largura do eixo, mesmo na
// vista de 30 dias: as sessões recentes ficam em resolução total e o
// histórico antigo condensa-se em blocos de contexto.

Apple appleAt(String id, String loc, DateTime ts, {String label = 'Healthy'}) =>
    Apple(id: id, frames: const [], location: loc, timestamp: ts, cnn2Label: label);

/// Um lote (localização) com as maçãs que lhe pertencem.
Batch batchOf(String loc, List<Apple> apples) => Batch(
      id: 'LT-$loc',
      name: 'Lote $loc',
      date: apples.map((a) => a.timestamp).reduce((a, b) => a.isAfter(b) ? a : b),
      apples: apples,
      location: loc,
    );

void main() {
  final now = DateTime.now();

  /// `oldDays` dias de histórico (2 talhões por dia) + `recentDays` dias
  /// dentro da janela de 7 dias (1 talhão por dia).
  List<Batch> build({required int oldDays, required int recentDays}) {
    final byLoc = <String, List<Apple>>{};
    void add(String loc, Apple a) => byLoc.putIfAbsent(loc, () => []).add(a);

    for (int d = 0; d < oldDays; d++) {
      final ts = now.subtract(Duration(days: 8 + d, hours: 3));
      add('Talhao 1', appleAt('o1-$d', 'Talhao 1', ts));
      add('Talhao 2', appleAt('o2-$d', 'Talhao 2', ts));
    }
    for (int d = 0; d < recentDays; d++) {
      final ts = now.subtract(Duration(days: d, hours: 3));
      add('Talhao 3', appleAt('r-$d', 'Talhao 3', ts));
    }
    return [for (final e in byLoc.entries) batchOf(e.key, e.value)];
  }

  group('cadenciaSanidade · foco nos últimos 7 dias', () {
    test('recente ocupa pelo menos 60% dos pontos do eixo', () {
      // 22 dias antigos x 2 talhoes = 44 sessoes antigas vs 6 recentes.
      final d = BiAdapters.cadenciaSanidade(build(oldDays: 22, recentDays: 6));
      final share = (d.points.length - d.recentFromIndex) / d.points.length;

      expect(share, greaterThanOrEqualTo(0.6));
      expect(d.hasFocusSplit, isTrue);
    });

    test('sem agregação, 44 sessões antigas esmagavam o recente para ~12%', () {
      // Prova de que o problema existia: 6 / (44 + 6) = 0.12.
      const semAgregacao = 6 / (44 + 6);
      expect(semAgregacao, lessThan(0.2));
    });

    test('as sessões dos últimos 7 dias ficam intactas, nunca agregadas', () {
      final d = BiAdapters.cadenciaSanidade(build(oldDays: 22, recentDays: 6));
      final recentes = d.points.sublist(d.recentFromIndex);

      expect(recentes.length, 6);
      expect(recentes.every((p) => !p.aggregated), isTrue);
      expect(recentes.every((p) => p.label.startsWith('T-')), isTrue);
    });

    test('os blocos antigos são marcados como agregados', () {
      final d = BiAdapters.cadenciaSanidade(build(oldDays: 22, recentDays: 6));
      final antigos = d.points.sublist(0, d.recentFromIndex);

      expect(antigos, isNotEmpty);
      expect(antigos.every((p) => p.aggregated), isTrue);
      expect(antigos.every((p) => p.period!.contains('sessões agregadas')), isTrue);
    });

    test('a agregação não perde nem inventa maçãs', () {
      final batches = build(oldDays: 22, recentDays: 6);
      final totalMacas = batches.fold<int>(0, (s, b) => s + b.apples.length);
      final d = BiAdapters.cadenciaSanidade(batches);

      // period termina em "· N maçãs" para todos os pontos.
      int somaPontos = 0;
      for (final p in d.points) {
        somaPontos += int.parse(RegExp(r'(\d+) maçãs').firstMatch(p.period!)!.group(1)!);
      }
      expect(somaPontos, totalMacas);
      expect(totalMacas, 22 * 2 + 6);
    });

    test('a ordem cronológica mantém-se: contexto antes, foco depois', () {
      final d = BiAdapters.cadenciaSanidade(build(oldDays: 22, recentDays: 6));
      expect(d.recentFromIndex, greaterThan(0));
      expect(d.recentFromIndex, lessThan(d.points.length));
    });

    test('só com dados recentes não há divisão nem agregação', () {
      final d = BiAdapters.cadenciaSanidade(build(oldDays: 0, recentDays: 6));

      expect(d.recentFromIndex, 0);
      expect(d.hasFocusSplit, isFalse);
      expect(d.points.every((p) => !p.aggregated), isTrue);
    });

    test('pouco histórico não é agregado desnecessariamente', () {
      // 2 dias antigos x 2 talhoes = 4 sessoes, com 6 recentes ja da 60%.
      final d = BiAdapters.cadenciaSanidade(build(oldDays: 2, recentDays: 6));
      expect(d.points.every((p) => !p.aggregated), isTrue);
      expect(d.points.length, 4 + 6);
    });

    test('sem dados devolve payload vazio, sem rebentar', () {
      final d = BiAdapters.cadenciaSanidade(const []);
      expect(d.points, isEmpty);
      expect(d.hasFocusSplit, isFalse);
    });
  });
}
