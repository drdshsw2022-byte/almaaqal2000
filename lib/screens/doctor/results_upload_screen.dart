import 'package:flutter/material.dart';

import '../../app_state.dart';
import '../../models.dart';
import '../../services/excel_import.dart';
import '../../theme.dart';
import '../../widgets/common.dart';
import '../common/course_picker.dart';
import 'grades_screen.dart';

/// رفع ملف نتائج الطلبة (بصيغة student_grades_full) لمادة، ومزامنته مع لوحات الطلبة.
class ResultsUploadScreen extends StatefulWidget {
  final List<Course> myCourses;
  final Course? initialCourse;
  const ResultsUploadScreen(
      {super.key, required this.myCourses, this.initialCourse});

  @override
  State<ResultsUploadScreen> createState() => _ResultsUploadScreenState();
}

class _Matched {
  final Student student;
  final Map<String, double> marks;
  _Matched(this.student, this.marks);
}

class _ResultsUploadScreenState extends State<ResultsUploadScreen> {
  Course? _course;
  GradeFile? _file;
  String? _fileError;
  bool _publish = true;
  List<_Matched> _matched = [];
  List<String> _problems = [];
  List<String> _notes = [];
  Map<String, double> _max = {};

  @override
  void initState() {
    super.initState();
    _course = widget.initialCourse ??
        (widget.myCourses.length == 1 ? widget.myCourses.first : null);
  }

  static String _fmt(double v) =>
      v == v.roundToDouble() ? v.toInt().toString() : v.toStringAsFixed(1);

  Future<void> _pickOtherCourse() async {
    final r = await Navigator.push<List<String>>(
      context,
      MaterialPageRoute(
        builder: (_) => const CoursePickerScreen(
            multi: false, title: 'اختر المادة'),
      ),
    );
    if (r == null || r.isEmpty || !mounted) return;
    final all = await repo.courses();
    final c = all.where((x) => x.id == r.first).firstOrNull;
    if (c == null) return;
    // إضافة المادة لمواد الدكتور (ليملك صلاحية رصد درجاتها)
    final me = AppState.user.value?.staff;
    if (me != null && !me.courseIds.contains(c.id)) {
      final updated = me.copyWith(courseIds: [...me.courseIds, c.id]);
      try {
        await repo.saveStaff(updated);
        AppState.user.value = AppUser.staff(updated);
      } catch (_) {}
    }
    setState(() {
      _course = c;
      _analyze();
    });
  }

  Future<void> _pickFile() async {
    try {
      final f = await GradesExcel.pick();
      if (f == null) return;
      _file = f;
      _fileError = f.rows.isEmpty
          ? 'لم أجد في الملف عمود «الرقم المعرفي» مع درجات مرصودة.'
          : null;
    } catch (e) {
      _file = null;
      _fileError = e is AppException
          ? e.message
          : 'تعذّرت قراءة الملف: $e';
    }
    await _analyze();
  }

  /// مطابقة صفوف الملف مع طلبة المادة والتحقق من المدى.
  Future<void> _analyze() async {
    final c = _course;
    final f = _file;
    _matched = [];
    _problems = [];
    _notes = [];
    if (c == null || f == null || f.rows.isEmpty) {
      if (mounted) setState(() {});
      return;
    }
    final sch = await repo.scheme(c.id);
    _max = Map<String, double>.from(sch.max)..addAll(f.headerMax);
    final students = {for (final s in await repo.students()) s.id: s};
    for (final r in f.rows) {
      final s = students[r.studentId];
      if (s == null) {
        _problems.add('صف ${r.row}: الرقم ${r.studentId} غير موجود في قاعدة البيانات');
        continue;
      }
      if (s.stage != c.stage || (s.deptId != null && s.deptId != c.deptId)) {
        _notes.add(
            '${s.name} (${s.id}) من ${stageName(s.stage)}؛ سيُرفع كطالب محمَّل بهذه المادة');
      }
      final marks = <String, double>{};
      r.marks.forEach((k, v) {
        final mx = _max[k] ?? 0;
        if (v == null) {
          _problems.add('صف ${r.row}: قيمة غير رقمية في ${componentName(k)}');
        } else if (mx <= 0 || v < 0 || v > mx) {
          _problems.add(
              'صف ${r.row}: ${componentName(k)} = ${_fmt(v)} خارج المدى (0–${_fmt(mx)})');
        } else {
          marks[k] = v;
        }
      });
      if (marks.isNotEmpty) _matched.add(_Matched(s, marks));
    }
    if (mounted) setState(() {});
  }

