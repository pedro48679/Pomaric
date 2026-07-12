import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:printing/printing.dart';
import 'package:fl_chart/fl_chart.dart';
import '../../models/models.dart';
import '../../providers/auth_provider.dart';
import '../../providers/dashboard_provider.dart';
import '../../utils/constants.dart';
import '../../widgets/apple_card.dart';
import '../../widgets/donut_chart_widget.dart';
import '../../services/pdf_service.dart';
import '../../services/mjpeg_service.dart';
import '../../services/supabase_service.dart';
import '../manual/manual_sorting.dart';
import '../global_dashboard.dart';
import '../../widgets/apple_grid_view.dart';
import '../../widgets/tech_grid_background.dart';
import '../matrix/matrix_dashboard.dart';
import '../reports/reports_dashboard.dart';
import '../mlops/mlops_dashboard.dart';
import '../iot/iot_dashboard.dart';

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
    final isDark = ref.watch(themeProvider);
    AppColors.isDark = isDark;

    final currentPage = ref.watch(currentPageProvider);
    final headerVisible = ref.watch(headerVisibleProvider);
    ref.watch(loadDataFutureProvider);

    ref.listen<String>(currentPageProvider, (previous, next) {
      if (previous != next && previous != null) {
        ScaffoldMessenger.of(context).clearSnackBars();
        ScaffoldMessenger.of(context).clearMaterialBanners();
        ref.read(headerVisibleProvider.notifier).setVisible(true);
      }
    });

    return TechGridBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        drawer: Drawer(
          backgroundColor: AppColors.surface,
          child: buildRightSidebar(context, ref),
        ),
        body: NotificationListener<ScrollNotification>(
          onNotification: (ScrollNotification notification) {
            if (notification is ScrollUpdateNotification) {
              final delta = notification.scrollDelta ?? 0.0;
              final pixels = notification.metrics.pixels;
              
              if (pixels <= 10) {
                ref.read(headerVisibleProvider.notifier).setVisible(true);
              } else if (delta > 3.0) {
                ref.read(headerVisibleProvider.notifier).setVisible(false);
              } else if (delta < -3.0) {
                ref.read(headerVisibleProvider.notifier).setVisible(true);
              }
            }
            return false;
          },
          child: Column(
            children: [
              AnimatedSize(
                duration: const Duration(milliseconds: 250),
                curve: Curves.easeInOut,
                child: (currentPage != 'Triagem Manual' && headerVisible)
                    ? buildHeader(context, ref)
                    : const SizedBox(height: 0, width: double.infinity),
              ),
              if (currentPage != 'Triagem Manual' && !headerVisible)
                GestureDetector(
                  onTap: () => ref.read(headerVisibleProvider.notifier).setVisible(true),
                  child: Container(
                    height: 12,
                    width: double.infinity,
                    color: AppColors.surface.withOpacity(0.4),
                    child: Center(
                      child: Container(
                        width: 50,
                        height: 4,
                        decoration: BoxDecoration(
                          color: AppColors.primary.withOpacity(0.6),
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                  ),
                ),
              Expanded(
                child: (currentPage == 'Controlo do Pomar' || currentPage == 'Lote Dashboard')
                    ? const GlobalDashboard()
                    : currentPage == 'IoT & Edge'
                    ? buildIotDashboard(context, ref)
                    : currentPage == 'MLOps/ShadowCNN'
                    ? buildMLOpsDashboard(context, ref)
                    : currentPage == 'Grelha Lote' ||
                          currentPage == 'Lote Específico'
                    ? buildDashboardContent(context, ref)
                    : currentPage == 'Relatório' || currentPage == 'Reports'
                    ? buildReportsContent(context, ref)
                    : currentPage == 'Triagem Manual'
                    ? const ManualSortingView()
                    : buildPlaceholderContent(currentPage),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget buildHeader(BuildContext context, WidgetRef ref) {
    final isDark = ref.watch(themeProvider);
    final currentBatch = ref.watch(batchProvider);
    final availableBatches = ref.watch(availableBatchesProvider);
    final currentPage = ref.watch(currentPageProvider);
    final String formattedDate = DateFormat(
      'dd/MM/yyyy HH:mm',
    ).format(DateTime.now());

    final user = ref.watch(authProvider);
    final isAdmin = user?.role == UserRole.admin;

    final batches = ref.watch(filteredBatchesProvider);
    final stats = ref.watch(globalStatsProvider);
    final dismissedIds = ref.watch(dismissedOutbreaksProvider);
    final isDismissed = ref.watch(outbreaksPopupDismissedProvider);

    bool hasOutbreaks = false;
    if (stats != null) {
      final riskBatchesCount = batches.where((b) {
        final dist = b.healthDistribution;
        String dominant = 'Healthy';
        int maxVal = 0;
        for (final k in ['Rot', 'Scab', 'Blotch', 'Anthracnose']) {
          if ((dist[k] ?? 0) > maxVal) {
            maxVal = dist[k]!;
            dominant = k;
          }
        }
        return dominant != 'Healthy' && b.urgencyScore > 0.15 && !dismissedIds.contains(b.id);
      }).length;

      final showSystemSurge = stats.surgeAlert != 'Estável' && !dismissedIds.contains('SYSTEM_SURGE');
      hasOutbreaks = riskBatchesCount > 0 || showSystemSurge;
    }

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
                    icon: Icon(Icons.menu, color: AppColors.textPrimary),
                    onPressed: () => Scaffold.of(context).openDrawer(),
                  ),
                ),
              if (isAdmin) const SizedBox(width: 16),
              Text(
                formattedDate,
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w500,
                  color: AppColors.textSecondary,
                ),
              ),
              const SizedBox(width: 24),
              buildIotStatusIndicator(ref),
              if (isAdmin) buildShadowGlobalBadge(ref),
            ],
          ),
          Row(
            children: [
              if (isAdmin) ...[
                if (currentPage != 'Controlo do Pomar' && currentBatch != null) ...[
                  const Icon(
                    Icons.location_on,
                    color: Colors.blueAccent,
                    size: 20,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    currentBatch.location,
                    style: TextStyle(color: AppColors.textSecondary, fontSize: 14),
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
                          Icon(Icons.inventory_2, color: AppColors.primary, size: 16),
                          const SizedBox(width: 8),
                          Text(
                            '$activeCount Lote${activeCount > 1 ? 's' : ''} Ativo${activeCount > 1 ? 's' : ''}',
                            style: TextStyle(color: AppColors.primary, fontWeight: FontWeight.bold, fontSize: 13),
                          ),
                        ],
                      ),
                    );
                  },
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
                  onPressed: () => ref.read(currentPageProvider.notifier).setPage('Triagem Manual'),
                ),
                const SizedBox(width: 8),
                ElevatedButton.icon(
                  icon: const Icon(Icons.logout, size: 16),
                  label: const Text('Sair'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.isDark ? Colors.white10 : Colors.black12,
                    foregroundColor: AppColors.textPrimary,
                    elevation: 0,
                  ),
                  onPressed: () => ref.read(authProvider.notifier).logout(),
                ),
              ],
              const SizedBox(width: 16),
              IconButton(
                icon: Icon(
                  isDark ? Icons.light_mode : Icons.dark_mode,
                  color: isDark ? AppColors.primary : AppColors.textSecondary,
                ),
                onPressed: () => ref.read(themeProvider.notifier).toggle(),
                tooltip: isDark ? 'Alternar para Modo Claro' : 'Alternar para Modo Escuro',
              ),
              if (hasOutbreaks && isDismissed) ...[
                const SizedBox(width: 8),
                IconButton(
                  icon: const Icon(Icons.warning_amber_rounded, color: Colors.redAccent),
                  onPressed: () {
                    ref.read(outbreaksPopupDismissedProvider.notifier).setDismissed(false);
                  },
                  tooltip: 'Restaurar avisos de risco biológico',
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

Widget buildIotStatusIndicator(WidgetRef ref) {
    final hbAsync = ref.watch(raspberryHeartbeatProvider);
    return hbAsync.when(
      data: (hb) {
        final online = hb.isOnline;
        final color = online
            ? (hb.mode == 'sleep' ? Colors.amber : Colors.green)
            : Colors.redAccent;
        final label = online
            ? (hb.mode == 'sleep'
                ? 'Pi5: REPOUSO'
                : hb.mode == 'active'
                    ? 'Pi5: ATIVO'
                    : 'Pi5: ONLINE')
            : 'Pi5: OFFLINE';
        final tempStr = (hb.cpuTemp != null) ? '  ${hb.cpuTemp!.toStringAsFixed(0)}°C' : '';
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: color.withOpacity(0.1),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: color.withOpacity(0.5)),
          ),
          child: Row(
            children: [
              Icon(
                online ? Icons.wifi_tethering : Icons.wifi_tethering_off,
                color: color,
                size: 16,
              ),
              const SizedBox(width: 8),
              Text(
                '$label$tempStr',
                style: TextStyle(
                  color: color,
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        );
      },
      loading: () => Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: Colors.grey.withOpacity(0.1),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Colors.grey.withOpacity(0.3)),
        ),
        child: const Row(
          children: [
            SizedBox(width: 12, height: 12, child: CircularProgressIndicator(strokeWidth: 1.5, color: Colors.grey)),
            SizedBox(width: 8),
            Text('Pi5: ...', style: TextStyle(color: Colors.grey, fontSize: 10, fontWeight: FontWeight.bold)),
          ],
        ),
      ),
      error: (_, __) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: Colors.redAccent.withOpacity(0.1),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Colors.redAccent.withOpacity(0.3)),
        ),
        child: const Row(
          children: [
            Icon(Icons.wifi_tethering_off, color: Colors.redAccent, size: 16),
            SizedBox(width: 8),
            Text('Pi5: OFFLINE', style: TextStyle(color: Colors.redAccent, fontSize: 10, fontWeight: FontWeight.bold)),
          ],
        ),
      ),
    );
  }

