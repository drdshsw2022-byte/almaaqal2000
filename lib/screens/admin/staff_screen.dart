import 'package:flutter/material.dart';

import '../../app_state.dart';
import '../../config.dart';
import '../../data/repo.dart';
import '../../models.dart';
import '../../theme.dart';
import '../../widgets/common.dart';
import '../common/course_picker.dart';
import '../common/password_tools.dart';

/// إدارة الكادر (الدكاترة والمدراء) وتوزيع المواد عليهم.
class StaffScreen extends StatefulWidget {
  const StaffScreen({super.key});

  @override
  State<StaffScreen> createState() => _StaffScreenState();
}

class _StaffScreenState extends State<StaffScreen> {
  List<Staff> _staff = [];
  List<Department> _depts = [];
  List<College> _colleges = [];
  Map<String, Course> _courses = {};

  /// الصفات التي يحق للمستخدم الحالي إضافتها/تعديلها.
  List<String> get _allowedRoles {
    final me = AppState.user.value?.staff?.roleEnum;
    return switch (me) {
      Role.admin => staffRoles,
      Role.president => ['president', 'dean', 'head', 'doctor'],
      Role.dean => ['head', 'doctor'],
      Role.head => ['doctor'],
      _ => const <String>[],
    };
  }
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final r = await Future.wait([
        repo.staff(),
        repo.departments(),
        repo.courses(),
        repo.colleges()
      ]);
      final scope = AppState.scope;
      _colleges = (r[3] as List<College>)
          .where((c) => scope.hasCollege(c.id))
          .toList();
      _staff = (r[0] as List<Staff>)
          .where((x) =>
              scope.isAll ||
              scope.hasDept(x.deptId) ||
              (x.role == 'dean' && x.collegeId != null && scope.hasCollege(x.collegeId) &&
                  AppState.user.value?.staff?.roleEnum == Role.dean))
          .toList()
        ..sort((a, b) => a.role != b.role
            ? staffRoles.indexOf(a.role).compareTo(staffRoles.indexOf(b.role))
            : a.name.compareTo(b.name));
      _depts = scope.filterDepts(r[1] as List<Department>);
      _courses = {for (final c in r[2] as List<Course>) c.id: c};
    } catch (e) {
      if (mounted) showSnack(context, friendlyError(e), error: true);
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _edit([Staff? s]) async {
    final email = TextEditingController(text: s?.email);
    final initPwCtrl = TextEditingController();
    final aliasCtrl = TextEditingController(text: s?.alias);
    final name = TextEditingController(text: s?.name);
    String role = s?.role ?? 'doctor';
    final sc = AppState.scope.deptIds;
    String? dept =
        s?.deptId ?? ((sc != null && sc.length == 1) ? sc.first : null);
    String? college = s?.collegeId ??
        (_colleges.length == 1 ? _colleges.first.id : null);
    final canEdit = s == null || _allowedRoles.contains(s.role);
    List<String> courseIds = [...?s?.courseIds];

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) => AlertDialog(
          title: Text(s == null ? 'إضافة عضو كادر' : 'تعديل بيانات الكادر'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<String>(
                  value: role,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'الصفة'),
                  items: {..._allowedRoles, role}
                      .map((r) => DropdownMenuItem(
                          value: r,
                          enabled: _allowedRoles.contains(r),
                          child: Text(roleName(r))))
                      .toList(),
                  onChanged: (v) => setD(() => role = v ?? role),
                ),
                const SizedBox(height: 12),
                TextField(
                    controller: name,
                    decoration: const InputDecoration(
                        labelText: 'الاسم الكامل مع اللقب العلمي')),
                const SizedBox(height: 10),
                TextField(
                    controller: email,
                    enabled: s == null,
                    keyboardType: TextInputType.emailAddress,
                    textDirection: TextDirection.ltr,
                    decoration: const InputDecoration(
                        labelText: 'البريد الإلكتروني',
                        hintText: 'name@${AppConfig.universityDomain}')),
                const SizedBox(height: 10),
                TextField(
                    controller: aliasCtrl,
                    textDirection: TextDirection.ltr,
                    decoration: const InputDecoration(
                        labelText: 'اسم المستخدم (اختياري)',
                        helperText: 'مثل doc01 • فارغ = بداية البريد الجامعي')),
                if (s == null) ...[
                  const SizedBox(height: 10),
                  TextField(
                    controller: initPwCtrl,
                    decoration: const InputDecoration(
                      labelText: 'كلمة المرور الأولية (اختياري)',
                      helperText:
                          'فارغة = ${AppConfig.defaultStaffPassword} • يُطلب تغييرها عند أول دخول',
                      helperMaxLines: 2,
                    ),
                  ),
                ],
                const SizedBox(height: 10),
                if (role == 'dean') ...[
                  DropdownButtonFormField<String?>(
                    value: _colleges.any((c) => c.id == college) ? college : null,
                    isExpanded: true,
                    decoration: const InputDecoration(labelText: 'الكلية'),
                    items: _colleges
                        .map((c) => DropdownMenuItem<String?>(
                            value: c.id, child: Text(c.name)))
                        .toList(),
                    onChanged: (v) => setD(() => college = v),
                  ),
                  const SizedBox(height: 10),
                ],
                DropdownButtonFormField<String?>(
                  value: _depts.any((d) => d.id == dept) ? dept : null,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'القسم'),
                  items: [
                    const DropdownMenuItem<String?>(
                        value: null, child: Text('غير محدد')),
                    ..._depts.map((d) => DropdownMenuItem<String?>(
                        value: d.id, child: Text(d.name))),
                  ],
                  onChanged: (v) => setD(() => dept = v),
                ),
                if (role == 'doctor' || role == 'head' || role == 'dean') ...[
                  const SizedBox(height: 10),
                  OutlinedButton.icon(
                    onPressed: () async {
                      final r = await Navigator.push<List<String>>(
                        ctx,
                        MaterialPageRoute(
                          builder: (_) => CoursePickerScreen(
                            initial: courseIds.toSet(),
                            title: 'مواد الدكتور',
                            initialDept: dept,
                          ),
                        ),
                      );
                      if (r != null) setD(() => courseIds = r);
                    },
                    icon: const Icon(Icons.library_books_outlined),
                    label: Text('المواد المسندة (${courseIds.length})'),
                  ),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('إلغاء')),
            FilledButton(
                onPressed: canEdit ? () => Navigator.pop(ctx, true) : null,
                child: Text(canEdit ? 'حفظ' : 'لا تملك صلاحية التعديل')),
          ],
        ),
      ),
    );
    if (ok != true || !mounted) return;
    if (!_allowedRoles.contains(role)) {
      showSnack(context, 'لا تملك صلاحية تعيين صفة "${roleName(role)}"',
          error: true);
      return;
    }
    if (role == 'dean' && college == null) {
      showSnack(context, 'حدد كلية العميد', error: true);
      return;
    }
    if ((role == 'head' || role == 'doctor') &&
        !AppState.scope.isAll &&
        !AppState.scope.hasDept(dept)) {
      showSnack(context, 'حدد قسماً ضمن نطاقك', error: true);
      return;
    }
    final e = email.text.trim().toLowerCase();
    if (e.isEmpty || name.text.trim().isEmpty) {
      showSnack(context, 'أدخل الاسم والبريد الجامعي', error: true);
      return;
    }
    if (!AppConfig.isValidEmail(e)) {
      showSnack(context, 'صيغة البريد غير صحيحة', error: true);
      return;
    }
    if (aliasCtrl.text.trim().toLowerCase() == AppConfig.bootstrapAdminUsername) {
      showSnack(context, 'اسم المستخدم "admin" محجوز لمدير النظام', error: true);
      return;
    }
    if (!AppConfig.isUniversityEmail(e) && aliasCtrl.text.trim().isEmpty) {
      showSnack(context, 'البريد من خارج الجامعة: حدد له اسم مستخدم للدخول',
          error: true);
      return;
    }
    if (s == null && _staff.any((x) => x.id == e)) {
      showSnack(context, 'هذا البريد مضاف مسبقاً', error: true);
      return;
    }
    final staff = Staff(
      activated: s?.activated ?? false,
      alias: aliasCtrl.text.trim().isEmpty ? null : aliasCtrl.text.trim(),
      initPw: initPwCtrl.text.trim().isNotEmpty
          ? hashPassword(e.split('@').first, initPwCtrl.text.trim())
          : s?.initPw,
      id: e,
      name: name.text.trim(),
      role: role,
      collegeId: role == 'dean' ? college : null,
      deptId: dept,
      courseIds: (role == 'doctor' || role == 'head' || role == 'dean')
          ? courseIds
          : const [],
    );
    if (initPwCtrl.text.trim().isNotEmpty && initPwCtrl.text.trim().length < 6) {
      showSnack(context, 'كلمة المرور الأولية 6 أحرف على الأقل', error: true);
      return;
    }
    await runBusy(context, () => repo.saveStaff(staff),
        success: s == null
            ? 'تمت الإضافة • اسم المستخدم: ${staff.loginName} • كلمة المرور الأولية: ${initPwCtrl.text.trim().isEmpty ? AppConfig.defaultStaffPassword : initPwCtrl.text.trim()}'
            : 'تم الحفظ');
    _load();
  }

  Future<void> _delete(Staff s) async {
    if (s.id == AppState.user.value?.staff?.id) {
      showSnack(context, 'لا يمكنك حذف حسابك', error: true);
      return;
    }
    if (!_allowedRoles.contains(s.role)) {
      showSnack(context, 'لا تملك صلاحية حذف "${roleName(s.role)}"', error: true);
      return;
    }
    final ok = await confirmDialog(context, 'حذف', 'حذف "${s.name}"؟',
        ok: 'حذف', danger: true);
    if (!ok || !mounted) return;
    await runBusy(context, () => repo.deleteStaff(s.id), success: 'تم الحذف');
    _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: gradientAppBar('الكادر التدريسي والإداري'),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _edit(),
        icon: const Icon(Icons.person_add),
        label: const Text('إضافة'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _staff.isEmpty
              ? const EmptyState(icon: Icons.badge, text: 'لا يوجد كادر بعد')
              : ListView.builder(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 90),
                  itemCount: _staff.length,
                  itemBuilder: (_, i) => _tile(_staff[i]),
                ),
    );
  }

  Widget _tile(Staff s) {
    final g = switch (s.role) {
      'president' => AppColors.goldGradient,
      'dean' => AppColors.tilePalette[5],
      'head' => AppColors.tilePalette[2],
      'admin' => AppColors.tilePalette[4],
      _ => AppColors.tilePalette[1],
    };
    final names = s.courseIds
        .map((id) => _courses[id]?.nameAr)
        .whereType<String>()
        .take(3)
        .join('، ');
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
          color: Colors.white, borderRadius: BorderRadius.circular(20)),
      child: ListTile(
        contentPadding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
        onTap: () => _edit(s),
        leading: Container(
          width: 48,
          height: 48,
          decoration:
              BoxDecoration(gradient: g, borderRadius: BorderRadius.circular(16)),
          child: Icon(
              switch (s.role) {
                'president' => Icons.account_balance_rounded,
                'dean' => Icons.domain_rounded,
                'head' => Icons.apartment_rounded,
                'admin' => Icons.admin_panel_settings,
                _ => Icons.co_present,
              },
              color: Colors.white),
        ),
        title: Text(s.name, style: const TextStyle(fontWeight: FontWeight.w700)),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('${roleName(s.role)} • اسم المستخدم: ${s.loginName}${s.activated ? '' : ' • لم يفعّل'}',
                style: const TextStyle(fontSize: 12)),
            if (s.role == 'doctor' || s.courseIds.isNotEmpty)
              Text(
                  s.courseIds.isEmpty
                      ? 'لا توجد مواد مسندة'
                      : '${s.courseIds.length} مادة: $names${s.courseIds.length > 3 ? '…' : ''}',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 12, color: AppColors.royal)),
          ],
        ),
        trailing: PopupMenuButton<String>(
          onSelected: (v) async {
            switch (v) {
              case 'edit':
                _edit(s);
              case 'reset':
                await resetPasswordFlow(context, staff: s);
                _load();
              default:
                _delete(s);
            }
          },
          itemBuilder: (_) => const [
            PopupMenuItem(value: 'edit', child: Text('تعديل')),
            PopupMenuItem(value: 'reset', child: Text('إعادة تعيين كلمة المرور')),
            PopupMenuItem(value: 'del', child: Text('حذف')),
          ],
        ),
      ),
    );
  }
}
