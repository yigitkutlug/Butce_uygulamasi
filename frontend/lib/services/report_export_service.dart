import 'dart:io';
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

class ReportExportService {
  Future<String> saveCsv(Uint8List bytes, {String? fileName}) async {
    final dir = await getApplicationDocumentsDirectory();
    final name = fileName ?? 'budget_report_${DateTime.now().millisecondsSinceEpoch}.csv';
    final file = File('${dir.path}\\$name');
    await file.writeAsBytes(bytes, flush: true);
    return file.path;
  }

  Future<String> savePdfFromMonthly({
    required List<Map<String, dynamic>> monthly,
    required String currencySymbol,
    String? fileName,
  }) async {
    final pdf = pw.Document();
    final generatedAt = DateTime.now();

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        build: (context) => [
          pw.Text('Budget Tracker Report', style: pw.TextStyle(fontSize: 20, fontWeight: pw.FontWeight.bold)),
          pw.SizedBox(height: 8),
          pw.Text('Generated: ${generatedAt.toIso8601String()}'),
          pw.SizedBox(height: 16),
          pw.Table.fromTextArray(
            headers: const ['Month', 'Income', 'Expense', 'Net'],
            data: monthly.map((m) {
              final income = (m['income'] as num? ?? 0).toDouble();
              final expense = (m['expense'] as num? ?? 0).toDouble();
              final net = income - expense;
              return [
                m['month']?.toString() ?? '',
                '${income.toStringAsFixed(2)} $currencySymbol',
                '${expense.toStringAsFixed(2)} $currencySymbol',
                '${net.toStringAsFixed(2)} $currencySymbol',
              ];
            }).toList(),
          ),
        ],
      ),
    );

    final bytes = await pdf.save();
    final dir = await getApplicationDocumentsDirectory();
    final name = fileName ?? 'budget_report_${DateTime.now().millisecondsSinceEpoch}.pdf';
    final file = File('${dir.path}\\$name');
    await file.writeAsBytes(bytes, flush: true);
    return file.path;
  }
}

