
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
import '../batch_dashboard.dart';
import '../global_dashboard.dart';
import '../../widgets/apple_grid_view.dart';
import '../../widgets/tech_grid_background.dart';
import '../structure/dashboard_screen.dart'; // for shadowPieTouchedIndexProvider

Widget buildIotDashboard(BuildContext context, WidgetRef ref) {
    final hbAsync = ref.watch(raspberryHeartbeatProvider);
    final hb = hbAsync.value ?? RaspberryHeartbeat.offline();

    final cpuTempStr = hb.cpuTemp != null ? '${hb.cpuTemp!.toStringAsFixed(1)}°C' : '--';
    final cpuTempWarning = hb.cpuTemp != null && hb.cpuTemp! > 75.0;
    final cpuPctStr = hb.cpuPercent != null ? '${hb.cpuPercent!.toStringAsFixed(0)}%' : '--';
    final fpsStr = hb.cameraFps != null ? '${hb.cameraFps!.toStringAsFixed(1)} fps' : '--';
    final blurStr = hb.lastBlurScore != null ? hb.lastBlurScore!.toStringAsFixed(0) : '--';

    final modeColor = hb.isOnline
        ? (hb.mode == 'sleep' ? Colors.amber : (hb.mode == 'active' ? Colors.greenAccent : Colors.blueAccent))
        : Colors.redAccent;
    final modeLabel = switch (hb.mode) {
      'active' => 'ATIVO — A processar',
      'sleep'  => 'REPOUSO — Baixa resolução',
      'idle'   => 'VIGILÂNCIA — A aguardar movimento',
      _        => 'OFFLINE',
    };

    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Cabeçalho compacto ───────────────────────────────────────────
          Row(
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Controlo de Hardware (Edge AI)',
                    style: TextStyle(color: AppColors.textPrimary, fontSize: 22, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    'Telemetria Raspberry Pi 5 · heartbeat 5s',
                    style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
                  ),
                ],
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                decoration: BoxDecoration(
                  color: modeColor.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(30),
                  border: Border.all(color: modeColor.withOpacity(0.4)),
                ),
                child: Row(
                  children: [
                    Icon(hb.isOnline ? Icons.sensors : Icons.sensors_off, color: modeColor, size: 15),
                    const SizedBox(width: 8),
                    Text(modeLabel, style: TextStyle(color: modeColor, fontWeight: FontWeight.bold, fontSize: 12)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),

          // ── Linha principal: KPIs | Vídeo | KPIs ────────────────────────
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Coluna esquerda — KPIs de sistema
                Expanded(
                  flex: 3,
                  child: FractionallySizedBox(
                    heightFactor: 0.9,
                    child: Column(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      Expanded(child: buildModernKpiCard(
                        'Carga CPU (Pi 5)', cpuPctStr, Icons.memory, Colors.blue,
                        hb.isOnline ? 'Uptime: ${hb.uptimeDisplay}' : 'Sem ligação', false,
                      )),
                      const SizedBox(height: 10),
                      Expanded(child: buildModernKpiCard(
                        'Temp. SoC', cpuTempStr, Icons.thermostat,
                        cpuTempWarning ? Colors.redAccent : Colors.orange,
                        cpuTempWarning ? 'Estrangulamento térmico!' : 'Temperatura nominal', false,
                      )),
                      const SizedBox(height: 10),
                      Expanded(child: buildModernKpiCard(
                        'Memória RAM', hb.ramDisplay, Icons.storage, Colors.purpleAccent,
                        'Modelo ONNX em memória', false,
                      )),
                    ],
                  ),
                ),
              ),
                const SizedBox(width: 14),

                // Coluna central — câmara ao vivo + botão RESTART abaixo
                Expanded(
                  flex: 10,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: IotVideoPanel(
                          hb: hb,
                          onRefresh: () => ref.invalidate(raspberryHeartbeatProvider),
                        ),
                      ),
                      const SizedBox(height: 6),
                      const RestartButton(),
                    ],
                  ),
                ),
                const SizedBox(width: 14),

                // Coluna direita — KPIs de câmara
                Expanded(
                  flex: 3,
                  child: FractionallySizedBox(
                    heightFactor: 0.9,
                    child: Column(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      Expanded(child: buildModernKpiCard(
                        'Câmara FPS', fpsStr, Icons.burst_mode, AppColors.healthy,
                        hb.mode == 'sleep' ? 'Modo repouso 640×360' : 'Stream 2304×1296', false,
                      )),
                      const SizedBox(height: 10),
                      Expanded(child: buildModernKpiCard(
                        'Inferências', '${hb.inferenceCount}', Icons.query_stats, Colors.amber,
                        'Total na sessão actual', false,
                      )),
                      const SizedBox(height: 10),
                      Expanded(child: buildModernKpiCard(
                        'Foco Médio', blurStr, Icons.center_focus_strong,
                        hb.blurWarning ? Colors.orange : Colors.cyan,
                        hb.blurWarning ? 'Lente suja / descalibrada' : 'Nitidez nominal', false,
                      )),
                    ],
                  ),
                ),
              ),
              ],
            ),
          ),
          const SizedBox(height: 10),

          // ── Painel de configuração compacto (flags + restart) ────────────
          const CameraConfigPanel(),
        ],
      ),
    );
  }

