import 'ocr_parser.dart';

/// クラウドOCRの差し替え口。実装は Edge Function かテスト用のフェイク。
class CloudOcrResponse {
  const CloudOcrResponse({this.text, this.fields});
  final String? text;
  final List<OcrField>? fields;
}

abstract class CloudOcrClient {
  Future<CloudOcrResponse> recognize(List<int> imageBytes, {required String mimeType});
}

class OcrRunResult {
  const OcrRunResult({
    required this.fields,
    required this.format,
    required this.usedCloud,
    required this.queuedCloud,
    this.message,
  });

  final List<OcrField> fields;
  final String format;
  final bool usedCloud;
  final bool queuedCloud;
  final String? message;
}

/// 定型は端末内テキスト、手書きはオンラインならクラウド、圏外なら端末内に退避。
Future<OcrRunResult> runOcr({
  required String onDeviceText,
  required String formatChoice,
  required bool online,
  CloudOcrClient? cloud,
  List<int>? imageBytes,
}) async {
  final detected = formatChoice == 'auto'
      ? (OcrParser.looksLikeTemplate(onDeviceText) ? 'template' : 'handwritten')
      : formatChoice;

  if (detected == 'handwritten' && online && cloud != null && imageBytes != null) {
    try {
      final remote = await cloud.recognize(imageBytes, mimeType: 'image/jpeg');
      if (remote.fields != null && remote.fields!.isNotEmpty) {
        return OcrRunResult(fields: remote.fields!, format: 'handwritten', usedCloud: true, queuedCloud: false);
      }
      final remoteText = remote.text?.trim() ?? '';
      if (remoteText.isNotEmpty) {
        return OcrRunResult(
          fields: OcrParser.parse(remoteText, format: 'handwritten'),
          format: 'handwritten',
          usedCloud: true,
          queuedCloud: false,
        );
      }
    } catch (_) {
      // クラウド失敗時は端末内の読み取りに戻す。
    }
  }

  final queued = detected == 'handwritten' && !online;
  return OcrRunResult(
    fields: OcrParser.parse(onDeviceText, format: detected == 'template' ? 'template' : 'handwritten'),
    format: detected == 'template' ? 'template' : 'handwritten',
    usedCloud: false,
    queuedCloud: queued,
    message: queued ? 'オフラインのため手書きOCRは通信復帰後に実行します。読み取れた範囲を確認し、足りない項目は手入力してください。' : null,
  );
}