Widget buildShadowGlobalBadge(WidgetRef ref) {
    final shadowAsync = ref.watch(shadowGlobalStatusProvider);
    return shadowAsync.maybeWhen(
      data: (s) {
        final state = (s['state'] as String?) ?? 'idle';
        if (state == 'idle') return const SizedBox();

        final processed = (s['apples_processed'] as num?)?.toInt() ?? 0;
        Color color;
        String label;
        switch (state) {
          case 'running':
            color = Colors.amberAccent;
            label = 'Shadow: $processed maçãs';
            break;
          case 'promoted':
            color = AppColors.healthy;
            label = 'Shadow: PROMOVIDO';
            break;
          case 'archived':
            color = Colors.grey;
            label = 'Shadow: arquivado';
            break;
          default:
            return const SizedBox();
        }

        return Padding(
          padding: const EdgeInsets.only(left: 12),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: color.withOpacity(0.1),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: color.withOpacity(0.5)),
            ),
            child: Row(
              children: [
                Icon(Icons.visibility_outlined, color: color, size: 16),
                const SizedBox(width: 8),
                Text(
                  label,
                  style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.bold),
                ),
              ],
            ),
          ),
        );
      },
      orElse: () => const SizedBox(),
    );
  }

Widget buildRightSidebar(BuildContext context, WidgetRef ref) {
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
            child: Icon(Icons.person, size: 40, color: AppColors.textPrimary),
          ),
          const SizedBox(height: 16),
          Text(
            user.username.toUpperCase(),
            style: TextStyle(
              color: AppColors.textPrimary,
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
          Divider(color: AppColors.textSecondary.withOpacity(0.2)),

          if (isAdmin)
            buildSidebarItem(
              context,
              ref,
              'Controlo do Pomar',
              Icons.home,
              currentPage,
            ),
          buildSidebarItem(
            context,
            ref,
            'Triagem Manual',
            Icons.precision_manufacturing,
            currentPage,
          ),
          buildSidebarItem(
            context,
            ref,
            'Grelha Lote',
            Icons.grid_view,
            currentPage,
          ),
          if (isAdmin)
            buildSidebarItem(
              context,
              ref,
              'IoT & Edge',
              Icons.camera_alt,
              currentPage,
            ),
          if (isAdmin)
            buildSidebarItem(
              context,
              ref,
              'MLOps/ShadowCNN',
              Icons.psychology,
              currentPage,
            ),
          if (isAdmin)
            buildSidebarItem(
              context,
              ref,
              'Relatório',
              Icons.picture_as_pdf,
              currentPage,
            ),

          const Spacer(),
          Divider(color: AppColors.textSecondary.withOpacity(0.2)),
          ListTile(
            leading: const Icon(Icons.logout, color: Colors.redAccent),
            title: const Text(
              'Sair',
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



Widget buildSidebarItem(
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
          color: isSelected ? AppColors.healthy : AppColors.textSecondary,
        ),
        title: Text(
          title,
          style: TextStyle(
            color: isSelected ? AppColors.textPrimary : AppColors.textSecondary,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
          ),
        ),
        onTap: () {
          ref.read(currentPageProvider.notifier).setPage(title);
        },
      ),
    );
  }

Widget buildMetaChip(String label, String value, IconData icon) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, color: AppColors.textSecondary, size: 20),
        const SizedBox(height: 4),
        Text(value, style: TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.bold, fontSize: 14)),
        Text(label, style: TextStyle(color: AppColors.textSecondary, fontSize: 10)),
      ],
    );
  }

Widget buildPlaceholderContent(String page) {
    return Center(
      child: Text(
        'Feature: $page\n(Configuração de software futura)',
        textAlign: TextAlign.center,
        style: TextStyle(color: AppColors.textSecondary, fontSize: 24),
      ),
    );
  }

}


Widget buildModernKpiCard(
    String title,
    String value,
    IconData icon,
    Color color, [
    String? subtitle,
    bool expand = true,
  ]) {
    Widget card = Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border(left: BorderSide(color: color, width: 4)),
      ),
      child: FittedBox(
        fit: BoxFit.scaleDown,
        alignment: Alignment.centerLeft,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: color, size: 28),
            const SizedBox(height: 12),
            Text(
              title,
              style: TextStyle(color: AppColors.textSecondary, fontSize: 16),
            ),
            const SizedBox(height: 8),
            Text(
              value,
              style: TextStyle(
                color: AppColors.textPrimary,
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
                            : AppColors.textSecondary),
                  fontSize: 12,
                ),
              ),
            ],
          ],
        ),
      ),
    );

    return expand ? Expanded(child: card) : card;
  }
