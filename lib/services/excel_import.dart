import 'dart:typed_data';

import 'package:excel/excel.dart';
import 'package:share_plus/share_plus.dart';

import '../app_state.dart';
import '../config.dart';
import '../data/repo.dart';
import '../models.dart';
import 'xlsx_reader.dart';

/// أنواع البيانات التي ترفع من Excel.
enum ImportKind { structure, students, staff, courses }

String importKindName(ImportKind k) => switch (k) {
      ImportKind.structure => 'الكليات والأقسام',
      ImportKind.students => 'الطلاب',
      ImportKind.staff => 'الكادر (الهيئة الإدارية والتدريسية)',
      ImportKind.courses => 'المواد والخطة الدراسية',
    };

class ImportResult {
  int added = 0;
  int updated = 0;
  int skipped = 0;
  final List<String> errors = [];
  void error(int row, String msg) {
    skipped++;
    if (errors.length < 200) errors.add('صف $row: $msg');
  }
}

/// تطبيع النص العربي للمقارنة.
String norm(String s) => s
    .trim()
    .toLowerCase()
    .replaceAll(RegExp('[ً-ْـ]'), '')
    .replaceAll(RegExp('[أإآ]'), 'ا')
    .replaceAll('ة', 'ه')
    .replaceAll('ى', 'ي')
    .replaceAll(RegExp(r'\s+'), ' ');

/// الأعمدة المقبولة لكل حقل (يكفي تطابق أحد الأسماء).
const _fields = <ImportKind, Map<String, List<String>>>{
  ImportKind.students: {
    'id': ['الرقم المعرفي', 'الرقم الجامعي', 'رقم الطالب', 'الرقم', 'id', 'student id'],
    'name': ['اسم الطالب', 'الاسم', 'الاسم الرباعي', 'name'],
    'stage': ['المرحلة', 'stage', 'level'],
    'shift': ['الدوام', 'shift'],
    'dept': ['القسم', 'department', 'dept'],
    'email': ['البريد الجامعي', 'البريد', 'البريد الالكتروني', 'الايميل', 'الايميل الجامعي', 'email'],
    'password': ['كلمه المرور', 'كلمه المرور الاوليه', 'الباسورد', 'الرمز السري', 'password'],
  },
  ImportKind.staff: {
    'email': ['البريد الجامعي', 'البريد', 'البريد الالكتروني', 'الايميل', 'الايميل الجامعي', 'email'],
    'name': ['الاسم', 'الاسم الكامل', 'اسم التدريسي', 'اسم الدكتور', 'اسم الاستاذ', 'name'],
    'alias': ['اسم المستخدم', 'username', 'user'],
    'role': ['الصفه', 'الدور', 'المنصب', 'role'],
    'college': ['الكليه', 'college'],
    'dept': ['القسم', 'department', 'dept'],
    'password': ['كلمه المرور', 'كلمه المرور الاوليه', 'الباسورد', 'الرمز السري', 'password'],
  },
  ImportKind.courses: {
    'dept': ['القسم', 'department', 'dept'],
    'semester': ['الفصل الدراسي', 'semester'],
    'stage': ['المرحله', 'stage', 'level'],
    'term': ['الكورس', 'فصل السنه', 'term'],
    'code': ['رمز المقرر', 'رمز الماده', 'الرمز', 'code'],
    'nameAr': ['اسم الماده بالعربيه', 'اسم الماده', 'الماده', 'المقرر'],
    'nameEn': ['اسم الماده بالانجليزيه', 'اسم الماده بالانكليزيه', 'english name', 'name en'],
    'ects': ['ects', 'الوحدات'],
    'credits': ['الساعات المعتمده', 'الساعات', 'credits'],
    'prereqs': ['المتطلب السابق', 'المتطلبات السابقه', 'prerequisites', 'prereq'],
  },
  ImportKind.structure: {
    'college': ['الكليه', 'college'],
    'dept': ['القسم', 'اسم القسم', 'department'],
    'deptCode': ['رمز القسم', 'code'],
  },
};

