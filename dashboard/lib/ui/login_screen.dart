import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'dart:math';
import '../providers/auth_provider.dart';
import '../providers/dashboard_provider.dart';
import '../widgets/lote_picker_dialog.dart';
import '../utils/constants.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({Key? key}) : super(key: key);

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final TextEditingController _userController = TextEditingController();
  final TextEditingController _passController = TextEditingController();
  bool _isLoading = false;

  void _handleLogin() async {
    final username = _userController.text.trim();
    final password = _passController.text;

    if (username.isEmpty || password.isEmpty) {
      _showError('Preencha utilizador e palavra-passe');
      return;
    }

    setState(() => _isLoading = true);

    try {
      final success = await ref.read(authProvider.notifier).login(username, password);

      if (!mounted) return;

      if (!success) {
        _showError('Utilizador ou palavra-passe inválido');
        setState(() => _isLoading = false);
        return;
      }

      setState(() => _isLoading = false);

      if (!mounted) return;
      final loggedInUser = ref.read(authProvider);

      if (loggedInUser != null && loggedInUser.role == UserRole.admin) {
        // Gestor: vê tudo, todos os lotes agregados — não escolhe lote nenhum.
        ref.read(currentPageProvider.notifier).setPage('Visão Geral');
        ref.read(sessionActiveProvider.notifier).setActive(true);
        final batches = ref.read(availableBatchesProvider);
        if (batches.isNotEmpty) ref.read(batchProvider.notifier).setBatch(batches.first);
        ref.read(currentPageProvider.notifier).setPage('Controlo do Pomar');
      } else {
        // Operador: obrigatório escolher o lote da triagem ativa antes de
        // entrar no Triagem Manual (pode voltar a mudá-lo mais tarde, a partir de lá).
        // Na vida real, a UI de lote limitaria a um lote, mas aqui deixamos em aberto.
        await showLotePickerDialog(context, username: username, mandatory: true);
        if (!mounted) return;
        ref.read(currentPageProvider.notifier).setPage('Triagem Manual');
      }
    } catch (e) {
      if (!mounted) return;
      _showError('Erro ao fazer login: $e');
      setState(() => _isLoading = false);
    }
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red.shade700,
        duration: const Duration(seconds: 3),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: Row(
        children: [
          // Left side: Login Panel
          Expanded(
            flex: 1,
            child: Center(
              child: Container(
                constraints: const BoxConstraints(maxWidth: 400),
                padding: const EdgeInsets.symmetric(horizontal: 40),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Icon(Icons.eco, size: 64, color: AppColors.healthy),
                    const SizedBox(height: 16),
                    Text(
                      'Apple Quality\nPlatform',
                      style: TextStyle(
                        fontSize: 32,
                        fontWeight: FontWeight.bold,
                        color: AppColors.textPrimary,
                        height: 1.2,
                        letterSpacing: -0.5,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 64),
                    Text(
                      'Login (admin ou operator)',
                      style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
                      textAlign: TextAlign.left,
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _userController,
                      style: TextStyle(color: AppColors.textPrimary),
                      decoration: InputDecoration(
                        filled: true,
                        fillColor: AppColors.surface,
                        hintText: 'Nome de Utilizador',
                        hintStyle: TextStyle(color: AppColors.isDark ? Colors.white24 : Colors.black26, fontSize: 14),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
                      ),
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: _passController,
                      style: TextStyle(color: AppColors.textPrimary),
                      obscureText: true,
                      decoration: InputDecoration(
                        filled: true,
                        fillColor: AppColors.surface,
                        hintText: 'Palavra-passe',
                        hintStyle: TextStyle(color: AppColors.isDark ? Colors.white24 : Colors.black26, fontSize: 14),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
                      ),
                    ),
                    const SizedBox(height: 32),
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.healthy,
                        foregroundColor: AppColors.isDark ? Colors.white : Colors.black,
                        padding: const EdgeInsets.symmetric(vertical: 20),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                        elevation: 0,
                        disabledBackgroundColor: AppColors.healthy.withValues(alpha: 0.5),
                      ),
                      onPressed: _isLoading ? null : _handleLogin,
                      child: _isLoading
                          ? const SizedBox(
                              height: 20,
                              width: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Text('Entrar', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                    ),
                    const SizedBox(height: 24),
                    Text(
                      'Sistema On-Premise e Cloud',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
                    )
                  ],
                ),
              ),
            ),
          ),
          // Right side: Branding/Image
          Expanded(
            flex: 1,
            child: Container(
              color: AppColors.surface,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  // Dynamic custom-painted animated tree
                  const Positioned.fill(
                    child: _TreeGraphic(),
                  ),
                  // Translucent gradient overlay for readability and premium visual depth
                  Positioned.fill(
                    child: Container(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            AppColors.surface.withValues(alpha: 0.15),
                            AppColors.surface.withValues(alpha: 0.65),
                          ],
                        ),
                      ),
                    ),
                  ),
                  // Title 'Pomaric'
                  Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        'Pomaric',
                        style: TextStyle(
                          fontSize: 64,
                          fontWeight: FontWeight.bold,
                          color: AppColors.textPrimary,
                          letterSpacing: -1.5,
                          shadows: [
                            Shadow(
                              color: AppColors.primary.withValues(alpha: 0.5),
                              blurRadius: 20,
                              offset: const Offset(0, 0),
                            ),
                            Shadow(
                              color: Colors.black.withValues(alpha: 0.8),
                              blurRadius: 10,
                              offset: const Offset(2, 4),
                            ),
                          ],
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Apple Quality Triaging & Analytics',
                        style: TextStyle(
                          color: AppColors.textSecondary.withValues(alpha: 0.8),
                          fontSize: 14,
                          letterSpacing: 1.5,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          )
        ],
      ),
    );
  }
}

