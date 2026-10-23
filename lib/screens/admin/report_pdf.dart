import 'dart:typed_data';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

String _two(int n) => n.toString().padLeft(2, '0');

String _stamp(DateTime d) =>
    '${d.year}-${_two(d.month)}-${_two(d.day)} ${_two(d.hour)}:${_two(d.minute)}';

String _fileName(String title) {
  final d = DateTime.now();
  final slug = title
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9]+'), '_')
      .replaceAll(RegExp(r'^_+|_+$'), '');
  return '${slug.isEmpty ? 'report' : slug}_${d.year}${_two(d.month)}${_two(d.day)}.pdf';
}

/// Builds an A4 PDF from a plain-text report (the same text you copy).
Future<List<int>> buildReportPdf({
  required String title,
  required String body,
}) async {
  // Noto Sans supports the peso sign and accented letters; the built-in
  // PDF fonts do not.
  final regular = await PdfGoogleFonts.notoSansRegular();
  final bold = await PdfGoogleFonts.notoSansBold();

  final doc = pw.Document(
    theme: pw.ThemeData.withFont(base: regular, bold: bold),
  );

  doc.addPage(
    pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(36),
      footer: (ctx) => pw.Align(
        alignment: pw.Alignment.centerRight,
        child: pw.Text(
          'Page ${ctx.pageNumber} of ${ctx.pagesCount}',
          style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey700),
        ),
      ),
      build: (ctx) => [
        pw.Text('SARAP',
            style: pw.TextStyle(
                fontSize: 11, color: PdfColors.deepOrange, fontWeight: pw.FontWeight.bold)),
        pw.SizedBox(height: 2),
        pw.Text(title,
            style: pw.TextStyle(fontSize: 20, fontWeight: pw.FontWeight.bold)),
        pw.SizedBox(height: 4),
        pw.Text('Generated ${_stamp(DateTime.now())}',
            style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey700)),
        pw.Divider(color: PdfColors.grey400),
        pw.SizedBox(height: 6),
        ...body.split('\n').map(
              (line) => line.trim().isEmpty
                  ? pw.SizedBox(height: 8)
                  : pw.Padding(
                      padding: const pw.EdgeInsets.only(bottom: 2),
                      child: pw.Text(line, style: const pw.TextStyle(fontSize: 11)),
                    ),
            ),
      ],
    ),
  );

  return doc.save();
}

/// Opens the browser's print preview. In it, choose "Save as PDF" as the
/// destination to keep a PDF copy, or pick a printer to print.
Future<void> printReport({required String title, required String body}) async {
  await Printing.layoutPdf(
    name: _fileName(title),
    onLayout: (_) async {
      final bytes = await buildReportPdf(title: title, body: body);
      return Uint8List.fromList(bytes);
    },
  );
}

/// Downloads the PDF straight to the computer (no print dialog).
Future<void> downloadReportPdf({required String title, required String body}) async {
  final bytes = await buildReportPdf(title: title, body: body);
  await Printing.sharePdf(
    bytes: Uint8List.fromList(bytes),
    filename: _fileName(title),
  );
}