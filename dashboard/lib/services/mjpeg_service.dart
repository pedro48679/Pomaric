import 'dart:async';
import 'dart:typed_data';
import 'package:http/http.dart' as http;

/// Faz streaming de um feed MJPEG (multipart/x-mixed-replace) e emite
/// cada frame JPEG como [Uint8List] num [Stream].
///
/// Uso:
/// ```dart
/// final svc = MjpegService();
/// svc.start('http://192.168.43.149:8000/stream.mjpg');
/// svc.stream.listen((frame) => setState(() => _frame = frame));
/// // quando terminar:
/// svc.stop();
/// ```
class MjpegService {
  final _buffer = <int>[];
  StreamController<Uint8List>? _controller;
  http.Client? _client;
  bool _running = false;

  /// Stream de frames JPEG. Ativo após [start] e fechado por [stop].
  Stream<Uint8List> get stream {
    _controller ??= StreamController<Uint8List>.broadcast();
    return _controller!.stream;
  }

  /// Inicia a ligação ao URL MJPEG e começa a emitir frames.
  /// Reconecta automaticamente se a ligação cair.
  void start(String url) {
    if (_running) return;
    _running = true;
    _buffer.clear();
    _controller = StreamController<Uint8List>.broadcast();
    _client = http.Client();
    _connect(url); // fire-and-forget: reconexão gerida internamente
  }

  Future<void> _connect(String url) async {
    while (_running) {
      try {
        final request = http.Request('GET', Uri.parse(url));
        final response = await _client!.send(request);
        // Sem isto, um 404/403/redirect (corpo que termina de imediato, sem
        // exceção) completava o await-for e o while reconectava em loop
        // apertado sem nenhum delay, retry storm contra o Pi.
        if (response.statusCode != 200) {
          throw http.ClientException('MJPEG HTTP ${response.statusCode}', Uri.parse(url));
        }

        await for (final chunk in response.stream) {
          if (!_running) return;
          _buffer.addAll(chunk);
          _extractFrames();
          // Previne crescimento ilimitado do buffer (ex: leitura mais lenta que chegada)
          if (_buffer.length > 2 * 1024 * 1024) {
            _buffer.removeRange(0, _buffer.length - 512 * 1024);
          }
        }
      } catch (_) {
        // backoff no caminho de exceção; o delay incondicional está abaixo
      }
      // Backoff SEMPRE entre tentativas de reconexão, também cobre o caso
      // de um stream 200 que termina logo (servidor a rejeitar sem erro).
      if (_running) await Future.delayed(const Duration(seconds: 2));
    }
  }

  /// Procura marcadores SOI (FF D8) e EOI (FF D9) para extrair frames JPEG completos.
  void _extractFrames() {
    while (true) {
      // Encontrar início de frame JPEG (SOI)
      int soiIdx = -1;
      for (int i = 0; i < _buffer.length - 1; i++) {
        if (_buffer[i] == 0xFF && _buffer[i + 1] == 0xD8) {
          soiIdx = i;
          break;
        }
      }
      if (soiIdx < 0) break;

      // Encontrar fim de frame JPEG (EOI) após o SOI
      int eoiIdx = -1;
      for (int i = soiIdx + 2; i < _buffer.length - 1; i++) {
        if (_buffer[i] == 0xFF && _buffer[i + 1] == 0xD9) {
          eoiIdx = i + 1; // inclusive
          break;
        }
      }
      if (eoiIdx < 0) break; // frame incompleto, aguardar mais dados

      final ctrl = _controller;
      if (ctrl != null && !ctrl.isClosed) {
        ctrl.add(Uint8List.fromList(_buffer.sublist(soiIdx, eoiIdx + 1)));
      }
      _buffer.removeRange(0, eoiIdx + 1);
    }
  }

  /// Para o streaming e liberta todos os recursos (HTTP client + stream controller).
  /// Seguro para chamar múltiplas vezes.
  void stop() {
    _running = false;
    _client?.close();
    _client = null;
    _buffer.clear();
    _controller?.close();
    _controller = null;
  }
}
