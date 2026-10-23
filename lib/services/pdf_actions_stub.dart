import 'dart:typed_data';
import 'package:printing/printing.dart';

Future<void> downloadPdfBytes(Uint8List bytes, String filename) =>
    Printing.sharePdf(bytes: bytes, filename: filename);

Future<void> printPdfBytes(Uint8List bytes, String filename) =>
    Printing.layoutPdf(name: filename, onLayout: (_) async => bytes);