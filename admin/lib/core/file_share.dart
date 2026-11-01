import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/widgets.dart';
import 'package:share_plus/share_plus.dart';

const csvMime = 'text/csv';
const xlsxMime =
    'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet';

/// Excel only detects UTF-8 (₹, Indian names) when the file starts with a BOM.
Uint8List csvBytes(String csv) {
  final body = utf8.encode(csv);
  if (csv.startsWith('\uFEFF')) return Uint8List.fromList(body);
  return Uint8List.fromList([0xEF, 0xBB, 0xBF, ...body]);
}

/// Hands a generated file to the system share sheet (Save to Files, Drive,
/// email, WhatsApp…). On web it falls back to a download.
Future<void> shareFile(
  BuildContext context,
  Uint8List bytes, {
  required String filename,
  required String mimeType,
}) async {
  final box = context.findRenderObject() as RenderBox?;
  final origin = box != null && box.hasSize
      ? box.localToGlobal(Offset.zero) & box.size
      : null;
  await SharePlus.instance.share(
    ShareParams(
      files: [XFile.fromData(bytes, name: filename, mimeType: mimeType)],
      fileNameOverrides: [filename],
      subject: filename,
      sharePositionOrigin: origin,
    ),
  );
}
