import 'package:flutter/material.dart';

import '../../app_state.dart';
import '../../models.dart';
import '../../theme.dart';
import '../../widgets/common.dart';
import '../common/course_browser.dart';

/// إدارة المواد الدراسية.
class CoursesScreen extends StatefulWidget {
  final String? initialDept;
  const CoursesScreen({super.key, this.initialDept});

  @override
  State<CoursesScreen> createState() => _CoursesScreenState();
}

class _CoursesScreenState extends State<CoursesScreen> {
  List<Course> _all = [];
  List<Department> _depts = [];
  String? _dept;
  int? _stage;
  int _term = 1;
  bool _loading = true;
  Key _browserKey = UniqueKey();

  @override
  void initState() {
    super.initState();
    _dept = widget.initialDept;
    _load();
  }

  Future<void> _load() async {
    try {
      final r = await Future.wait([repo.courses(), repo.departments()]);
      _all = (r[0] as List<Course>)
          .where((c) => AppState.scope.hasDept(c.deptId))
          .toList()
        ..sort((a, b) => a.semester != b.semester
            ? a.semester.compareTo(b.semester)
            : a.code.compareTo(b.code));
      _depts = AppState.scope.filterDepts(r[1] as List<Department>);
      _browserKey = UniqueKey();
    } catch (e) {
      if (mounted) showSnack(context, friendlyError(e), error: true);
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _edit([Course? c]) async {
    final code = TextEditingController(text: c?.code);
    final ar = TextEditingController(text: c?.nameAr);
    final en = TextEditingController(text: c?.nameEn);
    final ects = TextEditingController(text: c == null ? '5' : '${c.ects}');
    String dept = c?.deptId ?? _dept ?? (_depts.isNotEmpty ? _depts.first.id : '');
    int semester = c?.semester ??
        (_stage != null ? (_stage! - 1) * 2 + _term : 1);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) => AlertDialog(
          title: Text(c == null ? 'إضافة مادة' : 'تعديل المادة'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                    controller: ar,
                    decoration:
                        const InputDecoration(labelText: 'اسم المادة بالعربية')),
                const SizedBox(height: 10),
                TextField(
                    controller: en,
                    textDirection: TextDirection.ltr,
                    decoration: const InputDecoration(
                        labelText: 'اسم المادة بالإنجليزية')),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                          controller: code,
                          enabled: c == null,
                          textDirection: TextDirection.ltr,
                          decoration:
                              const InputDecoration(labelText: 'رمز المقرر')),
                    ),
                    const SizedBox(width: 10),
                    SizedBox(
                      width: 90,
                      child: TextField(
                          controller: ects,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(labelText: 'ECTS')),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                DropdownButtonFormField<String>(
                  value: _depts.any((d) => d.id == dept) ? dept : null,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'القسم'),
                  items: _depts
                      .map((d) =>
                          DropdownMenuItem(value: d.id, child: Text(d.name)))
                      .toList(),
                  onChanged: c != null
                      ? null
                      : (v) => setD(() => dept = v ?? dept),
                ),
                const SizedBox(height: 10),
                DropdownButtonFormField<int>(
                  value: semester,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'الفصل الدراسي'),
                  items: List.generate(10, (i) => i + 1)
                      .map((s) => DropdownMenuItem(
                          value: s,
                          child: Text(
                              'الفصل $s • ${stageName((s + 1) ~/ 2)} • ${termName(s.isOdd ? 1 : 2)}')))
                      .toList(),
                  onChanged: c != null
                      ? null
                      : (v) => setD(() => semester = v ?? semester),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('إلغاء')),
            FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('حفظ')),
          ],
        ),
      ),
    );
    if (ok != true || !mounted) return;
    if (ar.text.trim().isEmpty || code.text.trim().isEmpty || dept.isEmpty) {
      showSnack(context, 'أكمل الاسم والرمز والقسم', error: true);
      return;
    }
    final course = Course(
      id: c?.id ?? Course.makeId(dept, semester, code.text.trim().toUpperCase()),
      deptId: dept,
      semester: semester,
      stage: (semester + 1) ~/ 2,
      term: semester.isOdd ? 1 : 2,
      code: code.text.trim().toUpperCase(),
      nameAr: ar.text.trim(),
      nameEn: en.text.trim(),
      ects: int.tryParse(ects.text.trim()) ?? 0,
    );
    await runBusy(context, () => repo.saveCourse(course), success: 'تم الحفظ');
    _load();
  }

  Future<void> _delete(Course c) async {
    final ok = await confirmDialog(
        context, 'حذف المادة', 'حذف "${c.nameAr}" (${c.code})؟',
        ok: 'حذف', danger: true);
    if (!ok || !mounted) return;
    await runBusy(context, () => repo.deleteCourse(c.id), success: 'تم الحذف');
    _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: gradientAppBar('المواد الدراسية'),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _edit(),
        icon: const Icon(Icons.add),
        label: const Text('مادة'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : CourseBrowser(
              key: _browserKey,
              courses: _all,
              departments: _depts,
              initialDept: _dept,
              initialStage: _stage,
              initialTerm: _term,
              onChanged: (d, st, t) {
                _dept = d;
                _stage = st;
                _term = t;
              },
              itemBuilder: (ctx, c) => Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: _tile(c),
              ),
            ),
    );
  }

  Widget _tile(Course c) {
    final g = AppColors.tilePalette[(c.stage - 1) % AppColors.tilePalette.length];
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: () => _edit(c),
        onLongPress: () => _delete(c),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              Container(
                width: 54,
                height: 54,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                    gradient: g, borderRadius: BorderRadius.circular(16)),
                child: Text('${c.stage}',
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 22,
                        fontWeight: FontWeight.w900)),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(c.nameAr,
                        style: const TextStyle(
                            fontWeight: FontWeight.w700, fontSize: 15)),
                    Text(c.nameEn,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textDirection: TextDirection.ltr,
                        style: const TextStyle(
                            color: AppColors.muted, fontSize: 12)),
                    const SizedBox(height: 4),
                    Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      children: [
                        Pill(c.code),
                        Pill(termName(c.term), color: AppColors.violet),
                        Pill('${c.ects} ECTS', color: AppColors.emerald),
                      ],
                    ),
                  ],
                ),
              ),
              IconButton(
                onPressed: () => _delete(c),
                icon: const Icon(Icons.delete_outline, color: AppColors.rose),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
