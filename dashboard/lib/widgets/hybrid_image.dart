import 'package:flutter/material.dart';

/// Widget que tenta carregar imagem da cloud (Firebase Storage).
/// Se falhar (sem internet ou URL vazio), faz fallback para o servidor local.
class HybridImage extends StatelessWidget {
  final String? cloudUrl;
  final String? localUrl;
  final BoxFit fit;
  final double? width;
  final double? height;
  final Widget? errorWidget;

  const HybridImage({
    Key? key,
    this.cloudUrl,
    this.localUrl,
    this.fit = BoxFit.cover,
    this.width,
    this.height,
    this.errorWidget,
  }) : super(key: key);

  /// Constrói um HybridImage diretamente a partir do nome do ficheiro local.
  /// Ex: HybridImage.fromFilename('Baldwin (151)_mask.png')
  factory HybridImage.fromFilename(
    String filename, {
    String? cloudUrl,
    BoxFit fit = BoxFit.cover,
    double? width,
    double? height,
  }) {
    // Codifica o nome do ficheiro para URL (trata espaços e parênteses)
    final encoded = Uri.encodeComponent(filename);
    return HybridImage(
      cloudUrl: cloudUrl,
      localUrl: 'http://localhost:8000/$encoded',
      fit: fit,
      width: width,
      height: height,
    );
  }

  @override
  Widget build(BuildContext context) {
    // Se tiver URL da cloud válido, tenta cloud primeiro
    final hasCloud = cloudUrl != null && cloudUrl!.isNotEmpty;
    final hasLocal = localUrl != null && localUrl!.isNotEmpty;

    if (!hasCloud && !hasLocal) {
      return _placeholder();
    }

    // URL preferida: cloud. Fallback: local.
    final primaryUrl = hasCloud ? cloudUrl! : localUrl!;
    final fallbackUrl = hasCloud && hasLocal ? localUrl : null;

    return Image.network(
      primaryUrl,
      fit: fit,
      width: width,
      height: height,
      loadingBuilder: (context, child, progress) {
        if (progress == null) return child;
        return _loadingIndicator(progress);
      },
      errorBuilder: (context, error, stackTrace) {
        // Falhou a cloud → tenta o servidor local
        if (fallbackUrl != null) {
          return Image.network(
            fallbackUrl,
            fit: fit,
            width: width,
            height: height,
            errorBuilder: (_, __, ___) =>
                errorWidget ?? _placeholder(),
          );
        }
        return errorWidget ?? _placeholder();
      },
    );
  }

  Widget _loadingIndicator(ImageChunkEvent progress) {
    return Container(
      width: width,
      height: height,
      color: Colors.black12,
      child: Center(
        child: CircularProgressIndicator(
          value: progress.expectedTotalBytes != null
              ? progress.cumulativeBytesLoaded /
                  progress.expectedTotalBytes!
              : null,
          strokeWidth: 2,
          color: Colors.green,
        ),
      ),
    );
  }

  Widget _placeholder() {
    return Container(
      width: width,
      height: height,
      color: Colors.black26,
      child: const Icon(Icons.apple, color: Colors.white24, size: 40),
    );
  }
}
