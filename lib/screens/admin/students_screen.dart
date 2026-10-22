import 'package:flutter/material.dart';

import '../../app_state.dart';
import '../../models.dart';
import '../../theme.dart';
import '../../widgets/common.dart';
import '../common/filters.dart';
import '../common/student_report_screen.dart';
import '../common/nfc_link.dart';
import '../common/password_tools.dart';
import '../student/id_card_screen.dart';

const _noDept = '__none__';

class StudentsScreen extends StatefulWidget {
  const StudentsScreen({super.key});

  @override
  State<StudentsScreen> createState() => _StudentsScreenState();
}

class _StudentsScreenState extends State<StudentsScreen> {
  List<Student> _all = [];
  List<Department> _depts = [];
  bool _loading = true;
  String _q = '';
  int? _stage;
  String? _shift;
  String? _dept;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final r = await Future.wait([repo.students(), repo.departments()]);
      final scope = AppState.scope;
      _all = (r[0] as List<Student>)
          .where((x) => scope.isAll || scope.hasDept(x.deptId))
          .toList()
        ..sort((a, b) => a.name.compareTo(b.name));
      _depts = AppState.scope.filterDepts(r[1] as List<Department>);
    } catch (e) {
      if (mounted) showSnack(context, friendlyError(e), error: true);
    }
    if (mounted) setState(() => _loading = false);
  }

  String _deptName(String? id) => id == null
      ? 'بدون قسم'
      : (_depts.where((d) => d.id == id).map((d) => d.name).firstOrNull ?? id);

  List<Student> get _filtered => _all.where((s) {
        if (_stage != null && s.stage != _stage) return false;
        if (_shift != null && s.shift != _shift) return false;
        if (_dept == _noDept && s.deptId != null) return false;
        if (_dept != null && _dept != _noDept && s.deptId != _dept) {
          return false;
        }
        if (_q.isNotEmpty && !s.name.contains(_q) && !s.id.contains(_q)) {
          return false;
        }
        return true;
      }).toList();

  Future<void> _bulkDept() async {
    final list = _filtered;
    if (list.isEmpty) return;
    String? chosen = _depts.isNotEmpty ? _depts.first.id : null;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) => AlertDialog(
          title: const Text('تعيين القسم دفعة واحدة'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                  'سيتم تعيين القسم لـ ${list.length} طالباً (حسب التصفية الحالية).'),
              const SizedBox(height: 12),
              DropdownButtonFormField<String?>(
                value: chosen,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'القسم'),
                items: [
                  const DropdownMenuItem<String?>(
                      value: null, child: Text('بدون قسم (إزالة)')),
                  ..._depts.map((d) => DropdownMenuItem<String?>(
                      value: d.id, child: Text(d.name))),
                ],
                onChanged: (v) => setD(() => chosen = v),
              ),
            ],
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('إلغاء')),
            FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('تطبيق')),
          ],
        ),
      ),
    );
    if (ok != true || !mounted) return;
    await runBusy(context,
        () => repo.setStudentsDept(list.map((s) => s.id).toList(), chosen),
        success: 'تم تعيين القسم');
    _load();
  }

  Future<void> _edit([Student? s]) async {
    final id = TextEditingController(text: s?.id);
    final name = TextEditingController(text: s?.name);
    final email = TextEditingController(text: s?.email);
    int stage = s?.stage ?? 1;
    String shift = s?.shift ?? 'morning';
    final sc = AppState.scope.deptIds;
    String? dept = s?.deptId ?? ((sc != null && sc.length == 1) ? sc.first : null);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) => AlertDialog(
          title: Text(s == null ? 'إضافة طالب' : 'بيانات الطالب'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                    controller: id,
                    enabled: s == null,
                    keyboardType: TextInputType.number,
                    decoration:
                        const InputDecoration(labelText: 'الرقم المعرفي')),
                const SizedBox(height: 10),
                TextField(
                    controller: name,
                    decoration:
                        const InputDecoration(labelText: 'اسم الطالب الرباعي')),
                const SizedBox(height: 10),
                DropdownButtonFormField<int>(
                  value: stage,
                  decoration: const InputDecoration(labelText: 'المرحلة'),
                  items: [1, 2, 3, 4, 5]
                      .map((x) =>
                          DropdownMenuItem(value: x, child: Text(stageName(x))))
                      .toList(),
                  onChanged: (v) => setD(() => stage = v ?? stage),
                ),
                const SizedBox(height: 10),
                DropdownButtonFormField<String>(
                  value: shift,
                  decoration: const InputDecoration(labelText: 'الدوام'),
                  items: const [
                    DropdownMenuItem(value: 'morning', child: Text('صباحي')),
                    DropdownMenuItem(value: 'evening', child: Text('مسائي')),
                  ],
                  onChanged: (v) => setD(() => shift = v ?? shift),
                ),
                const SizedBox(height: 10),
                DropdownButtonFormField<String?>(
                  value: dept,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'القسم'),
                  items: [
                    const DropdownMenuItem<String?>(
                        value: null, child: Text('بدون قسم')),
                    ..._depts.map((d) => DropdownMenuItem<String?>(
                        value: d.id, child: Text(d.name))),
                  ],
                  onChanged: (v) => setD(() => dept = v),
                ),
                const SizedBox(height: 10),
                TextField(
                    controller: email,
                    keyboardType: TextInputType.emailAddress,
                    textDirection: TextDirection.ltr,
                    decoration: const InputDecoration(
                        labelText: 'البريد الجامعي الرسمي')),
              ],
            ),
          ),
          actions: [
            if (s != null)
              TextButton(
                onPressed: () => Navigator.pop(ctx, null),
                child: const Text('إغلاق'),
              ),
            if (s == null)
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
    if (id.text.trim().isEmpty || name.text.trim().isEmpty) {
      showSnack(context, 'أدخل الرقم والاسم', error: true);
      return;
    }
    if (s == null && _all.any((x) => x.id == id.text.trim())) {
      showSnack(context, 'هذا الرقم موجود مسبقاً', error: true);
      return;
    }
    final e = email.text.trim().toLowerCase();
    final st = Student(
      id: id.text.trim(),
      name: name.text.trim(),
      stage: stage,
      shift: shift,
      deptId: dept,
      email: e.isEmpty ? null : e,
      nfcUid: s?.nfcUid,
      activated: s?.activated ?? false,
      initPw: s?.initPw,
    );
    await runBusy(context, () => repo.saveStudent(st), success: 'تم الحفظ');
    _load();
  }

  Future<void> _delete(Student s) async {
    final ok = await confirmDialog(
        context, 'حذف الطالب', 'حذف "${s.name}" (${s.id}) نهائياً؟',
        ok: 'حذف', danger: true);
    if (!ok || !mounted) return;
    await runBusy(context, () => repo.deleteStudent(s.id),
        success: 'تم الحذف');
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final list = _filtered;
    return Scaffold(
      appBar: gradientAppBar('الطلاب', actions: [
        IconButton(
          tooltip: 'تعيين القسم للمعروضين',
          onPressed: _loading ? null : _bulkDept,
          icon: const Icon(Icons.drive_file_move_outline),
        ),
      ]),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _edit(),
        icon: const Icon(Icons.person_add_alt_1),
        label: const Text('طالب'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                FilterBar(
                  searchHint: 'ابحث بالاسم أو الرقم المعرفي',
                  onSearch: (v) => setState(() => _q = v.trim()),
                  children: [
                    ChoiceMenuChip<int>(
                      label: 'المرحلة',
                      value: _stage,
                      options: const {
                        1: 'الأولى',
                        2: 'الثانية',
                        3: 'الثالثة',
                        4: 'الرابعة'
                      },
                      onChanged: (v) => setState(() => _stage = v),
                    ),
                    ChoiceMenuChip<String>(
                      label: 'الدوام',
                      value: _shift,
                      options: const {'morning': 'صباحي', 'evening': 'مسائي'},
                      onChanged: (v) => setState(() => _shift = v),
                    ),
                    ChoiceMenuChip<String>(
                      label: 'القسم',
                      value: _dept,
                      options: {
                        _noDept: 'بدون قسم',
                        for (final d in _depts) d.id: d.name
                      },
                      onChanged: (v) => setState(() => _dept = v),
                    ),
                  ],
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 6, 20, 4),
                  child: Row(
                    children: [
                      Text('${list.length} طالب',
                          style: const TextStyle(color: AppColors.muted)),
                      const Spacer(),
                      Text(
                          'بطاقة NFC: ${list.where((s) => s.nfcUid != null).length}',
                          style: const TextStyle(
                              color: AppColors.emerald,
                              fontWeight: FontWeight.w700)),
                    ],
                  ),
                ),
                Expanded(
                  child: list.isEmpty
                      ? const EmptyState(
                          icon: Icons.person_search,
                          text: 'لا يوجد طلاب مطابقون')
                      : ListView.builder(
                          padding: const EdgeInsets.fromLTRB(16, 4, 16, 90),
                          itemCount: list.length,
                          itemBuilder: (_, i) => _tile(list[i]),
                        ),
                ),
              ],
            ),
    );
  }

  Widget _tile(Student s) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        child: ListTile(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
          onTap: () => _edit(s),
          leading: CircleAvatar(
            radius: 22,
            backgroundColor: (s.shift == 'morning'
                    ? AppColors.royal
                    : AppColors.violet)
                .withOpacity(0.12),
            child: Text(s.name.isEmpty ? '?' : s.name.characters.first,
                style: TextStyle(
                    fontWeight: FontWeight.w800,
                    color: s.shift == 'morning'
                        ? AppColors.royal
                        : AppColors.violet)),
          ),
          title: Text(s.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w700)),
          subtitle: Text(
              '${s.id} • ${stageName(s.stage)} • ${shiftName(s.shift)}\n${_deptName(s.deptId)}',
              style: const TextStyle(fontSize: 12)),
          isThreeLine: true,
          trailing: PopupMenuButton<String>(
            onSelected: (v) async {
              switch (v) {
                case 'report':
                  Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (_) => StudentReportScreen(student: s)));
                case 'card':
                  Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (_) => IdCardScreen(student: s)));
                case 'nfc':
                  if (await linkNfcCard(context, s)) _load();
                case 'unnfc':
                  await runBusy(context, () => repo.setStudentNfc(s.id, null),
                      success: 'تم إلغاء ربط البطاقة');
                  _load();
                case 'reset':
                  await resetPasswordFlow(context, student: s);
                  _load();
                case 'edit':
                  _edit(s);
                default:
                  _delete(s);
              }
            },
            itemBuilder: (_) => [
              const PopupMenuItem(value: 'report', child: Text('سجل الحضور')),
              const PopupMenuItem(value: 'card', child: Text('الهوية و QR')),
              PopupMenuItem(
                  value: 'nfc',
                  child: Text(s.nfcUid == null
                      ? 'ربط بطاقة NFC'
                      : 'تغيير بطاقة NFC')),
              if (s.nfcUid != null)
                const PopupMenuItem(
                    value: 'unnfc', child: Text('إلغاء ربط البطاقة')),
              const PopupMenuItem(
                  value: 'reset', child: Text('إعادة تعيين كلمة المرور')),
              const PopupMenuItem(value: 'edit', child: Text('تعديل')),
              const PopupMenuItem(value: 'del', child: Text('حذف')),
            ],
            icon: Icon(
              s.nfcUid != null ? Icons.nfc : Icons.more_vert,
              color: s.nfcUid != null ? AppColors.emerald : AppColors.muted,
            ),
          ),
        ),
      ),
    );
  }
}