  Future<void> _sync() async {
    final c = _course!;
    final ok = await runBusy(context, () async {
      final sch = await repo.scheme(c.id);
      final comps = <String>{
        for (final m in _matched) ...m.marks.keys,
      };
      final published = {...sch.published};
      if (_publish) published.addAll(comps);
      await repo.saveScheme(
          GradeScheme(courseId: c.id, max: _max, published: published));
      final existing = {
        for (final g in await repo.gradesForCourse(c.id)) g.studentId: g
      };
      final out = _matched.map((m) {
        final old = existing[m.student.id];
        return GradeRecord(
          courseId: c.id,
          studentId: m.student.id,
          studentName: m.student.name,
          studentEmail: m.student.email,
          marks: {...?old?.marks, ...m.marks},
        );
      }).toList();
      await repo.saveGradesBulk(out);
      return out.length;
    });
    if (ok == null || !mounted) return;
    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: const Icon(Icons.cloud_done_rounded,
            color: AppColors.emerald, size: 48),
        title: const Text('تمت المزامنة'),
        content: Text(
            'حُفظت نتائج $ok طالباً في ${c.nameAr}.\n${_publish ? 'وهي ظاهرة الآن في قسم «الدرجات» لدى كل طالب.' : 'لم تُنشر بعد للطلبة؛ انشرها من شاشة الدرجات.'}',
            textAlign: TextAlign.center),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              Navigator.pushReplacement(
                  context,
                  MaterialPageRoute(
                      builder: (_) => GradesScreen(course: c)));
            },
            child: const Text('عرض الدرجات'),
          ),
          FilledButton(
              onPressed: () {
                Navigator.pop(ctx);
                Navigator.pop(context);
              },
              child: const Text('تم')),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final courses = {
      for (final c in [...widget.myCourses, if (_course != null) _course!])
        c.id: c
    }.values.toList();
    final canSync = _course != null && _matched.isNotEmpty;
    return Scaffold(
      appBar: gradientAppBar('رفع نتائج الطلبة'),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _step(
            1,
            'المادة',
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (courses.isNotEmpty)
                  DropdownButtonFormField<String>(
                    value: _course?.id,
                    isExpanded: true,
                    hint: const Text('اختر المادة'),
                    items: courses
                        .map((c) => DropdownMenuItem(
                            value: c.id,
                            child: Text(
                                '${c.nameAr} • ${stageName(c.stage)} • ${termName(c.term)}',
                                overflow: TextOverflow.ellipsis)))
                        .toList(),
                    onChanged: (v) {
                      setState(() =>
                          _course = courses.firstWhere((c) => c.id == v));
                      _analyze();
                    },
                  ),
                TextButton.icon(
                  onPressed: _pickOtherCourse,
                  icon: const Icon(Icons.search),
                  label: Text(courses.isEmpty
                      ? 'اختيار المادة من الأقسام'
                      : 'مادة أخرى'),
                ),
              ],
            ),
          ),
          _step(
            2,
            'ملف النتائج',
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'سجل الدرجات بصيغة الجامعة (student_grades_full): الرقم المعرفي، الحضور، الواجب البيتي، المشروع، المختبر، الامتحان الأسبوعي، الفصلي، النهائي. يمكن اختياره من الهاتف أو من Google Drive.',
                  style: TextStyle(fontSize: 12.5, color: AppColors.muted, height: 1.6),
                ),
                const SizedBox(height: 10),
                OutlinedButton.icon(
                  onPressed: _pickFile,
                  icon: const Icon(Icons.upload_file_rounded),
                  label: Text(_file == null ? 'اختيار ملف Excel' : 'اختيار ملف آخر'),
                ),
                if (_fileError != null) ...[
                  const SizedBox(height: 8),
                  Text(_fileError!,
                      style: const TextStyle(color: AppColors.rose)),
                ],
                if (_file != null && _file!.headerMax.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: gradeComponents
                        .where((k) => _file!.headerMax.containsKey(k))
                        .map((k) => Pill(
                            '${componentName(k)} ${_fmt(_file!.headerMax[k]!)}'))
                        .toList(),
                  ),
                ],
              ],
            ),
          ),
          if (_course != null && _file != null && _file!.rows.isNotEmpty)
            _step(
              3,
              'المعاينة',
              Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      _num('جاهز للمزامنة', _matched.length, AppColors.emerald),
                      _num('ملاحظات', _problems.length, AppColors.orange),
                    ],
                  ),
                  const SizedBox(height: 10),
                  ..._matched.take(8).map((m) {
                    final total = m.marks.values.fold<double>(0, (a, b) => a + b);
                    return ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.check_circle,
                          color: AppColors.emerald),
                      title: Text(m.student.name),
                      subtitle: Text('الرقم المعرفي: ${m.student.id}'),
                      trailing: Text(_fmt(total),
                          style: const TextStyle(
                              fontWeight: FontWeight.w900, fontSize: 16)),
                    );
                  }),
                  if (_matched.length > 8)
                    Text('و${_matched.length - 8} طالباً آخرين…',
                        style: const TextStyle(color: AppColors.muted)),
                  if (_notes.isNotEmpty)
                    ExpansionTile(
                      tilePadding: EdgeInsets.zero,
                      title: Text('تنبيهات (${_notes.length})',
                          style: const TextStyle(
                              fontSize: 13.5, color: AppColors.royal)),
                      children: _notes
                          .take(100)
                          .map((p) => Align(
                                alignment: AlignmentDirectional.centerStart,
                                child: Text('• $p',
                                    style: const TextStyle(fontSize: 12)),
                              ))
                          .toList(),
                    ),
                  if (_problems.isNotEmpty)
                    ExpansionTile(
                      tilePadding: EdgeInsets.zero,
                      title: Text('الصفوف غير المرفوعة (${_problems.length})',
                          style: const TextStyle(
                              fontSize: 13.5, color: AppColors.orange)),
                      children: _problems
                          .take(100)
                          .map((p) => Align(
                                alignment: AlignmentDirectional.centerStart,
                                child: Text('• $p',
                                    style: const TextStyle(fontSize: 12)),
                              ))
                          .toList(),
                    ),
                ],
              ),
            ),
          if (_course != null && _file != null && _file!.rows.isNotEmpty) ...[
            SwitchListTile(
              value: _publish,
              onChanged: (v) => setState(() => _publish = v),
              title: const Text('نشر النتائج للطلبة فوراً'),
              subtitle: const Text('تظهر في قسم «الدرجات» بلوحة الطالب'),
            ),
            const SizedBox(height: 8),
            ElevatedButton.icon(
              onPressed: canSync ? _sync : null,
              icon: const Icon(Icons.sync_rounded),
              label: Text(canSync
                  ? 'مزامنة نتائج ${_matched.length} طالباً'
                  : 'لا توجد نتائج صالحة للمزامنة'),
            ),
          ],
        ],
      ),
    );
  }

  Widget _num(String l, int n, Color c) => Expanded(
        child: Column(
          children: [
            Text('$n',
                style: TextStyle(
                    color: c, fontSize: 24, fontWeight: FontWeight.w900)),
            Text(l, style: const TextStyle(color: AppColors.muted)),
          ],
        ),
      );

  Widget _step(int n, String title, Widget child) => Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
            color: Colors.white, borderRadius: BorderRadius.circular(20)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                CircleAvatar(
                  radius: 14,
                  backgroundColor: AppColors.royal,
                  child: Text('$n',
                      style: const TextStyle(
                          color: Colors.white, fontWeight: FontWeight.w800)),
                ),
                const SizedBox(width: 10),
                Text(title,
                    style: const TextStyle(
                        fontWeight: FontWeight.w800, fontSize: 16)),
              ],
            ),
            const SizedBox(height: 12),
            child,
          ],
        ),
      );
}