/// صفوف القالب: العناوين + مثال.
const _templates = <ImportKind, List<List<String>>>{
  ImportKind.students: [
    ['الرقم المعرفي', 'اسم الطالب', 'القسم', 'المرحلة', 'الدوام', 'البريد الجامعي'],
    ['1989616052', 'ابرار منخي لفته كزار', 'هندسة الذكاء الاصطناعي', '2', 'صباحي', '1989616052@almaaqal.edu.iq'],
  ],
  ImportKind.staff: [
    ['البريد الجامعي', 'الاسم', 'اسم المستخدم', 'كلمة المرور', 'الصفة', 'الكلية', 'القسم'],
    ['ahmed.ali@almaaqal.edu.iq', 'أ.م.د. أحمد علي', 'doc30', 'MqProf#2024_30', 'تدريسي', 'كلية الهندسة', 'هندسة الذكاء الاصطناعي'],
    ['dean.eng@almaaqal.edu.iq', 'أ.د. عميد الكلية', 'dean01', '', 'عميد', 'كلية الهندسة', ''],
  ],
  ImportKind.courses: [
    ['القسم', 'المرحلة', 'الكورس', 'رمز المقرر', 'اسم المادة بالعربية', 'اسم المادة بالإنجليزية', 'الساعات المعتمدة', 'ECTS', 'المتطلب السابق'],
    ['هندسة الذكاء الاصطناعي', '2', 'الأول', 'ARIE211', 'بايثون للذكاء الاصطناعي 1', 'Python for AI I', '3', '7', 'ENG110'],
  ],
  ImportKind.structure: [
    ['الكلية', 'القسم', 'رمز القسم'],
    ['كلية الهندسة', 'هندسة الذكاء الاصطناعي', 'ai'],
  ],
};

class ExcelImporter {
  ExcelImporter._();

  static String _cell(Data? d) => cellText(d);

  static String cellText(Data? d) {
    final v = d?.value;
    if (v == null) return '';
    final String s = switch (v) {
      IntCellValue() => v.value.toString(),
      DoubleCellValue() => v.value == v.value.roundToDouble()
          ? v.value.toInt().toString()
          : v.value.toString(),
      BoolCellValue() => v.value.toString(),
      _ => v.toString(),
    };
    return s.trim();
  }

  /// يشارك قالب Excel فارغاً (مع مثال) لنوع البيانات.
  static Future<void> shareTemplate(ImportKind k) async {
    final x = Excel.createExcel();
    final sheet = x['Sheet1'];
    for (final row in _templates[k]!) {
      sheet.appendRow(row.map((e) => TextCellValue(e)).toList());
    }
    final bytes = x.encode();
    if (bytes == null) return;
    await Share.shareXFiles([
      XFile.fromData(Uint8List.fromList(bytes),
          mimeType:
              'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
          name: 'template_${k.name}.xlsx')
    ], subject: 'قالب ${importKindName(k)}');
  }

  /// يختار ملفاً ويعيد السجلات (كل سجل خريطة حقل ← قيمة) مع رقم الصف.
  static Future<List<(int, Map<String, String>)>?> pickRecords(
      ImportKind k) async {
    final sheets = await XlsxReader.pick();
    if (sheets == null) return null;
    final fields = _fields[k]!;
    final out = <(int, Map<String, String>)>[];
    for (final sheet in sheets) {
      final sheetName = sheet.name;
      final rows = sheet.rows;
      // قيم افتراضية من اسم الورقة (مثل "المرحلة الثانية مسائي")
      final sn = norm(sheetName);
      final sheetStage = parseStage(sheetName) != null ? sheetName : null;
      final sheetShift =
          (sn.contains('مسائ') || sn.contains('صباح')) ? sheetName : null;
      // البحث عن صف العناوين ضمن أول 15 صفاً
      int headerAt = -1;
      Map<int, String> colField = {};
      for (var i = 0; i < rows.length && i < 15; i++) {
        final m = <int, String>{};
        for (var c = 0; c < rows[i].length; c++) {
          final h = norm(rows[i][c]);
          if (h.isEmpty) continue;
          for (final e in fields.entries) {
            if (m.containsValue(e.key)) continue;
            if (e.value.any((syn) => norm(syn) == h)) {
              m[c] = e.key;
              break;
            }
          }
        }
        if (m.length >= 2) {
          headerAt = i;
          colField = m;
          break;
        }
      }
      if (headerAt < 0) continue;
      for (var i = headerAt + 1; i < rows.length; i++) {
        final rec = <String, String>{};
        colField.forEach((c, f) {
          if (c < rows[i].length) {
            final v = rows[i][c];
            if (v.isNotEmpty) rec[f] = v;
          }
        });
        if (rec.isEmpty) continue;
        if (k == ImportKind.students) {
          if (sheetStage != null) rec.putIfAbsent('stage', () => sheetStage);
          if (sheetShift != null) rec.putIfAbsent('shift', () => sheetShift);
        }
        if (k == ImportKind.courses && !rec.containsKey('dept')) {
          rec['dept'] = sheetName; // أوراق الأقسام بلا عمود القسم
        }
        out.add((i + 1, rec));
      }
    }
    return out;
  }

