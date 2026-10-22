import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:file_picker/file_picker.dart';
import 'package:xml/xml.dart';

import '../models.dart';

/// ورقة من ملف Excel بعد قراءتها كنصوص.
class XlsxSheet {
  final String name;
  final List<List<String>> rows;
  XlsxSheet(this.name, this.rows);
}

/// قارئ xlsx متسامح: يقرأ مباشرة من XML داخل الملف، ويتحمّل الملفات المولّدة من
/// Google Sheets و openpyxl و LibreOffice (خلايا inlineStr فارغة، غياب sharedStrings،
/// معادلات بلا قيم محسوبة، خلايا متفرقة...).
class XlsxReader {
  XlsxReader._();

  static const _rel =
      'http://schemas.openxmlformats.org/officeDocument/2006/relationships';

  static List<XlsxSheet> read(Uint8List bytes) {
    if (bytes.length < 4 || bytes[0] != 0x50 || bytes[1] != 0x4B) {
      throw AppException(
          'الملف ليس بصيغة Excel (xlsx). إن كان ملف Google Sheets فنزّله أولاً: ملف ← تنزيل ← Microsoft Excel (.xlsx)');
    }
    final Archive zip;
    try {
      zip = ZipDecoder().decodeBytes(bytes);
    } catch (_) {
      throw AppException('ملف Excel تالف أو غير مكتمل التحميل');
    }
    String? text(String path) {
      final f = zip.findFile(path) ?? zip.findFile('/$path');
      if (f == null) return null;
      return utf8.decode(f.content as List<int>, allowMalformed: true);
    }

    // النصوص المشتركة (قد لا توجد)
    final shared = <String>[];
    final ss = text('xl/sharedStrings.xml');
    if (ss != null) {
      final doc = XmlDocument.parse(ss);
      for (final si in doc.findAllElements('si')) {
        shared.add(si.findAllElements('t').map((t) => t.innerText).join());
      }
    }

    // أسماء الأوراق ومساراتها
    final sheets = <(String, String)>[];
    final wb = text('xl/workbook.xml');
    final relsTxt = text('xl/_rels/workbook.xml.rels');
    final rels = <String, String>{};
    if (relsTxt != null) {
      for (final r in XmlDocument.parse(relsTxt).findAllElements('Relationship')) {
        final id = r.getAttribute('Id');
        var t = r.getAttribute('Target') ?? '';
        if (t.startsWith('/')) {
          t = t.substring(1);
        } else if (!t.startsWith('xl/')) {
          t = 'xl/$t';
        }
        if (id != null) rels[id] = t;
      }
    }
    if (wb != null) {
      var i = 0;
      for (final s in XmlDocument.parse(wb).findAllElements('sheet')) {
        i++;
        final rid = s.getAttribute('id', namespace: _rel) ??
            s.attributes
                .where((a) => a.name.local == 'id')
                .map((a) => a.value)
                .firstOrNull;
        final path = rels[rid] ?? 'xl/worksheets/sheet$i.xml';
        sheets.add((s.getAttribute('name') ?? 'Sheet$i', path));
      }
    }
    if (sheets.isEmpty) {
      for (final f in zip.files) {
        if (f.name.startsWith('xl/worksheets/') && f.name.endsWith('.xml')) {
          sheets.add((f.name.split('/').last.replaceAll('.xml', ''), f.name));
        }
      }
    }

    final out = <XlsxSheet>[];
    for (final (name, path) in sheets) {
      final x = text(path);
      if (x == null) continue;
      out.add(XlsxSheet(name, _rows(XmlDocument.parse(x), shared)));
    }
    return out;
  }

  static int _colIndex(String ref) {
    var n = 0;
    for (final ch in ref.codeUnits) {
      if (ch >= 65 && ch <= 90) {
        n = n * 26 + (ch - 64);
      } else if (ch >= 97 && ch <= 122) {
        n = n * 26 + (ch - 96);
      } else {
        break;
      }
    }
    return n - 1;
  }

  static String _num(String v) {
    final d = double.tryParse(v);
    if (d == null) return v;
    if (d == d.roundToDouble() && d.abs() < 1e15) return d.toInt().toString();
    return d.toString();
  }

  static List<List<String>> _rows(XmlDocument doc, List<String> shared) {
    final rows = <List<String>>[];
    var nextRow = 0;
    for (final r in doc.findAllElements('row')) {
      final rn = int.tryParse(r.getAttribute('r') ?? '');
      final idx = rn != null ? rn - 1 : nextRow;
      nextRow = idx + 1;
      while (rows.length <= idx) {
        rows.add(<String>[]);
      }
      final cells = rows[idx];
      var nextCol = 0;
      for (final c in r.findElements('c')) {
        final ref = c.getAttribute('r');
        final col = ref != null ? _colIndex(ref) : nextCol;
        nextCol = col + 1;
        final t = c.getAttribute('t');
        final v = c.getElement('v')?.innerText ?? '';
        String val;
        switch (t) {
          case 's':
            final i = int.tryParse(v.trim());
            val = (i != null && i >= 0 && i < shared.length) ? shared[i] : '';
          case 'inlineStr':
            val = c.findAllElements('t').map((e) => e.innerText).join();
            if (val.isEmpty) val = v;
          case 'str':
          case 'e':
            val = v;
          case 'b':
            val = v == '1' ? 'TRUE' : (v.isEmpty ? '' : 'FALSE');
          default:
            val = v.isEmpty ? '' : _num(v.trim());
        }
        while (cells.length <= col) {
          cells.add('');
        }
        cells[col] = val.trim();
      }
    }
    return rows;
  }

  /// يختار ملف Excel من الهاتف أو Google Drive ويعيد أوراقه، أو null عند الإلغاء.
  static Future<List<XlsxSheet>?> pick() async {
    final r = await FilePicker.platform.pickFiles(
      type: FileType.any,
      withData: true,
    );
    if (r == null || r.files.isEmpty) return null;
    final f = r.files.single;
    var bytes = f.bytes;
    if ((bytes == null || bytes.isEmpty) && f.path != null) {
      bytes = await File(f.path!).readAsBytes();
    }
    if (bytes == null || bytes.isEmpty) {
      throw AppException(
          'تعذّر تحميل الملف. إن كان على Google Drive فتأكد من الاتصال بالإنترنت وأعد المحاولة');
    }
    final name = f.name.toLowerCase();
    if (name.endsWith('.xls') || name.endsWith('.csv')) {
      throw AppException(
          'صيغة ${name.split('.').last} غير مدعومة؛ احفظ الملف بصيغة xlsx (Excel الحديثة)');
    }
    return read(bytes);
  }
}
