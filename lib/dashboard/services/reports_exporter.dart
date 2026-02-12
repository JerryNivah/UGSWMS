import 'reports_exporter_stub.dart'
    if (dart.library.html) 'reports_exporter_web.dart';

Future<void> downloadTextFile({
  required String filename,
  required String content,
  required String mime,
}) {
  return downloadTextFileImpl(
    filename: filename,
    content: content,
    mime: mime,
  );
}