  // ---------------- تحويل القيم ----------------
  static int? parseStage(String? v) {
    if (v == null) return null;
    final n = int.tryParse(v.replaceAll(RegExp(r'[^0-9]'), ''));
    if (n != null && n > 0 && n < 10) return n;
    final t = norm(v);
    const words = {'اولي': 1, 'ثانيه': 2, 'ثالثه': 3, 'رابعه': 4, 'خامسه': 5};
    for (final e in words.entries) {
      if (t.contains(e.key)) return e.value;
    }
    return null;
  }

  static int? parseTerm(String? v) {
    if (v == null) return null;
    final n = int.tryParse(v.trim());
    if (n == 1 || n == 2) return n;
    final t = norm(v);
    if (t.contains('اول') || t.contains('first')) return 1;
    if (t.contains('ثان') || t.contains('second')) return 2;
    return null;
  }

  static String parseShift(String? v) {
    final t = norm(v ?? '');
    return (t.contains('مسائ') || t.contains('evening')) ? 'evening' : 'morning';
  }

  static String parseRole(String? v) {
    final t = norm(v ?? '');
    if (t.contains('رئيس قسم') || t.contains('رئيس القسم') || t.contains('head')) {
      return 'head';
    }
    if (t.contains('عميد') || t.contains('dean')) return 'dean';
    if (t.contains('رئاسه') ||
        t.contains('رئيس الجامعه') ||
        t.contains('مجلس') ||
        t.contains('مساعد رئيس') ||
        t.contains('president')) {
      return 'president';
    }
    if (t.contains('مدير النظام') || t.contains('مدير نظام') || t == 'admin') {
      return 'admin';
    }
    return 'doctor';
  }

  static Department? findDept(List<Department> all, String? v) {
    if (v == null || v.trim().isEmpty) return null;
    final t = norm(v);
    for (final d in all) {
      if (norm(d.id) == t || norm(d.name) == t) return d;
    }
    for (final d in all) {
      final n = norm(d.name);
      if (n.contains(t) || t.contains(n)) return d;
    }
    return null;
  }

  static College? findCollege(List<College> all, String? v) {
    if (v == null || v.trim().isEmpty) return null;
    final t = norm(v);
    for (final c in all) {
      if (norm(c.id) == t || norm(c.name) == t) return c;
    }
    for (final c in all) {
      final n = norm(c.name);
      if (n.contains(t) || t.contains(n)) return c;
    }
    return null;
  }

  static String _slug(String prefix, String name) =>
      '${prefix}_${name.hashCode.toUnsigned(32).toRadixString(36)}';

  // ---------------- التنفيذ ----------------
  static Future<ImportResult> run(
      ImportKind k, List<(int, Map<String, String>)> records) async {
    return switch (k) {
      ImportKind.students => _students(records),
      ImportKind.staff => _staff(records),
      ImportKind.courses => _courses(records),
      ImportKind.structure => _structure(records),
    };
  }