class IotVideoPanel extends StatefulWidget {
  final RaspberryHeartbeat hb;
  final VoidCallback onRefresh;

  const IotVideoPanel({required this.hb, required this.onRefresh});

  @override
  State<IotVideoPanel> createState() => IotVideoPanelState();
}

class IotVideoPanelState extends State<IotVideoPanel> {
  MjpegService? _mjpeg;
  StreamSubscription<Uint8List>? _sub;
  bool _streaming = false;
  bool _connecting = false;
  Uint8List? _frame;
  String? _error;

  void _startStream() {
    setState(() { _connecting = true; _error = null; });
    _mjpeg = MjpegService();
    _mjpeg!.start(AppConstants.mjpegUrl);
    _sub = _mjpeg!.stream.listen(
      (frame) { if (mounted) setState(() => _frame = frame); },
      onError: (e) { if (mounted) setState(() { _error = e.toString(); }); _stopStream(); },
    );
    if (mounted) setState(() { _streaming = true; _connecting = false; });
  }

  void _stopStream() {
    _sub?.cancel(); _sub = null;
    _mjpeg?.stop(); _mjpeg = null;
    if (mounted) setState(() { _streaming = false; _frame = null; _connecting = false; });
  }

  @override
  void dispose() {
    // Garante libertação de recursos quando o utilizador sai da página IoT
    _sub?.cancel();
    _mjpeg?.stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final hb = widget.hb;
    final modeColor = hb.isOnline
        ? (hb.mode == 'sleep'
            ? Colors.amber
            : (hb.mode == 'active' ? Colors.greenAccent : Colors.blueAccent))
        : Colors.redAccent;
    final fpsStr = hb.cameraFps != null
        ? '${hb.cameraFps!.toStringAsFixed(1)} fps'
        : '--';

    return Container(
      decoration: BoxDecoration(
        color: AppColors.isDark ? Colors.black : Colors.blueGrey.shade100,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: hb.blurWarning
              ? Colors.orange.withOpacity(0.7)
              : (_streaming
                  ? Colors.redAccent.withOpacity(0.5)
                  : modeColor.withOpacity(0.3)),
          width: hb.blurWarning ? 1.5 : 1.0,
        ),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(15),
        child: Stack(
          fit: StackFit.expand,
          children: [
            // ── Conteúdo principal ──────────────────────────────────────────
            if (_streaming && _frame != null)
              Image.memory(_frame!, fit: BoxFit.contain, gaplessPlayback: true)
            else
              _buildStaticPanel(hb, modeColor, fpsStr),

            // ── Aviso de blur (lente suja / descalibrada) ───────────────────
            if (hb.blurWarning)
              Positioned(
                top: 0, left: 0, right: 0,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
                  color: Colors.orange.withOpacity(0.93),
                  child: Row(
                    children: [
                      const Icon(Icons.lens_blur, color: Colors.black87, size: 18),
                      const SizedBox(width: 8),
                      const Expanded(
                        child: Text(
                          'Atenção: blur score baixo — verifique a lente (suja ou descalibrada)',
                          style: TextStyle(
                            color: Colors.black87,
                            fontWeight: FontWeight.bold,
                            fontSize: 12,
                          ),
                        ),
                      ),
                      if (hb.lastBlurScore != null)
                        Container(
                          margin: const EdgeInsets.only(left: 8),
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: Colors.black26,
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            'Blur: ${hb.lastBlurScore!.toStringAsFixed(0)}',
                            style: const TextStyle(
                              color: Colors.black87,
                              fontWeight: FontWeight.bold,
                              fontSize: 11,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),

            // ── Badge LIVE (quando em streaming) ────────────────────────────
            if (_streaming)
              Positioned(
                top: hb.blurWarning ? 52 : 12,
                right: 12,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.75),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: Colors.redAccent.withOpacity(0.9)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 6, height: 6,
                        decoration: const BoxDecoration(
                          color: Colors.redAccent,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 5),
                      const Text(
                        'LIVE',
                        style: TextStyle(
                          color: Colors.redAccent,
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 1,
                        ),
                      ),
                    ],
                  ),
                ),
              ),

            // ── Botão desligar câmara (overlay sobre o vídeo) ───────────────
            if (_streaming)
              Positioned(
                bottom: 16, left: 0, right: 0,
                child: Center(
                  child: ElevatedButton.icon(
                    onPressed: _stopStream,
                    icon: const Icon(Icons.videocam_off, size: 16),
                    label: const Text('DESLIGAR CÂMARA'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.red[900]!.withOpacity(0.88),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  /// Painel estático mostrado quando o stream está inativo.
  Widget _buildStaticPanel(
    RaspberryHeartbeat hb,
    Color modeColor,
    String fpsStr,
  ) {
    return SingleChildScrollView(
      child: Padding(
        padding: EdgeInsets.only(
          top: hb.blurWarning ? 60 : 28,
          bottom: 28,
          left: 28,
          right: 28,
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              hb.isOnline ? Icons.radar : Icons.center_focus_weak,
              color: modeColor,
              size: 52,
            ),
            const SizedBox(height: 14),
            Text(
              hb.isOnline ? 'RASPBERRY PI 5 · LIGADO' : 'RASPBERRY PI 5 · DESLIGADO',
              style: TextStyle(
                color: modeColor,
                letterSpacing: 2,
                fontWeight: FontWeight.bold,
                fontSize: 12,
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: 6),
              Text(
                'Erro de ligação ao stream',
                style: TextStyle(color: Colors.redAccent, fontSize: 11),
              ),
            ],
            const SizedBox(height: 20),
            // Grelha de metadados
            Wrap(
              spacing: 20,
              runSpacing: 16,
              alignment: WrapAlignment.center,
              children: [
                _chip('Disco', hb.diskDisplay, Icons.sd_card, null),
                _chip('Câmara FPS', fpsStr, Icons.videocam, null),
                _chip('Inferências', '${hb.inferenceCount}', Icons.bubble_chart, null),
                _chip('Uptime', hb.uptimeDisplay, Icons.timer, null),
                if (hb.lastBlurScore != null)
                  _chip(
                    'Blur Score',
                    hb.lastBlurScore!.toStringAsFixed(0),
                    Icons.center_focus_strong,
                    hb.blurWarning ? Colors.orange : Colors.greenAccent,
                  ),
              ],
            ),
            const SizedBox(height: 24),
            // Botões de ação
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                ElevatedButton.icon(
                  onPressed: widget.onRefresh,
                  icon: const Icon(Icons.refresh, size: 15),
                  label: const Text('ATUALIZAR'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.isDark ? Colors.blueGrey.shade800 : Colors.blueAccent.shade100,
                    foregroundColor: AppColors.isDark ? Colors.white : Colors.black87,
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  ),
                ),
                const SizedBox(width: 12),
                ElevatedButton.icon(
                  onPressed: _connecting ? null : _startStream,
                  icon: _connecting
                      ? const SizedBox(
                          width: 14, height: 14,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.cyanAccent,
                          ),
                        )
                      : const Icon(Icons.videocam, size: 15),
                  label: Text(_connecting ? 'A LIGAR...' : 'VER EM DIRETO'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.isDark ? Colors.teal.shade800 : Colors.teal.shade600,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _chip(String label, String value, IconData icon, Color? color) {
    final c = color ?? AppColors.textSecondary;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, color: c, size: 18),
        const SizedBox(height: 3),
        Text(value, style: TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.bold, fontSize: 13)),
        Text(label, style: TextStyle(color: c, fontSize: 10)),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Estado do indicador de dot no botão RESTART
// ---------------------------------------------------------------------------

enum _DotState { idle, sending, done }

// ---------------------------------------------------------------------------
// Botão RESTART — fica abaixo da tela de livestream, canto inferior esquerdo.
// O ponto indica o estado: preto (idle) → laranja (a reiniciar) → branco (feito).
// Lê a configuração actual do cameraConfigProvider e envia para ws_server.py.
// ---------------------------------------------------------------------------

class RestartButton extends ConsumerStatefulWidget {
  const RestartButton();

  @override
  ConsumerState<RestartButton> createState() => RestartButtonState();
}

class RestartButtonState extends ConsumerState<RestartButton> {
  _DotState _dot = _DotState.idle;

  Future<void> _restart() async {
    if (_dot != _DotState.idle) return;
    setState(() => _dot = _DotState.sending);
    try {
      final flags = ref.read(cameraConfigProvider.notifier).state.toFlags();
      final resp = await http
          .post(
            Uri.parse(AppConstants.commandUrl),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({'type': 'restart_cmd', 'flags': flags}),
          )
          .timeout(const Duration(seconds: 3));
      if (resp.statusCode == 200 && mounted) {
        setState(() => _dot = _DotState.done);
        Future.delayed(const Duration(seconds: 3), () {
          if (mounted) setState(() => _dot = _DotState.idle);
        });
      } else {
        if (mounted) setState(() => _dot = _DotState.idle);
      }
    } catch (_) {
      if (mounted) setState(() => _dot = _DotState.idle);
    }
  }

  Color get _dotColor => switch (_dot) {
    _DotState.idle    => Colors.black,
    _DotState.sending => Colors.orange,
    _DotState.done    => Colors.white,
  };

  @override
  Widget build(BuildContext context) {
    return ElevatedButton(
      onPressed: _dot == _DotState.idle ? _restart : null,
      style: ElevatedButton.styleFrom(
        backgroundColor: AppColors.surface,
        foregroundColor: AppColors.textPrimary,
        disabledBackgroundColor: AppColors.surface,
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
          side: BorderSide(color: AppColors.glassBorder),
        ),
        elevation: 0,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 350),
            curve: Curves.easeInOut,
            width: 9, height: 9,
            decoration: BoxDecoration(
              color: _dotColor,
              shape: BoxShape.circle,
              boxShadow: _dot == _DotState.sending
                  ? [BoxShadow(color: Colors.orange.withOpacity(0.6), blurRadius: 6, spreadRadius: 1)]
                  : [],
            ),
          ),
          const SizedBox(width: 10),
          Text(
            'RESTART',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 11,
              letterSpacing: 1,
              color: _dot == _DotState.idle ? AppColors.textPrimary : AppColors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Painel de configuração da câmara — flags do raspberry_camera_format.py
// Opções básicas visíveis; avançadas reveladas com o botão ⚙
// ---------------------------------------------------------------------------

class CameraConfigPanel extends ConsumerStatefulWidget {
  const CameraConfigPanel();

  @override
  ConsumerState<CameraConfigPanel> createState() => CameraConfigPanelState();
}

class CameraConfigPanelState extends ConsumerState<CameraConfigPanel> {
  // Cópia local para responsividade dos sliders — sincronizada com o provider
  late double _lensPosition;
  late double _burst;
  late double _burstInterval;
  late double _shutterUs;
  late double _motionThreshold;
  late double _triggerDelay;
  late double _sharpness;
  late double _contrast;
  late double _saturation;
  late double _noiseReduction;

  bool _showAdvanced = false;

  @override
  void initState() {
    super.initState();
    final c = ref.read(cameraConfigProvider.notifier).state;
    _lensPosition = c.lensPosition;
    _burst = c.burst;
    _burstInterval = c.burstInterval;
    _shutterUs = c.shutterUs;
    _motionThreshold = c.motionThreshold;
    _triggerDelay = c.triggerDelay;
    _sharpness = c.sharpness;
    _contrast = c.contrast;
    _saturation = c.saturation;
    _noiseReduction = c.noiseReduction;
  }

  void _set(CameraConfig Function(CameraConfig) fn) {
    ref.read(cameraConfigProvider.notifier).update(fn);
  }

  String get _focusLabel {
    if (_lensPosition < 0.05) return 'Autofocus';
    return '${_lensPosition.toStringAsFixed(1)} dpt · ${(100.0 / _lensPosition).round()} cm';
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.glassBorder),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // ── Cabeçalho ────────────────────────────────────────────────────
          Row(
            children: [
              Icon(Icons.tune, color: AppColors.textSecondary, size: 14),
              const SizedBox(width: 7),
              Text(
                'CONFIGURAÇÃO DA CÂMARA',
                style: TextStyle(
                  color: AppColors.textSecondary,
                  fontWeight: FontWeight.bold,
                  fontSize: 11,
                  letterSpacing: 1.2,
                ),
              ),
              const Spacer(),
              // Botão de configurações avançadas
              TextButton.icon(
                onPressed: () => setState(() => _showAdvanced = !_showAdvanced),
                icon: Icon(
                  Icons.settings,
                  size: 13,
                  color: _showAdvanced ? AppColors.primary : AppColors.textSecondary,
                ),
                label: Text(
                  _showAdvanced ? 'Avançadas ▲' : 'Avançadas ▼',
                  style: TextStyle(
                    fontSize: 10,
                    color: _showAdvanced ? AppColors.primary : AppColors.textSecondary,
                  ),
                ),
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),

          // ── Opções base: Foco · Frames · Intervalo ───────────────────────
          Row(
            children: [
              Expanded(child: _slider(
                'Distância foco', _focusLabel,
                _lensPosition, 0, 10,
                (v) { setState(() => _lensPosition = v); _set((c) => c.copyWith(lensPosition: v)); },
              )),
              const SizedBox(width: 12),
              Expanded(child: _slider(
                'Frames (burst)', '${_burst.round()} foto${_burst >= 2 ? "s" : ""}',
                _burst, 1, 10,
                (v) { setState(() => _burst = v); _set((c) => c.copyWith(burst: v)); },
                divisions: 9,
              )),
              const SizedBox(width: 12),
              Expanded(child: _slider(
                'Intervalo burst', '${_burstInterval.round()} ms',
                _burstInterval, 50, 500,
                (v) { setState(() => _burstInterval = v); _set((c) => c.copyWith(burstInterval: v)); },
              )),
            ],
          ),

          // ── Opções avançadas (animadas) ───────────────────────────────────
          AnimatedSize(
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeInOut,
            child: _showAdvanced
                ? Column(
                    children: [
                      const SizedBox(height: 4),
                      // Linha 2: Exposição · Motion threshold · Delay
                      Row(
                        children: [
                          Expanded(child: _slider(
                            'Exposição', '${_shutterUs.round()} µs',
                            _shutterUs, 1000, 20000,
                            (v) { setState(() => _shutterUs = v); _set((c) => c.copyWith(shutterUs: v)); },
                          )),
                          const SizedBox(width: 12),
                          Expanded(child: _slider(
                            'Threshold mov.', '${_motionThreshold.round()} px',
                            _motionThreshold, 1, 60,
                            (v) { setState(() => _motionThreshold = v); _set((c) => c.copyWith(motionThreshold: v)); },
                          )),
                          const SizedBox(width: 12),
                          Expanded(child: _slider(
                            'Delay trigger', '${_triggerDelay.toStringAsFixed(2)} s',
                            _triggerDelay, 0, 2,
                            (v) { setState(() => _triggerDelay = v); _set((c) => c.copyWith(triggerDelay: v)); },
                          )),
                        ],
                      ),
                      const SizedBox(height: 4),
                      // Linha 3: Qualidade (4 sliders)
                      Row(
                        children: [
                          Expanded(child: _slider(
                            'Nitidez', _sharpness.toStringAsFixed(1),
                            _sharpness, 0, 16,
                            (v) { setState(() => _sharpness = v); _set((c) => c.copyWith(sharpness: v)); },
                          )),
                          const SizedBox(width: 10),
                          Expanded(child: _slider(
                            'Contraste', _contrast.toStringAsFixed(1),
                            _contrast, 0, 32,
                            (v) { setState(() => _contrast = v); _set((c) => c.copyWith(contrast: v)); },
                          )),
                          const SizedBox(width: 10),
                          Expanded(child: _slider(
                            'Saturação', _saturation.toStringAsFixed(1),
                            _saturation, 0, 32,
                            (v) { setState(() => _saturation = v); _set((c) => c.copyWith(saturation: v)); },
                          )),
                          const SizedBox(width: 10),
                          Expanded(child: _slider(
                            'Ruído (NR)', '${_noiseReduction.round()}',
                            _noiseReduction, 0, 4,
                            (v) { setState(() => _noiseReduction = v); _set((c) => c.copyWith(noiseReduction: v)); },
                            divisions: 4,
                          )),
                        ],
                      ),
                    ],
                  )
                : const SizedBox.shrink(),
          ),
        ],
      ),
    );
  }

  Widget _slider(
    String label,
    String display,
    double value,
    double min,
    double max,
    ValueChanged<double> onChanged, {
    int? divisions,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Flexible(
              child: Text(
                label,
                style: TextStyle(color: AppColors.textSecondary, fontSize: 9, letterSpacing: 0.2),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 4),
            Text(
              display,
              style: TextStyle(color: AppColors.primary, fontSize: 9, fontWeight: FontWeight.bold),
            ),
          ],
        ),
        SliderTheme(
          data: SliderTheme.of(context).copyWith(
            trackHeight: 2,
            thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 5),
            overlayShape: const RoundSliderOverlayShape(overlayRadius: 10),
            activeTrackColor: AppColors.accent,
            inactiveTrackColor: AppColors.textSecondary.withOpacity(0.2),
            thumbColor: AppColors.primary,
            overlayColor: AppColors.primary.withOpacity(0.12),
          ),
          child: SizedBox(
            height: 26,
            child: Slider(
              value: value,
              min: min,
              max: max,
              divisions: divisions,
              onChanged: onChanged,
            ),
          ),
        ),
      ],
    );
  }
}

// =============================================================================
// MLOps Page — Treino de CNN com dados do Supabase
// =============================================================================