// ═══ STATIC APPLE TREE FOR BRANDING ═══
class _TreeGraphic extends StatelessWidget {
  const _TreeGraphic();

  @override
  Widget build(BuildContext context) {
    return const CustomPaint(
      painter: _TreePainter(),
    );
  }
}

class _TreePainter extends CustomPainter {
  const _TreePainter();

  @override
  void paint(Canvas canvas, Size size) {
    final start = Offset(size.width / 2, size.height);
    final paint = Paint()
      ..color = AppColors.accent.withValues(alpha: 0.45)
      ..strokeCap = StrokeCap.round;

    final trunkLength = size.height * 0.22;
    _drawBranch(canvas, paint, start, trunkLength, pi / 2, 8.0, 8);
  }

  void _drawBranch(
    Canvas canvas,
    Paint paint,
    Offset start,
    double length,
    double angle,
    double thickness,
    int depth,
  ) {
    if (depth == 0 || length < 2) {
      final leafPaint = Paint()
        ..color = AppColors.healthy.withValues(alpha: 0.8)
        ..style = PaintingStyle.fill;
      
      // Draw a leafy green cluster
      canvas.drawCircle(start, 6.0, leafPaint);
      canvas.drawCircle(start + const Offset(-4, -2), 5.0, leafPaint);
      canvas.drawCircle(start + const Offset(4, -2), 5.0, leafPaint);

      // Draw a small brown stem hanging downwards
      final stemPaint = Paint()
        ..color = const Color(0xFF7A5C33) // Brown branch color
        ..strokeWidth = 1.0
        ..style = PaintingStyle.stroke;
      final appleStart = start + const Offset(0, 2);
      final appleEnd = start + const Offset(0, 9);
      canvas.drawLine(appleStart, appleEnd, stemPaint);

      // Draw a red apple at the end of the stem (hanging below the leaves)
      final applePaint = Paint()
        ..color = Colors.redAccent.withValues(alpha: 0.95)
        ..style = PaintingStyle.fill;
      canvas.drawCircle(appleEnd, 4.0, applePaint);

      // Add a tiny glossy white reflection dot on the apple
      final highlightPaint = Paint()
        ..color = Colors.white.withValues(alpha: 0.6)
        ..style = PaintingStyle.fill;
      canvas.drawCircle(appleEnd + const Offset(-1.0, -1.0), 0.8, highlightPaint);
      return;
    }

    final endX = start.dx + length * cos(angle);
    final endY = start.dy - length * sin(angle);
    final end = Offset(endX, endY);

    paint.strokeWidth = thickness;
    paint.color = AppColors.accent.withValues(alpha: (0.15 + (depth * 0.05)).clamp(0.15, 0.6));
    canvas.drawLine(start, end, paint);

    const splitAngle = 22 * pi / 180;
    _drawBranch(canvas, paint, end, length * 0.75, angle + splitAngle, thickness * 0.72, depth - 1);
    _drawBranch(canvas, paint, end, length * 0.75, angle - splitAngle, thickness * 0.72, depth - 1);
  }

  @override
  bool shouldRepaint(covariant _TreePainter oldDelegate) => false;
}