  /// القسم الافتراضي حين لا يحدد الملف قسماً (لرئيس القسم).
  static String? get _defaultDept {
    final d = AppState.scope.deptIds;
    return (d != null && d.length == 1) ? d.first : null;
  }

  static Future<ImportResult> _students(
      List<(int, Map<String, String>)> recs) async {
    final res = ImportResult();
    final depts = await repo.departments();
    final existing = {for (final s in await repo.students()) s.id: s};
    final scope = AppState.scope;
    final out = <String, Student>{};
    for (final (row, r) in recs) {
      final id = r['id'];
      final name = r['name'];
      if (id == null || name == null) {
        res.error(row, 'الرقم المعرفي والاسم مطلوبان');
        continue;
      }
      String? deptId;
      if (r['dept'] != null) {
        final d = findDept(depts, r['dept']);
        if (d == null) {
          res.error(row, 'القسم "${r['dept']}" غير معرّف');
          continue;
        }
        deptId = d.id;
      }
      final old = existing[id];
      deptId ??= old?.deptId ?? _defaultDept;
      if (!scope.isAll && !scope.hasDept(deptId)) {
        res.error(row, 'الطالب خارج نطاق صلاحيتك');
        continue;
      }
      final email = r['email']?.toLowerCase();
      if (email != null && !AppConfig.isUniversityEmail(email)) {
        res.error(row, 'البريد ليس جامعياً: $email');
        continue;
      }
      final s = Student(
        id: id,
        name: name,
        stage: parseStage(r['stage']) ?? old?.stage ?? 1,
        shift: r['shift'] != null ? parseShift(r['shift']) : (old?.shift ?? 'morning'),
        deptId: deptId,
        email: email ?? old?.email,
        nfcUid: old?.nfcUid,
        activated: old?.activated ?? false,
        initPw: r['password'] != null
            ? hashPassword(id, r['password']!)
            : old?.initPw,
      );
      out[s.id] = s; // آخر ظهور للرقم هو المعتمد
    }
    for (final id in out.keys) {
      existing.containsKey(id) ? res.updated++ : res.added++;
    }
    if (out.isNotEmpty) await repo.saveStudentsBulk(out.values.toList());
    return res;
  }

  static Future<ImportResult> _staff(
      List<(int, Map<String, String>)> recs) async {
    final res = ImportResult();
    final depts = await repo.departments();
    final colleges = await repo.colleges();
    final existing = {for (final s in await repo.staff()) s.id: s};
    final me = AppState.user.value?.staff;
    final myRole = me?.roleEnum ?? Role.doctor;
    final scope = AppState.scope;
    final out = <Staff>[];
    for (final (row, r) in recs) {
      final email = r['email']?.toLowerCase();
      final name = r['name'];
      if (email == null || name == null) {
        res.error(row, 'البريد والاسم مطلوبان');
        continue;
      }
      if (!AppConfig.isValidEmail(email)) {
        res.error(row, 'صيغة البريد غير صحيحة: $email');
        continue;
      }
      if (r['alias']?.toLowerCase() == AppConfig.bootstrapAdminUsername) {
        res.error(row, 'اسم المستخدم "admin" محجوز لمدير النظام');
        continue;
      }
      final role = parseRole(r['role']);
      // من يحق له إضافة من؟
      final allowed = switch (myRole) {
        Role.admin => true,
        Role.president => role != 'admin',
        Role.dean => role == 'head' || role == 'doctor',
        Role.head => role == 'doctor',
        _ => false,
      };
      if (!allowed) {
        res.error(row, 'لا تملك صلاحية إضافة "${roleName(role)}"');
        continue;
      }
      final d = findDept(depts, r['dept']);
      if (r['dept'] != null && d == null) {
        res.error(row, 'القسم "${r['dept']}" غير معرّف');
        continue;
      }
      var c = findCollege(colleges, r['college']);
      if (c == null && d != null) {
        c = colleges.where((x) => x.id == d.collegeId).firstOrNull;
      }
      final deptId = d?.id ?? (role == 'doctor' || role == 'head' ? _defaultDept : null);
      if ((role == 'doctor' || role == 'head') && !scope.hasDept(deptId)) {
        res.error(row, 'القسم خارج نطاق صلاحيتك');
        continue;
      }
      if (role == 'dean' && (c == null || !scope.hasCollege(c.id))) {
        res.error(row, 'حدد كلية العميد (ضمن صلاحيتك)');
        continue;
      }
      final old = existing[email];
      out.add(Staff(
        id: email,
        name: name,
        role: role,
        collegeId: c?.id ?? old?.collegeId,
        deptId: deptId ?? old?.deptId,
        courseIds: old?.courseIds ?? const [],
        alias: r['alias'] ?? old?.alias,
        activated: old?.activated ?? false,
        initPw: r['password'] != null
            ? hashPassword(email.split('@').first, r['password']!)
            : old?.initPw,
      ));
      old == null ? res.added++ : res.updated++;
    }
    if (out.isNotEmpty) await repo.saveStaffBulk(out);
    return res;
  }

