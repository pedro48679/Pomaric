import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:dashboard/models/models.dart';
import 'package:dashboard/providers/dashboard_provider.dart';

// Reproduz o bug do botão 7d/30d: `getBatches` agrupa as maçãs por
// LOCALIZAÇÃO, por isso um lote acumula maçãs de todas as datas e `batch.date`
// é só o timestamp da maçã mais recente desse sítio. O filtro antigo testava
// `b.date.isAfter(threshold)`, logo bastava uma maçã recente para o lote
// entrar inteiro, e 7d e 30d devolviam exatamente o mesmo.

Apple appleAt(String id, DateTime ts) =>
    Apple(id: id, frames: const [], location: 'Setor A', timestamp: ts);

/// Um único lote (uma localização) com maçãs espalhadas por várias datas,
/// como acontece em produção.
Batch locationBatch(List<Apple> apples) {
  final sorted = [...apples]..sort((a, b) => b.timestamp.compareTo(a.timestamp));
  return Batch(
    id: 'LT-SETOR_A',
    name: 'Lote Setor A',
    date: sorted.first.timestamp, // maçã mais recente, tal como getBatches
    apples: sorted,
    location: 'Setor A',
  );
}

void main() {
  final now = DateTime.now();

  // Cenário reportado: maçãs entre há 12 e há 5 dias, todas no mesmo sítio.
  final antiga12 = appleAt('a12', now.subtract(const Duration(days: 12)));
  final antiga9 = appleAt('a9', now.subtract(const Duration(days: 9)));
  final recente5 = appleAt('r5', now.subtract(const Duration(days: 5)));
  final recente2 = appleAt('r2', now.subtract(const Duration(days: 2)));

  final batches = [locationBatch([antiga12, antiga9, recente5, recente2])];

  ProviderContainer containerWith(String range) {
    final c = ProviderContainer();
    addTearDown(c.dispose);
    c.read(availableBatchesProvider.notifier).setBatches(batches);
    c.read(dateRangeFilterProvider.notifier).setRange(range);
    return c;
  }

  List<String> appleIds(List<Batch> bs) =>
      bs.expand((b) => b.apples).map((a) => a.id).toList()..sort();

  group('filteredBatchesProvider (botão 7d/30d)', () {
    test('7d deixa de fora as maçãs com mais de 7 dias', () {
      final c = containerWith('7d');
      expect(appleIds(c.read(filteredBatchesProvider)), ['r2', 'r5']);
    });

    test('30d inclui todas as maçãs da janela', () {
      final c = containerWith('30d');
      expect(appleIds(c.read(filteredBatchesProvider)), ['a12', 'a9', 'r2', 'r5']);
    });

    test('7d e 30d dão resultados DIFERENTES (o bug era serem iguais)', () {
      final sete = appleIds(containerWith('7d').read(filteredBatchesProvider));
      final trinta = appleIds(containerWith('30d').read(filteredBatchesProvider));
      expect(sete, isNot(equals(trinta)));
      expect(sete.length, lessThan(trinta.length));
    });

    test('totalApples do lote reflete a janela (os KPIs mudam)', () {
      expect(containerWith('7d').read(filteredBatchesProvider).first.totalApples, 2);
      expect(containerWith('30d').read(filteredBatchesProvider).first.totalApples, 4);
    });

    test('lote sem maçãs na janela é removido', () {
      final c = ProviderContainer();
      addTearDown(c.dispose);
      c.read(availableBatchesProvider.notifier).setBatches([
        locationBatch([appleAt('velha', now.subtract(const Duration(days: 40)))]),
      ]);
      c.read(dateRangeFilterProvider.notifier).setRange('30d');
      expect(c.read(filteredBatchesProvider), isEmpty);
    });
  });

  group('chapter23BatchesProvider (janela fixa de 7 dias)', () {
    test('ignora o botão: fica nos 7 dias mesmo com 30d selecionado', () {
      final com30 = appleIds(containerWith('30d').read(chapter23BatchesProvider));
      final com7 = appleIds(containerWith('7d').read(chapter23BatchesProvider));
      expect(com30, ['r2', 'r5']);
      expect(com30, equals(com7));
    });
  });
}
