import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:printing/printing.dart';
import 'package:fl_chart/fl_chart.dart';
import '../models/models.dart';
import '../providers/auth_provider.dart';
import '../providers/dashboard_provider.dart';
import '../utils/constants.dart';
import '../widgets/apple_card.dart';
import '../widgets/donut_chart_widget.dart';
import '../services/pdf_service.dart';
import 'grad_cam_view.dart';
import 'batch_dashboard.dart';
import 'global_dashboard.dart';
import '../widgets/apple_grid_view.dart';
import '../widgets/tech_grid_background.dart';

class ShadowPieTouchedIndexNotifier extends Notifier<int> {
  @override
  int build() => -1;

  void setIndex(int value) {
    state = value;
  }
}

final shadowPieTouchedIndexProvider = NotifierProvider<ShadowPieTouchedIndexNotifier, int>(
  ShadowPieTouchedIndexNotifier.new,
);

class DashboardScreen extends ConsumerWidget {
  const DashboardScreen({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currentPage = ref.watch(currentPageProvider);
    ref.watch(loadDataFutureProvider);

    return TechGridBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        drawer: Drawer(
          backgroundColor: AppColors.surface,
          child: _buildRightSidebar(context, ref),
        ),
        body: Column(
          children: [
            if (currentPage != 'Tapete') _buildHeader(context, ref),
            Expanded(
              child: currentPage == 'Visão Geral'
                  ? const GlobalDashboard()
                : currentPage == 'Lote Dashboard'
                ? const BatchDashboard()
                : currentPage == 'IoT & Edge'
                ? _buildIotDashboard(context, ref)
                : currentPage == 'MLOps & IA'
                ? _buildMLOpsDashboard(context, ref)
                : currentPage == 'Matriz (Grelha)' ||
                      currentPage == 'Lote Específico'
                ? _buildDashboardContent(context, ref)
                : currentPage == 'Reports'
                ? _buildReportsContent(context, ref)
                : currentPage == 'Tapete'
                ? const GradCamOperatorView()
                : _buildPlaceholderContent(currentPage),
          ),
        ],
      ),
    ),
  );
}

  Widget _buildHeader(BuildContext context, WidgetRef ref) {
    final currentBatch = ref.watch(batchProvider);
    final availableBatches = ref.watch(availableBatchesProvider);
    final currentPage = ref.watch(currentPageProvider);
    final String formattedDate = DateFormat(
      'dd/MM/yyyy HH:mm',
    ).format(DateTime.now());

    final user = ref.watch(authProvider);
    final isAdmin = user?.role == UserRole.admin;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 16.0),
      color: AppColors.surface,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              if (isAdmin)
                Builder(
                  builder: (context) => IconButton(
                    icon: const Icon(Icons.menu, color: Colors.white),
                    onPressed: () => Scaffold.of(context).openDrawer(),
                  ),
                ),
              if (isAdmin) const SizedBox(width: 16),
              Text(
                formattedDate,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w500,
                  color: AppColors.textSecondary,
                ),
              ),
              const SizedBox(width: 24),
              _buildIotStatusIndicator(),
            ],
          ),
          Row(
            children: [
              if (isAdmin) ...[
                if (currentPage != 'Visão Geral' && currentBatch != null) ...[
                  const Icon(
                    Icons.location_on,
                    color: Colors.blueAccent,
                    size: 20,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    currentBatch.location,
                    style: const TextStyle(color: Colors.white70, fontSize: 14),
                  ),
                  const SizedBox(width: 24),
                ],
                Builder(
                  builder: (context) {
                    final activeCount = availableBatches.where((b) => b.isActive).length;
                    if (activeCount == 0) return const SizedBox.shrink();
                    return Container(
                      margin: const EdgeInsets.only(right: 24),
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: AppColors.primary.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: AppColors.primary.withValues(alpha: 0.3)),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.inventory_2, color: AppColors.primary, size: 16),
                          const SizedBox(width: 8),
                          Text(
                            '$activeCount Lote${activeCount > 1 ? 's' : ''} Ativo${activeCount > 1 ? 's' : ''}',
                            style: const TextStyle(color: AppColors.primary, fontWeight: FontWeight.bold, fontSize: 13),
                          ),
                        ],
                      ),
                    );
                  },
                ),
                Text(
                  currentPage == 'Visão Geral' ? 'Visão: ' : 'Lote Ativo: ',
                  style: const TextStyle(color: Colors.white54),
                ),
                const SizedBox(width: 8),
                DropdownButton<String>(
                  dropdownColor: AppColors.surface,
                  value: currentPage == 'Visão Geral' ? 'Global' : currentBatch?.id,
                  underline: const SizedBox(),
                  icon: const Icon(
                    Icons.arrow_drop_down,
                    color: AppColors.healthy,
                  ),
                  onChanged: (String? newValue) {
                    if (newValue != null) {
                      if (newValue == 'Global') {
                        ref.read(currentPageProvider.notifier).setPage('Visão Geral');
                      } else {
                        final b = availableBatches.firstWhere((batch) => batch.id == newValue);
                        ref.read(batchProvider.notifier).setBatch(b);
                        ref.read(currentPageProvider.notifier).setPage('Lote Dashboard');
                      }
                    }
                  },
                  items: [
                    const DropdownMenuItem<String>(
                      value: 'Global',
                      child: Text(
                        'Global',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    ...availableBatches.map<DropdownMenuItem<String>>((Batch b) {
                      return DropdownMenuItem<String>(
                        value: b.id,
                        child: Text(
                          b.id,
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      );
                    }).toList(),
                  ],
                ),
              ] else ...[
                ElevatedButton.icon(
                  icon: const Icon(Icons.touch_app, size: 16),
                  label: const Text('Triagem Manual'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary.withValues(alpha: 0.2),
                    foregroundColor: AppColors.primary,
                    elevation: 0,
                  ),
                  onPressed: () => ref.read(currentPageProvider.notifier).setPage('Tapete'),
                ),
                const SizedBox(width: 8),
                ElevatedButton.icon(
                  icon: const Icon(Icons.logout, size: 16),
                  label: const Text('Sair'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.white10,
                    foregroundColor: Colors.white,
                    elevation: 0,
                  ),
                  onPressed: () => ref.read(authProvider.notifier).logout(),
                ),
              ]
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildIotStatusIndicator() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.green.withOpacity(0.1),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.green.withOpacity(0.5)),
      ),
      child: const Row(
        children: [
          Icon(Icons.wifi_tethering, color: Colors.green, size: 16),
          SizedBox(width: 8),
          Text(
            'IoT CAMERA: ONLINE',
            style: TextStyle(
              color: Colors.green,
              fontSize: 10,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRightSidebar(BuildContext context, WidgetRef ref) {
    final currentPage = ref.watch(currentPageProvider);
    final user = ref.watch(authProvider);

    if (user == null) return const SizedBox(); // safety fallback

    final isAdmin = user.role == UserRole.admin;

    return Container(
      width: 250,
      color: AppColors.surface,
      child: Column(
        children: [
          const SizedBox(height: 40),
          CircleAvatar(
            radius: 40,
            backgroundColor: isAdmin ? Colors.blueAccent : AppColors.healthy,
            child: const Icon(Icons.person, size: 40, color: Colors.white),
          ),
          const SizedBox(height: 16),
          Text(
            user.username.toUpperCase(),
            style: const TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            isAdmin ? 'Administrador' : 'Operador de Linha',
            style: const TextStyle(color: Colors.greenAccent, fontSize: 12),
          ),
          const SizedBox(height: 40),
          const Divider(color: Colors.white24),

          if (isAdmin)
            _buildSidebarItem(
              context,
              ref,
              'Visão Geral',
              Icons.home,
              currentPage,
            ),
          _buildSidebarItem(
            context,
            ref,
            'Tapete',
            Icons.precision_manufacturing,
            currentPage,
          ),
          _buildSidebarItem(
            context,
            ref,
            'Matriz (Grelha)',
            Icons.grid_view,
            currentPage,
          ),
          if (isAdmin)
            _buildSidebarItem(
              context,
              ref,
              'IoT & Edge',
              Icons.camera_alt,
              currentPage,
            ),
          if (isAdmin)
            _buildSidebarItem(
              context,
              ref,
              'MLOps & IA',
              Icons.psychology,
              currentPage,
            ),
          if (isAdmin)
            _buildSidebarItem(
              context,
              ref,
              'Relatório',
              Icons.picture_as_pdf,
              currentPage,
            ),
          if (isAdmin)
            _buildSidebarItem(
              context,
              ref,
              'Settings',
              Icons.settings,
              currentPage,
            ),

          const Spacer(),
          const Divider(color: Colors.white24),
          ListTile(
            leading: const Icon(Icons.logout, color: Colors.redAccent),
            title: const Text(
              'Logout',
              style: TextStyle(color: Colors.redAccent),
            ),
            onTap: () {
              ref.read(sessionActiveProvider.notifier).setActive(false);
              ref.read(authProvider.notifier).logout();
            },
          ),
          const SizedBox(height: 20),
        ],
      ),
    );
  }


Widget _buildModernKpiCard(
    String title,
    String value,
    IconData icon,
    Color color, [
    String? subtitle,
    bool expand = true,
  ]) {
    Widget card = Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border(left: BorderSide(color: color, width: 4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 32),
          const SizedBox(height: 16),
          Text(
            title,
            style: const TextStyle(color: Colors.white54, fontSize: 16),
          ),
          const SizedBox(height: 8),
          Text(
            value,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 32,
              fontWeight: FontWeight.bold,
            ),
          ),
          if (subtitle != null) ...[
            const SizedBox(height: 8),
            Text(
              subtitle,
              style: TextStyle(
                color: subtitle.contains('▲')
                    ? Colors.greenAccent
                    : (subtitle.contains('▼')
                          ? Colors.redAccent
                          : Colors.white54),
                fontSize: 12,
              ),
            ),
          ],
        ],
      ),
    );

    return expand ? Expanded(child: card) : card;
  }

  Widget _buildSidebarItem(
    BuildContext context,
    WidgetRef ref,
    String title,
    IconData icon,
    String current,
  ) {
    final bool isSelected = title == current;
    return Container(
      color: isSelected ? AppColors.background : Colors.transparent,
      child: ListTile(
        leading: Icon(
          icon,
          color: isSelected ? AppColors.healthy : Colors.white70,
        ),
        title: Text(
          title,
          style: TextStyle(
            color: isSelected ? AppColors.textPrimary : Colors.white70,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
          ),
        ),
        onTap: () {
          ref.read(currentPageProvider.notifier).setPage(title);
        },
      ),
    );
  }

  Widget _buildDashboardContent(BuildContext context, WidgetRef ref) {
    final batch = ref.watch(batchProvider);
    final filteredApples = ref.watch(filteredApplesProvider);
    final filter = ref.watch(selectedConditionFilterProvider);
    final user = ref.watch(authProvider);
    final isAdmin = user?.role == UserRole.admin;

    if (batch == null) return const Center(child: CircularProgressIndicator());

    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (isAdmin)
            Padding(
              padding: const EdgeInsets.only(bottom: 16.0),
              child: ElevatedButton.icon(
                onPressed: () => ref
                    .read(currentPageProvider.notifier)
                    .setPage('Lote Dashboard'),
                icon: const Icon(Icons.arrow_back),
                label: const Text('Voltar ao Lote'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.grey[800],
                ),
              ),
            ),
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Left side: Analytics
                const Expanded(flex: 2, child: DonutChartWidget()),
                const SizedBox(width: 16),
                // Right side: Apple Grid
                Expanded(
                  flex: 5,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'Matriz de Inspeção: ${batch.id}',
                            style: const TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                              color: AppColors.textPrimary,
                            ),
                          ),
                          Text(
                            filter.isEmpty
                                ? 'A mostrar todos (${filteredApples.length})'
                                : 'Filtrado por: ${filter.join(', ')} (${filteredApples.length})',
                            style: const TextStyle(
                              color: AppColors.textSecondary,
                              fontSize: 14,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      Expanded(
                        child: AppleGridView(apples: filteredApples),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildReportsContent(BuildContext context, WidgetRef ref) {
    final batch = ref.watch(batchProvider);
    if (batch == null) return const Center(child: Text('Nenhum lote selecionado.'));

    return Container(
      color: Colors.grey[900], // Dark background for PDF viewer area
      child: PdfPreview(
        build: (format) => PdfService.generatePdfBytes(batch),
        canChangeOrientation: false,
        canChangePageFormat: false,
        canDebug: false,
        pdfFileName: 'relatorio_${batch.id}.pdf',
        useActions: true,
      ),
    );
  }

  DataCell _buildClickableAppleIdCell(
    BuildContext context,
    WidgetRef ref,
    String id,
    String condition,
  ) {
    return DataCell(
      InkWell(
        onTap: () {
          ref.read(currentPageProvider.notifier).setPage('Matriz (Grelha)');

          final mockApple = Apple(
            id: id,
            frames: [
              FrameData(
                id: 1,
                url: 'https://picsum.photos/200?random=$id-1',
                diseaseSum: 0.91,
                probabilities: {condition: 0.91, 'Healthy': 0.09},
              ),
              FrameData(
                id: 2,
                url: 'https://picsum.photos/200?random=$id-2',
                diseaseSum: 0.85,
                probabilities: {condition: 0.85, 'Healthy': 0.15},
              ),
              FrameData(
                id: 3,
                url: 'https://picsum.photos/200?random=$id-3',
                diseaseSum: 0.60,
                probabilities: {condition: 0.60, 'Healthy': 0.40},
              ),
            ],
          );

          Future.delayed(const Duration(milliseconds: 100), () {
            if (!context.mounted) return;
            AppleCard.showAppleDetails(context, mockApple);
          });
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8.0),
          child: Text(
            id,
            style: const TextStyle(
              color: Colors.blueAccent,
              decoration: TextDecoration.underline,
              decorationColor: Colors.blueAccent,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildMLOpsDashboard(BuildContext context, WidgetRef ref) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(32.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'MLOps & Ciclo de Vida da IA',
            style: TextStyle(
              color: Colors.white,
              fontSize: 32,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Gestão de Active Learning, Testes A/B e Retreino de Modelos',
            style: TextStyle(color: Colors.white54, fontSize: 18),
          ),
          const SizedBox(height: 32),

          // KPIs Topo
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _buildModernKpiCard(
                  'Média de Incerteza',
                  '48.3%',
                  Icons.psychology_alt,
                  Colors.amber,
                  'Média na faixa [25-75%] excluindo outliers',
                  true,
                ),
                const SizedBox(width: 16),
                _buildModernKpiCard(
                  'Dataset de Retreino',
                  '1,452 Imagens',
                  Icons.folder_special,
                  Colors.purpleAccent,
                  'Novos casos limite capturados (+45 hoje)',
                  true,
                ),
                const SizedBox(width: 16),
                _buildModernKpiCard(
                  'Shadow Mode V2',
                  '+4.1% Precisão',
                  Icons.compare,
                  Colors.cyan,
                  'Melhoria simulada vs Modelo V1 (Tapete)',
                  true,
                ),
              ],
            ),
          ),

          const SizedBox(height: 32),

          // Secção Minidashboard: Título da Secção de Gráficos
          const Text(
            'Minidashboard: Análise Comparativa Shadow CNN',
            style: TextStyle(
              color: Colors.white,
              fontSize: 22,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 16),

          // Row com os 3 gráficos do Minidashboard
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 1. Gráfico de Timeline de Precisão (LineChart)
              Expanded(
                child: _buildTimelineChartCard(),
              ),
              const SizedBox(width: 16),
              // 2. Gráfico de Confiança Delta (BarChart)
              Expanded(
                child: _buildConfidenceDeltaChartCard(),
              ),
              const SizedBox(width: 16),
              // 3. Gráfico de Consenso e Auditoria (PieChart)
              Expanded(
                child: _buildAgreementPieChartCard(context, ref),
              ),
            ],
          ),

          const SizedBox(height: 32),

          // Painel Inferior (Ação Requerida + Logs Recentes)
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Ação Requerida (Deploy V2) - Flex 2
              Expanded(
                flex: 2,
                child: _buildActionRequiredCard(),
              ),
              const SizedBox(width: 16),
              // Logs Recentes - Flex 3
              Expanded(
                flex: 3,
                child: _buildRecentLogsCard(context, ref),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildTimelineChartCard() {
    return Container(
      height: 350,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.glassBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Precisão Temporal (Timeline)',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                ),
              ),
              Row(
                children: [
                  Container(width: 8, height: 8, color: AppColors.primary),
                  const SizedBox(width: 4),
                  const Text('V1', style: TextStyle(color: Colors.white70, fontSize: 10)),
                  const SizedBox(width: 8),
                  Container(width: 8, height: 8, color: AppColors.accent),
                  const SizedBox(width: 4),
                  const Text('V2', style: TextStyle(color: Colors.white70, fontSize: 10)),
                ],
              )
            ],
          ),
          const SizedBox(height: 20),
          Expanded(
            child: LineChart(
              LineChartData(
                minY: 80,
                maxY: 100,
                gridData: FlGridData(
                  show: true,
                  drawVerticalLine: false,
                  getDrawingHorizontalLine: (value) => FlLine(
                    color: Colors.white.withOpacity(0.05),
                    strokeWidth: 1,
                  ),
                ),
                titlesData: FlTitlesData(
                  show: true,
                  topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  leftTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 35,
                      getTitlesWidget: (value, meta) {
                        if (value % 5 == 0) {
                          return Text(
                            '${value.toInt()}%',
                            style: const TextStyle(color: Colors.white30, fontSize: 10),
                          );
                        }
                        return const SizedBox();
                      },
                    ),
                  ),
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      getTitlesWidget: (value, meta) {
                        const style = TextStyle(color: Colors.white30, fontSize: 10);
                        String text = '';
                        switch (value.toInt()) {
                          case 0: text = '09:00'; break;
                          case 1: text = '10:00'; break;
                          case 2: text = '11:00'; break;
                          case 3: text = '12:00'; break;
                          case 4: text = '13:00'; break;
                          case 5: text = '14:00'; break;
                        }
                        return SideTitleWidget(meta: meta, child: Text(text, style: style));
                      },
                    ),
                  ),
                ),
                borderData: FlBorderData(show: false),
                lineBarsData: [
                  LineChartBarData(
                    spots: const [
                      FlSpot(0, 85.2),
                      FlSpot(1, 86.0),
                      FlSpot(2, 85.5),
                      FlSpot(3, 87.1),
                      FlSpot(4, 86.8),
                      FlSpot(5, 87.5),
                    ],
                    isCurved: true,
                    color: AppColors.primary,
                    barWidth: 3,
                    isStrokeCapRound: true,
                    dotData: const FlDotData(show: true),
                    belowBarData: BarAreaData(
                      show: true,
                      color: AppColors.primary.withOpacity(0.1),
                    ),
                  ),
                  LineChartBarData(
                    spots: const [
                      FlSpot(0, 88.5),
                      FlSpot(1, 90.1),
                      FlSpot(2, 91.4),
                      FlSpot(3, 92.5),
                      FlSpot(4, 93.8),
                      FlSpot(5, 94.6),
                    ],
                    isCurved: true,
                    color: AppColors.accent,
                    barWidth: 3,
                    isStrokeCapRound: true,
                    dotData: const FlDotData(show: true),
                    belowBarData: BarAreaData(
                      show: true,
                      color: AppColors.accent.withOpacity(0.1),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildConfidenceDeltaChartCard() {
    return Container(
      height: 350,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.glassBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Diferença de Confiança (V2 - V1)',
            style: TextStyle(
              color: Colors.white,
              fontSize: 15,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 4),
          const Text(
            'Melhoria líquida de confiança do modelo Shadow',
            style: TextStyle(color: Colors.white30, fontSize: 11),
          ),
          const SizedBox(height: 20),
          Expanded(
            child: BarChart(
              BarChartData(
                alignment: BarChartAlignment.spaceAround,
                maxY: 10,
                barTouchData: BarTouchData(
                  touchTooltipData: BarTouchTooltipData(
                    getTooltipColor: (_) => const Color(0xFF1A1A2E),
                    getTooltipItem: (group, groupIndex, rod, rodIndex) {
                      return BarTooltipItem(
                        '+${rod.toY.toStringAsFixed(1)}%',
                        const TextStyle(color: AppColors.primary, fontWeight: FontWeight.bold),
                      );
                    },
                  ),
                ),
                titlesData: FlTitlesData(
                  show: true,
                  topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  leftTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 30,
                      getTitlesWidget: (value, meta) {
                        return Text(
                          '+${value.toInt()}%',
                          style: const TextStyle(color: Colors.white30, fontSize: 9),
                        );
                      },
                    ),
                  ),
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      getTitlesWidget: (value, meta) {
                        const style = TextStyle(color: Colors.white54, fontSize: 9, fontWeight: FontWeight.bold);
                        String text = '';
                        switch (value.toInt()) {
                          case 0: text = 'Healthy'; break;
                          case 1: text = 'Rot'; break;
                          case 2: text = 'Scab'; break;
                          case 3: text = 'Blotch'; break;
                          case 4: text = 'Anthrac'; break;
                        }
                        return SideTitleWidget(meta: meta, child: Text(text, style: style));
                      },
                    ),
                  ),
                ),
                gridData: FlGridData(
                  show: true,
                  drawVerticalLine: false,
                  getDrawingHorizontalLine: (value) => FlLine(
                    color: Colors.white.withOpacity(0.05),
                    strokeWidth: 1,
                  ),
                ),
                borderData: FlBorderData(show: false),
                barGroups: [
                  BarChartGroupData(
                    x: 0,
                    barRods: [
                      BarChartRodData(
                        toY: 2.1,
                        gradient: const LinearGradient(
                          colors: [AppColors.primary, AppColors.accent],
                          begin: Alignment.bottomCenter,
                          end: Alignment.topCenter,
                        ),
                        width: 14,
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ],
                  ),
                  BarChartGroupData(
                    x: 1,
                    barRods: [
                      BarChartRodData(
                        toY: 6.5,
                        gradient: const LinearGradient(
                          colors: [AppColors.primary, AppColors.accent],
                          begin: Alignment.bottomCenter,
                          end: Alignment.topCenter,
                        ),
                        width: 14,
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ],
                  ),
                  BarChartGroupData(
                    x: 2,
                    barRods: [
                      BarChartRodData(
                        toY: 8.3,
                        gradient: const LinearGradient(
                          colors: [AppColors.primary, AppColors.accent],
                          begin: Alignment.bottomCenter,
                          end: Alignment.topCenter,
                        ),
                        width: 14,
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ],
                  ),
                  BarChartGroupData(
                    x: 3,
                    barRods: [
                      BarChartRodData(
                        toY: 7.2,
                        gradient: const LinearGradient(
                          colors: [AppColors.primary, AppColors.accent],
                          begin: Alignment.bottomCenter,
                          end: Alignment.topCenter,
                        ),
                        width: 14,
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ],
                  ),
                  BarChartGroupData(
                    x: 4,
                    barRods: [
                      BarChartRodData(
                        toY: 5.0,
                        gradient: const LinearGradient(
                          colors: [AppColors.primary, AppColors.accent],
                          begin: Alignment.bottomCenter,
                          end: Alignment.topCenter,
                        ),
                        width: 14,
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAgreementPieChartCard(BuildContext context, WidgetRef ref) {
    final touchedIndex = ref.watch(shadowPieTouchedIndexProvider);

    return Container(
      height: 350,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.glassBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Consenso & Divergência V1/V2',
            style: TextStyle(
              color: Colors.white,
              fontSize: 15,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 4),
          const Text(
            'Correlações de classificação entre modelos',
            style: TextStyle(color: Colors.white30, fontSize: 11),
          ),
          const SizedBox(height: 20),
          Expanded(
            child: Stack(
              children: [
                PieChart(
                  PieChartData(
                    pieTouchData: PieTouchData(
                      touchCallback: (FlTouchEvent event, pieTouchResponse) {
                        if (!event.isInterestedForInteractions ||
                            pieTouchResponse == null ||
                            pieTouchResponse.touchedSection == null) {
                          return;
                        }
                        if (event is FlTapUpEvent) {
                          final index = pieTouchResponse.touchedSection!.touchedSectionIndex;
                          if (index >= 0 && index < 3) {
                            ref.read(shadowPieTouchedIndexProvider.notifier).setIndex(
                              touchedIndex == index ? -1 : index,
                            );
                          }
                        }
                      },
                    ),
                    borderData: FlBorderData(show: false),
                    sectionsSpace: 4,
                    centerSpaceRadius: 50,
                    sections: [
                      PieChartSectionData(
                        color: AppColors.healthy,
                        value: 82.0,
                        title: '82%',
                        radius: touchedIndex == 0 ? 46.0 : 38.0,
                        titleStyle: TextStyle(
                          fontSize: touchedIndex == 0 ? 16.0 : 12.0,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                          shadows: const [Shadow(color: Colors.black, blurRadius: 4)],
                        ),
                      ),
                      PieChartSectionData(
                        color: AppColors.primary,
                        value: 12.0,
                        title: '12%',
                        radius: touchedIndex == 1 ? 46.0 : 38.0,
                        titleStyle: TextStyle(
                          fontSize: touchedIndex == 1 ? 16.0 : 12.0,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                          shadows: const [Shadow(color: Colors.black, blurRadius: 4)],
                        ),
                      ),
                      PieChartSectionData(
                        color: AppColors.scab,
                        value: 6.0,
                        title: '6%',
                        radius: touchedIndex == 2 ? 46.0 : 38.0,
                        titleStyle: TextStyle(
                          fontSize: touchedIndex == 2 ? 16.0 : 12.0,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                          shadows: const [Shadow(color: Colors.black, blurRadius: 4)],
                        ),
                      ),
                    ],
                  ),
                ),
                const Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        'Total Casos',
                        style: TextStyle(color: Colors.white30, fontSize: 10),
                      ),
                      Text(
                        '100%',
                        style: TextStyle(
                          color: Colors.white70,
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          // Legends
          Column(
            children: [
              _buildPieLegendRow('Consenso Geral', '82%', AppColors.healthy, touchedIndex == 0),
              const SizedBox(height: 4),
              _buildPieLegendRow('V2 Superior (Correção)', '12%', AppColors.primary, touchedIndex == 1),
              const SizedBox(height: 4),
              _buildPieLegendRow('Auditoria (Divergente)', '6%', AppColors.scab, touchedIndex == 2),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildPieLegendRow(String label, String value, Color color, bool isTouched) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: isTouched ? color.withOpacity(0.15) : Colors.transparent,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(color: color, shape: BoxShape.circle),
              ),
              const SizedBox(width: 8),
              Text(
                label,
                style: TextStyle(
                  color: isTouched ? Colors.white : Colors.white70,
                  fontSize: 11,
                  fontWeight: isTouched ? FontWeight.bold : FontWeight.normal,
                ),
              ),
            ],
          ),
          Text(
            value,
            style: TextStyle(
              color: isTouched ? Colors.white : Colors.white70,
              fontSize: 11,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActionRequiredCard() {
    return Container(
      height: 380,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.black,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: Colors.purpleAccent.withOpacity(0.3),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(
            Icons.model_training,
            color: Colors.purpleAccent,
            size: 44,
          ),
          const SizedBox(height: 16),
          const Text(
            'Ação Requerida',
            style: TextStyle(
              color: Colors.purpleAccent,
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'O volume do Dataset de Retreino atingiu a massa crítica. O Modelo V2 mostra superioridade consistente em "Blotch" e "Scab".',
            style: TextStyle(color: Colors.white54, fontSize: 13),
          ),
          const Spacer(),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: () {},
              icon: const Icon(Icons.rocket_launch),
              label: const Text('APROVAR DEPLOY DO V2'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.purpleAccent,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 18),
                textStyle: const TextStyle(
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1,
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: TextButton(
              onPressed: () {},
              child: const Text(
                'Apenas iniciar Fine-Tuning de novo modelo V3',
                style: TextStyle(color: Colors.white54, fontSize: 12),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRecentLogsCard(BuildContext context, WidgetRef ref) {
    return Container(
      height: 380,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.glassBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Logs Recentes: Limiar de Decisão Crítico (~70%)',
            style: TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 16),
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.vertical,
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: DataTable(
                  headingTextStyle: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
                  dataTextStyle: const TextStyle(color: Colors.white70),
                  columns: const [
                    DataColumn(label: Text('ID Maçã')),
                    DataColumn(label: Text('Timestamp')),
                    DataColumn(label: Text('Confiança Edge')),
                    DataColumn(label: Text('Suspeita Edge')),
                    DataColumn(label: Text('Decisão Nuvem (CNN5)')),
                  ],
                  rows: [
                    DataRow(
                      cells: [
                        _buildClickableAppleIdCell(context, ref, 'APL-8492', 'Rot'),
                        DataCell(Text('14:32:01')),
                        DataCell(
                          Text('68.2%', style: TextStyle(color: Colors.amber)),
                        ),
                        DataCell(Text('Rot')),
                        DataCell(
                          Text(
                            'Rot (91%)',
                            style: TextStyle(color: Colors.redAccent),
                          ),
                        ),
                      ],
                    ),
                    DataRow(
                      cells: [
                        _buildClickableAppleIdCell(
                          context,
                          ref,
                          'APL-8493',
                          'Healthy',
                        ),
                        DataCell(Text('14:32:05')),
                        DataCell(
                          Text('72.4%', style: TextStyle(color: Colors.amber)),
                        ),
                        DataCell(Text('Healthy')),
                        DataCell(
                          Text(
                            'Healthy (98%)',
                            style: TextStyle(color: Colors.greenAccent),
                          ),
                        ),
                      ],
                    ),
                    DataRow(
                      cells: [
                        _buildClickableAppleIdCell(
                          context,
                          ref,
                          'APL-8497',
                          'Scab',
                        ),
                        DataCell(Text('14:32:18')),
                        DataCell(
                          Text('65.9%', style: TextStyle(color: Colors.amber)),
                        ),
                        DataCell(Text('Blotch')),
                        DataCell(
                          Text(
                            'Scab (85%)',
                            style: TextStyle(color: Colors.orangeAccent),
                          ),
                        ),
                      ],
                    ),
                    DataRow(
                      cells: [
                        _buildClickableAppleIdCell(
                          context,
                          ref,
                          'APL-8501',
                          'Blotch',
                        ),
                        DataCell(Text('14:33:42')),
                        DataCell(
                          Text('74.1%', style: TextStyle(color: Colors.amber)),
                        ),
                        DataCell(Text('Healthy')),
                        DataCell(
                          Text(
                            'Blotch (62%)',
                            style: TextStyle(color: Colors.orangeAccent),
                          ),
                        ),
                      ],
                    ),
                    DataRow(
                      cells: [
                        _buildClickableAppleIdCell(context, ref, 'APL-8509', 'Rot'),
                        DataCell(Text('14:35:11')),
                        DataCell(
                          Text('69.5%', style: TextStyle(color: Colors.amber)),
                        ),
                        DataCell(Text('Rot')),
                        DataCell(
                          Text(
                            'Rot (88%)',
                            style: TextStyle(color: Colors.redAccent),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildIotDashboard(BuildContext context, WidgetRef ref) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(32.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Controlo de Hardware (Edge AI)',
            style: TextStyle(
              color: Colors.white,
              fontSize: 32,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Gestão da telemetria do Raspberry Pi 4 e pipeline de inferência no Edge',
            style: TextStyle(color: Colors.white54, fontSize: 18),
          ),
          const SizedBox(height: 32),

          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  flex: 1,
                  child: Column(
                    children: [
                      _buildModernKpiCard(
                        'Carga CPU (Pi 4)',
                        '68%',
                        Icons.memory,
                        Colors.blue,
                        'Estável',
                        false,
                      ),
                      const SizedBox(height: 16),
                      _buildModernKpiCard(
                        'Temp. SoC',
                        '62°C',
                        Icons.thermostat,
                        Colors.orange,
                        'Aviso: Estrangulamento térmico leve',
                        false,
                      ),
                      const SizedBox(height: 16),
                      _buildModernKpiCard(
                        'Memória RAM',
                        '2.1 / 4 GB',
                        Icons.storage,
                        Colors.purpleAccent,
                        'Modelo MobileNetV2 em memória',
                        false,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 16),

                // JANELA DE TESTE CENTRAL
                Expanded(
                  flex: 2,
                  child: Container(
                    decoration: BoxDecoration(
                      color: Colors.black,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: Colors.blueAccent.withValues(alpha: 0.3),
                      ),
                    ),
                    child: Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(
                            Icons.center_focus_weak,
                            color: Colors.blueAccent,
                            size: 64,
                          ),
                          const SizedBox(height: 16),
                          const Text(
                            'FRAME DE CALIBRAÇÃO',
                            style: TextStyle(
                              color: Colors.blueAccent,
                              letterSpacing: 2,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 8),
                          const Text(
                            'Aguardando ajuste de lente.',
                            style: TextStyle(
                              color: Colors.white54,
                              fontSize: 14,
                            ),
                          ),
                          const SizedBox(height: 24),
                          ElevatedButton.icon(
                            onPressed: () {},
                            icon: const Icon(Icons.camera_alt),
                            label: const Text('PEDIR SNAPSHOT AGORA'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.grey[850],
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 24,
                                vertical: 16,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),

                const SizedBox(width: 16),
                Expanded(
                  flex: 1,
                  child: Column(
                    children: [
                      _buildModernKpiCard(
                        'Taxa Incerteza (25-75%)',
                        '14.2%',
                        Icons.query_stats,
                        Colors.amber,
                        'Maçãs redirecionadas p/ Cloud',
                        false,
                      ),
                      const SizedBox(height: 16),
                      _buildModernKpiCard(
                        'Latência Inferência',
                        '45 ms',
                        Icons.speed,
                        Colors.cyan,
                        'Processamento por frame local',
                        false,
                      ),
                      const SizedBox(height: 16),
                      _buildModernKpiCard(
                        'Taxa de Captura',
                        '3 frames/maçã',
                        Icons.burst_mode,
                        AppColors.healthy,
                        'Taxa de falha (blur): 0.4%',
                        false,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 32),

          const Text(
            'Controlos Remotos da Câmara',
            style: TextStyle(
              color: Colors.white,
              fontSize: 20,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 16),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Container(
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Row(
                        children: [
                          Icon(Icons.zoom_in, color: Colors.white54),
                          SizedBox(width: 8),
                          Text(
                            'Zoom Ótico (Distância ao Tapete)',
                            style: TextStyle(
                              color: Colors.white54,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Slider(
                        value: 0.4,
                        onChanged: (v) {},
                        activeColor: Colors.blue,
                      ),
                      const SizedBox(height: 24),
                      const Row(
                        children: [
                          Icon(Icons.light_mode, color: Colors.white54),
                          SizedBox(width: 8),
                          Text(
                            'Exposição / ISO (Luz Ambiente)',
                            style: TextStyle(
                              color: Colors.white54,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Slider(
                        value: 0.7,
                        onChanged: (v) {},
                        activeColor: Colors.yellow,
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Container(
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Row(
                        children: [
                          Icon(
                            Icons.warning_amber_rounded,
                            color: Colors.white54,
                          ),
                          SizedBox(width: 8),
                          Text(
                            'Gestão de Falhas do Módulo Edge',
                            style: TextStyle(
                              color: Colors.white54,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 24),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          onPressed: () {},
                          icon: const Icon(Icons.restart_alt),
                          label: const Text('FORÇAR REINÍCIO DA CÂMARA'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.red[900],
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.all(20),
                            textStyle: const TextStyle(
                              fontWeight: FontWeight.bold,
                              letterSpacing: 1,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.white10,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Row(
                          children: [
                            Icon(
                              Icons.info_outline,
                              color: Colors.white30,
                              size: 16,
                            ),
                            SizedBox(width: 8),
                            Text(
                              'Último restart: Há 5 dias. Sistema estável.',
                              style: TextStyle(
                                color: Colors.white30,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildPlaceholderContent(String page) {
    return Center(
      child: Text(
        'Feature: $page\n(Configuração de software futura)',
        textAlign: TextAlign.center,
        style: const TextStyle(color: Colors.white54, fontSize: 24),
      ),
    );
  }
}