  static Future<ImportResult> _courses(
      List<(int, Map<String, String>)> recs) async {
    final res = ImportResult();
    final depts = await repo.departments();
    final existing = {for (final c in await repo.courses()) c.id: c};
    final scope = AppState.scope;
    final out = <String, Course>{};
    for (final (row, r) in recs) {
      final code = r['code']?.toUpperCase().replaceAll(' ', '');
      final nameAr = r['nameAr'];
      if (code == null || nameAr == null) {
        res.error(row, 'رمز المقرر واسم المادة مطلوبان');
        continue;
      }
      final d = findDept(depts, r['dept']);
      final deptId = d?.id ?? _defaultDept;
      if (deptId == null) {
        res.error(row, r['dept'] == null ? 'القسم مطلوب' : 'القسم "${r['dept']}" غير معرّف');
        continue;
      }
      if (!scope.hasDept(deptId)) {
        res.error(row, 'القسم خارج نطاق صلاحيتك');
        continue;
      }
      int? sem = int.tryParse(r['semester'] ?? '');
      if (sem == null || sem < 1 || sem > 12) {
        final st = parseStage(r['stage']);
        final t = parseTerm(r['term']);
        if (st == null || t == null) {
          res.error(row, 'حدد المرحلة والكورس (أو رقم الفصل الدراسي)');
          continue;
        }
        sem = (st - 1) * 2 + t;
      }
      final prereqs = (r['prereqs'] ?? '')
          .split(RegExp(r'[,،;\s]+'))
          .map((e) => e.trim().toUpperCase())
          .where((e) => e.isNotEmpty && e != '-' && e != 'لايوجد' && e != 'لا')
          .toList();
      final id = Course.makeId(deptId, sem, code);
      out[id] = (Course(
        id: id,
        deptId: deptId,
        semester: sem,
        stage: (sem + 1) ~/ 2,
        term: sem.isOdd ? 1 : 2,
        code: code,
        nameAr: nameAr,
        nameEn: r['nameEn'] ?? existing[id]?.nameEn ?? '',
        ects: int.tryParse(r['ects'] ?? '') ?? existing[id]?.ects ?? 0,
        credits: int.tryParse(r['credits'] ?? '') ?? existing[id]?.credits ?? 0,
        prereqs: prereqs.isNotEmpty ? prereqs : (existing[id]?.prereqs ?? const []),
      ));
    }
    for (final id in out.keys) {
      existing.containsKey(id) ? res.updated++ : res.added++;
    }
    if (out.isNotEmpty) await repo.saveCoursesBulk(out.values.toList());
    return res;
  }

