import 'package:flutter/material.dart';

import '../../app_state.dart';
import '../../models.dart';
import '../../theme.dart';
import '../../widgets/common.dart';
import 'courses_screen.dart';

/// إدارة الكليات والأقسام.
class StructureScreen extends StatefulWidget {
  const StructureScreen({super.key});

  @override
  State<StructureScreen> createState() => _StructureScreenState();
}

class _StructureScreenState extends State<StructureScreen> {
  List<College> _colleges = [];
  List<Department> _depts = [];
  Map<String, int> _courseCount = {};
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final r = await Future.wait(
          [repo.colleges(), repo.departments(), repo.courses()]);
      _colleges = (r[0] as List<College>)..sort((a, b) => a.name.compareTo(b.name));
      _depts = (r[1] as List<Department>)
        ..sort((a, b) => a.name.compareTo(b.name));
      _courseCount = {};
      for (final c in r[2] as List<Course>) {
        _courseCount[c.deptId] = (_courseCount[c.deptId] ?? 0) + 1;
      }
    } catch (e) {
      if (mounted) showSnack(context, friendlyError(e), error: true);
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _editCollege([College? c]) async {
    final name = TextEditingController(text: c?.name);
    final id = TextEditingController(text: c?.id);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(c == null ? 'إضافة كلية' : 'تعديل الكلية'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
                controller: name,
                decoration: const InputDecoration(labelText: 'اسم الكلية')),
            const SizedBox(height: 10),
            TextField(
                controller: id,
                enabled: c == null,
                textDirection: TextDirection.ltr,
                decoration: const InputDecoration(
                    labelText: 'رمز مختصر بالإنجليزية (مثل eng)')),
          ],
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
    );
    if (ok != true || !mounted) return;
    if (name.text.trim().isEmpty || id.text.trim().isEmpty) {
      showSnack(context, 'أكمل الحقول', error: true);
      return;
    }
    await runBusy(
        context,
        () => repo.saveCollege(
            College(id: id.text.trim(), name: name.text.trim())),
        success: 'تم الحفظ');
    _load();
  }

  Future<void> _editDept({Department? d, String? collegeId}) async {
    final name = TextEditingController(text: d?.name);
    final id = TextEditingController(text: d?.id);
    String college = d?.collegeId ??
        collegeId ??
        (_colleges.isNotEmpty ? _colleges.first.id : '');
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) => AlertDialog(
          title: Text(d == null ? 'إضافة قسم' : 'تعديل القسم'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                  controller: name,
                  decoration: const InputDecoration(labelText: 'اسم القسم')),
              const SizedBox(height: 10),
              TextField(
                  controller: id,
                  enabled: d == null,
                  textDirection: TextDirection.ltr,
                  decoration: const InputDecoration(
                      labelText: 'رمز مختصر بالإنجليزية (مثل ai)')),
              const SizedBox(height: 10),
              DropdownButtonFormField<String>(
                value: _colleges.any((c) => c.id == college) ? college : null,
                decoration: const InputDecoration(labelText: 'الكلية'),
                items: _colleges
                    .map((c) =>
                        DropdownMenuItem(value: c.id, child: Text(c.name)))
                    .toList(),
                onChanged: (v) => setD(() => college = v ?? college),
              ),
            ],
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
    if (name.text.trim().isEmpty || id.text.trim().isEmpty || college.isEmpty) {
      showSnack(context, 'أكمل الحقول', error: true);
      return;
    }
    await runBusy(
        context,
        () => repo.saveDepartment(Department(
            id: id.text.trim(), name: name.text.trim(), collegeId: college)),
        success: 'تم الحفظ');
    _load();
  }

  Future<void> _deleteDept(Department d) async {
    final n = _courseCount[d.id] ?? 0;
    final ok = await confirmDialog(context, 'حذف القسم',
        'حذف "${d.name}"؟${n > 0 ? '\nتنبيه: للقسم $n مادة ستبقى بدون قسم.' : ''}',
        ok: 'حذف', danger: true);
    if (!ok || !mounted) return;
    await runBusy(context, () => repo.deleteDepartment(d.id),
        success: 'تم الحذف');
    _load();
  }

  Future<void> _deleteCollege(College c) async {
    final has = _depts.any((d) => d.collegeId == c.id);
    if (has) {
      showSnack(context, 'احذف أقسام الكلية أولاً', error: true);
      return;
    }
    final ok = await confirmDialog(context, 'حذف الكلية', 'حذف "${c.name}"؟',
        ok: 'حذف', danger: true);
    if (!ok || !mounted) return;
    await runBusy(context, () => repo.deleteCollege(c.id), success: 'تم الحذف');
    _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: gradientAppBar('الكليات والأقسام'),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _editCollege(),
        icon: const Icon(Icons.add),
        label: const Text('كلية'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _colleges.isEmpty
              ? const EmptyState(
                  icon: Icons.account_balance, text: 'لا توجد كليات بعد')
              : ListView(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 90),
                  children: _colleges.map(_collegeCard).toList(),
                ),
    );
  }

  Widget _collegeCard(College c) {
    final depts = _depts.where((d) => d.collegeId == c.id).toList();
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
          color: Colors.white, borderRadius: BorderRadius.circular(22)),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
            decoration: BoxDecoration(
              gradient: AppColors.tilePalette[6],
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(22)),
            ),
            child: Row(
              children: [
                const Icon(Icons.account_balance_rounded, color: Colors.white),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(c.name,
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 17,
                          fontWeight: FontWeight.w800)),
                ),
                IconButton(
                    onPressed: () => _editCollege(c),
                    icon: const Icon(Icons.edit, color: Colors.white)),
                IconButton(
                    onPressed: () => _deleteCollege(c),
                    icon: const Icon(Icons.delete_outline,
                        color: Colors.white)),
              ],
            ),
          ),
          ...depts.map((d) => ListTile(
                leading: CircleAvatar(
                  backgroundColor: AppColors.royal.withOpacity(0.1),
                  child: const Icon(Icons.apartment, color: AppColors.royal),
                ),
                title: Text(d.name,
                    style: const TextStyle(fontWeight: FontWeight.w700)),
                subtitle: Text('${_courseCount[d.id] ?? 0} مادة • ${d.id}'),
                onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (_) => CoursesScreen(initialDept: d.id))),
                trailing: PopupMenuButton<String>(
                  onSelected: (v) =>
                      v == 'edit' ? _editDept(d: d) : _deleteDept(d),
                  itemBuilder: (_) => const [
                    PopupMenuItem(value: 'edit', child: Text('تعديل')),
                    PopupMenuItem(value: 'del', child: Text('حذف')),
                  ],
                ),
              )),
          TextButton.icon(
            onPressed: () => _editDept(collegeId: c.id),
            icon: const Icon(Icons.add),
            label: const Text('إضافة قسم'),
          ),
          const SizedBox(height: 6),
        ],
      ),
    );
  }
}