  static Future<ImportResult> _structure(
      List<(int, Map<String, String>)> recs) async {
    final res = ImportResult();
    final role = AppState.user.value?.staff?.roleEnum;
    if (role != Role.admin && role != Role.president) {
      res.error(0, 'تعريف الكليات والأقسام للإدارة العليا ومدير النظام فقط');
      return res;
    }
    final colleges = await repo.colleges();
    final depts = await repo.departments();
    for (final (row, r) in recs) {
      final cName = r['college'];
      if (cName == null) {
        res.error(row, 'اسم الكلية مطلوب');
        continue;
      }
      var c = findCollege(colleges, cName);
      if (c == null) {
        c = College(id: _slug('col', cName), name: cName);
        await repo.saveCollege(c);
        colleges.add(c);
        res.added++;
      }
      final dName = r['dept'];
      if (dName == null) continue;
      final existing = findDept(depts, r['deptCode'] ?? dName);
      final d = Department(
        id: existing?.id ?? (r['deptCode']?.toLowerCase() ?? _slug('dep', dName)),
        name: dName,
        collegeId: c.id,
      );
      await repo.saveDepartment(d);
      if (existing == null) {
        depts.add(d);
        res.added++;
      } else {
        res.updated++;
      }
    }
    return res;
  }
}

// ======================== الدرجات ========================

const _gradeHeaders = <String, List<String>>{
  'id': ['الرقم المعرفي', 'الرقم الجامعي', 'رقم الطالب', 'id number', 'id', 'student id'],
  'attendance': ['الحضور', 'حضور', 'درجه الحضور', 'attendance'],
  'assignment': ['الواجب البيتي', 'الواجبات', 'واجبات', 'الواجب', 'homework', 'assignment', 'assignments'],
  'project': ['المشروع', 'مشروع', 'project'],
  'lab': ['المختبر', 'مختبر', 'المختبرات', 'العملي', 'lab', 'labs'],
  'quiz': ['الامتحان الاسبوعي', 'الاختبار الاسبوعي', 'الاختبارات', 'اختبارات', 'الاختبارات القصيره', 'weekly quiz', 'quiz', 'quizzes'],
  'midterm': ['الامتحان الفصلي', 'الفصلي', 'امتحان نصف السنه', 'نصف الفصل', 'midterm', 'mid'],
  'final': ['الامتحان النهائي', 'النهائي', 'final exam', 'final'],
};

class GradeRow {
  final int row;
  final String studentId;
  final Map<String, double?> marks; // null = قيمة غير رقمية
  GradeRow(this.row, this.studentId, this.marks);
}

/// نتيجة قراءة ملف درجات: الصفوف + الدرجات القصوى المكتوبة في العناوين مثل "الحضور (5)".
class GradeFile {
  final List<GradeRow> rows;
  final Map<String, double> headerMax;
  GradeFile(this.rows, this.headerMax);
}

class GradesExcel {
  GradesExcel._();

  static String _fmt(double? v) {
    if (v == null) return '';
    return v == v.roundToDouble() ? v.toInt().toString() : v.toStringAsFixed(2);
  }

  static String _col(int i) => String.fromCharCode(65 + i); // A..Z

  /// سجل درجات بشكل "student_grades_full": عنوان، عناوين عربية بالدرجة القصوى،
  /// عناوين إنجليزية، صف لكل طالب مع معادلتي المجموع والتقدير، ثم المعدل والأعلى والأدنى.
  static Future<void> shareTemplate(Course c, List<Student> students,
      GradeScheme sch, Map<String, GradeRecord> existing) async {
    final x = Excel.createExcel();
    final sheet = x['Sheet1'];
    final comps = sch.active;
    final first = 3; // العمود D
    final last = first + comps.length - 1;
    final totalCol = last + 1;
    sheet.appendRow([
      TextCellValue('سجل درجات الطلاب / Student Grades Record — ${c.nameAr} (${c.code})'),
    ]);
    sheet.appendRow([TextCellValue('')]);
    sheet.appendRow([
      TextCellValue('ت'),
      TextCellValue('الرقم المعرفي'),
      TextCellValue('اسم الطالب'),
      ...comps.map((k) => TextCellValue('${componentName(k)}\n(${_fmt(sch.max[k])})')),
      TextCellValue('الدرجة النهائية\n(${_fmt(sch.total)})'),
      TextCellValue('التقدير\nGrade'),
    ]);
    sheet.appendRow([
      TextCellValue('No.'),
      TextCellValue('ID Number'),
      TextCellValue('Student Name'),
      ...comps.map((k) => TextCellValue(gradeComponentNamesEn[k] ?? k)),
      TextCellValue('Final Grade'),
      TextCellValue('Status / Grade'),
    ]);
    var r = 5;
    for (var i = 0; i < students.length; i++, r++) {
      final s = students[i];
      final g = existing[s.id];
      final k = '${_col(totalCol)}$r';
      sheet.appendRow([
        IntCellValue(i + 1),
        TextCellValue(s.id),
        TextCellValue(s.name),
        ...comps.map((c) {
          final v = g?.marks[c];
          return v == null ? null : DoubleCellValue(v);
        }),
        FormulaCellValue('SUM(${_col(first)}$r:${_col(last)}$r)'),
        FormulaCellValue(
            'IF($k="","",IF($k>=90,"امتياز / Excellent",IF($k>=80,"جيد جداً / Very Good",IF($k>=70,"جيد / Good",IF($k>=60,"متوسط / Medium",IF($k>=50,"مقبول / Pass","راسب / Fail"))))))'),
      ]);
    }
    final end = r - 1;
    if (students.isNotEmpty) {
      sheet.appendRow([TextCellValue('')]);
      for (final (label, fn) in [
        ('المعدل العام / Average', 'AVERAGE'),
        ('أعلى درجة / Highest Score', 'MAX'),
        ('أدنى درجة / Lowest Score', 'MIN'),
      ]) {
        sheet.appendRow([
          TextCellValue(label),
          null,
          null,
          for (var col = first; col <= totalCol; col++)
            FormulaCellValue('IFERROR($fn(${_col(col)}5:${_col(col)}$end),"")'),
        ]);
      }
    }
    final bytes = x.encode();
    if (bytes == null) return;
    await Share.shareXFiles([
      XFile.fromData(Uint8List.fromList(bytes),
          mimeType:
              'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
          name: 'student_grades_${c.code}.xlsx')
    ], subject: 'سجل درجات ${c.nameAr}');
  }

  /// يختار ملف الدرجات (من الهاتف أو Google Drive) ويقرأ صفوفه.
  static Future<GradeFile?> pick() async {
    final sheets = await XlsxReader.pick();
    if (sheets == null) return null;
    final out = <GradeRow>[];
    final headerMax = <String, double>{};
    for (final sheet in sheets) {
      final rows = sheet.rows;
      int headerAt = -1;
      Map<int, String> colField = {};
      for (var i = 0; i < rows.length && i < 15; i++) {
        final m = <int, String>{};
        final mx = <String, double>{};
        for (var c = 0; c < rows[i].length; c++) {
          final raw = rows[i][c];
          final h = norm(raw.split('(').first.replaceAll('\n', ' '));
          if (h.isEmpty) continue;
          for (final e in _gradeHeaders.entries) {
            if (m.containsValue(e.key)) continue;
            if (e.value.any((syn) => norm(syn) == h)) {
              m[c] = e.key;
              final mm = RegExp(r'\(([0-9.]+)\)').firstMatch(raw);
              final v = mm == null ? null : double.tryParse(mm.group(1)!);
              if (v != null && e.key != 'id') mx[e.key] = v;
              break;
            }
          }
        }
        if (m.containsValue('id') && m.length >= 2) {
          headerAt = i;
          colField = m;
          headerMax.addAll(mx);
          break;
        }
      }
      if (headerAt < 0) continue;
      for (var i = headerAt + 1; i < rows.length; i++) {
        String? id;
        final marks = <String, double?>{};
        colField.forEach((c, f) {
          if (c >= rows[i].length) return;
          final v = rows[i][c];
          if (f == 'id') {
            if (v.isNotEmpty) id = v;
          } else if (v.isNotEmpty) {
            marks[f] = double.tryParse(v.replaceAll(',', '.'));
          }
        });
        // تجاهل صف العناوين الإنجليزية وصفوف المعدل/الأعلى/الأدنى
        if (id == null || !RegExp(r'^[0-9]+$').hasMatch(id!)) continue;
        if (marks.isNotEmpty) out.add(GradeRow(i + 1, id!, marks));
      }
    }
    return GradeFile(out, headerMax);
  }
}
