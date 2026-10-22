import 'package:flutter/material.dart';

import '../../app_state.dart';
import '../../models.dart';
import '../../theme.dart';
import '../../widgets/common.dart';

/// لوحة المؤشرات الحية: أرقام فورية ضمن نطاق صلاحية المستخدم.
class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DeptStat {
  final Department dept;
  int students = 0;
  int doctors = 0;
  int courses = 0;
  int expected = 0;
  int present = 0;
  int sessions = 0;
  _DeptStat(this.dept);
  double get rate => expected == 0 ? -1 : present * 100 / expected;
}

class _DashboardScreenState extends State<DashboardScreen> {
  bool _loading = true;
  int _students = 0, _morning = 0, _evening = 0, _noDept = 0;
  int _doctors = 0, _courses = 0, _sessions7 = 0, _sessions30 = 0;
  double _rate30 = -1;
  final Map<int, int> _byStage = {};
  final Map<String, int> _byRole = {};
  List<_DeptStat> _depts = [];
  int _colleges = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final scope = AppState.scope;
      final now = DateTime.now();
      final since30 = now.subtract(const Duration(days: 30)).millisecondsSinceEpoch;
      final since7 = now.subtract(const Duration(days: 7)).millisecondsSinceEpoch;
      final r = await Future.wait([
        repo.students(),
        repo.staff(),
        repo.courses(),
        repo.departments(),
        repo.colleges(),
        repo.sessionsSince(since30),
        repo.attendanceSince(since30),
      ]);
      final students = (r[0] as List<Student>)
          .where((s) => scope.isAll || scope.hasDept(s.deptId))
          .toList();
      final staff = (r[1] as List<Staff>)
          .where((s) => scope.isAll || scope.hasDept(s.deptId))
          .toList();
      final courses =
          (r[2] as List<Course>).where((c) => scope.hasDept(c.deptId)).toList();
      final depts = scope.filterDepts(r[3] as List<Department>)
        ..sort((a, b) => a.name.compareTo(b.name));
      _colleges = (r[4] as List<College>)
          .where((c) => scope.hasCollege(c.id))
          .length;
      final sessions = (r[5] as List<LectureSession>)
          .where((s) => scope.hasDept(s.deptId))
          .toList();
      final att = r[6] as List<AttendanceRecord>;

      _students = students.length;
      _morning = students.where((s) => s.shift == 'morning').length;
      _evening = _students - _morning;
      _noDept = students.where((s) => s.deptId == null).length;
      _byStage.clear();
      for (final s in students) {
        _byStage[s.stage] = (_byStage[s.stage] ?? 0) + 1;
      }
      _byRole.clear();
      for (final s in staff) {
        _byRole[s.role] = (_byRole[s.role] ?? 0) + 1;
      }
      _doctors = staff.where((s) => s.role == 'doctor' || s.role == 'head').length;
      _courses = courses.length;
      _sessions30 = sessions.length;
      _sessions7 = sessions.where((s) => s.startedAt >= since7).length;

      final presentBySession = <String, int>{};
      for (final a in att) {
        presentBySession[a.sessionId] = (presentBySession[a.sessionId] ?? 0) + 1;
      }
      final stats = {for (final d in depts) d.id: _DeptStat(d)};
      for (final s in students) {
        stats[s.deptId]?.students++;
      }
      for (final s in staff) {
        if (s.role == 'doctor' || s.role == 'head') stats[s.deptId]?.doctors++;
      }
      for (final c in courses) {
        stats[c.deptId]?.courses++;
      }
      int exp = 0, pres = 0;
      for (final s in sessions) {
        final e = students.where(s.appliesTo).length;
        final p = presentBySession[s.id] ?? 0;
        exp += e;
        pres += p;
        final st = stats[s.deptId];
        if (st != null) {
          st.expected += e;
          st.present += p;
          st.sessions++;
        }
      }
      _rate30 = exp == 0 ? -1 : (pres * 100 / exp).clamp(0, 100).toDouble();
      _depts = stats.values.toList();
    } catch (e) {
      if (mounted) showSnack(context, friendlyError(e), error: true);
    }
    if (mounted) setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) {
    final p = AppColors.tilePalette;
    final scopeName = AppState.scope.isAll
        ? 'كل الجامعة'
        : (_depts.length == 1 ? _depts.first.dept.name : 'كليتك ($_colleges)');
    return Scaffold(
      appBar: gradientAppBar('لوحة المؤشرات'),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  Row(
                    children: [
                      const Icon(Icons.public, color: AppColors.royal, size: 18),
                      const SizedBox(width: 6),
                      Text('النطاق: $scopeName',
                          style: const TextStyle(
                              color: AppColors.royal,
                              fontWeight: FontWeight.w700)),
                      const Spacer(),
                      Text(fmtDateTime(DateTime.now()),
                          style: const TextStyle(
                              color: AppColors.muted, fontSize: 12)),
                    ],
                  ),
                  const SizedBox(height: 12),
                  GridView.count(
                    crossAxisCount: 2,
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    mainAxisSpacing: 10,
                    crossAxisSpacing: 10,
                    childAspectRatio: 2.1,
                    children: [
                      StatCard(
                          label: 'الطلبة المسجلون',
                          value: '$_students',
                          icon: Icons.groups_rounded,
                          gradient: p[0]),
                      StatCard(
                          label: 'أعضاء هيئة التدريس',
                          value: '$_doctors',
                          icon: Icons.co_present_rounded,
                          gradient: p[1]),
                      StatCard(
                          label: 'المقررات الدراسية',
                          value: '$_courses',
                          icon: Icons.menu_book_rounded,
                          gradient: p[2]),
                      StatCard(
                          label: 'الأقسام',
                          value: '${_depts.length}',
                          icon: Icons.apartment_rounded,
                          gradient: p[6]),
                      StatCard(
                          label: 'محاضرات آخر 7 أيام',
                          value: '$_sessions7',
                          icon: Icons.event_available_rounded,
                          gradient: p[3]),
                      StatCard(
                          label: 'نسبة الحضور (30 يوماً)',
                          value: _rate30 < 0 ? '—' : '${_rate30.round()}%',
                          icon: Icons.trending_up_rounded,
                          gradient: p[4]),
                    ],
                  ),
                  const SectionTitle('الطلبة حسب المرحلة والدوام'),
                  _panel(Column(
                    children: [
                      ...(_byStage.keys.toList()..sort()).map((st) => _bar(
                          stageName(st),
                          _byStage[st]!,
                          _students,
                          AppColors.tilePalette[(st - 1) % 8])),
                      const Divider(height: 24),
                      Row(
                        children: [
                          _pill('صباحي', _morning, AppColors.orange),
                          const SizedBox(width: 8),
                          _pill('مسائي', _evening, AppColors.violet),
                          if (_noDept > 0) ...[
                            const SizedBox(width: 8),
                            _pill('بلا قسم', _noDept, AppColors.rose),
                          ],
                        ],
                      ),
                    ],
                  )),
                  SectionTitle('الأقسام (${_depts.length})'),
                  if (_depts.isEmpty)
                    const EmptyState(
                        icon: Icons.apartment, text: 'لا توجد أقسام ضمن نطاقك')
                  else
                    ..._depts.map(_deptCard),
                  const SectionTitle('الكادر حسب الصفة'),
                  _panel(Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: staffRoles
                        .where((r) => (_byRole[r] ?? 0) > 0)
                        .map((r) => _pill(roleName(r), _byRole[r]!, AppColors.royal))
                        .toList(),
                  )),
                  const SectionTitle('مؤشرات قادمة'),
                  _soon(Icons.grading_rounded, 'نسب النجاح والرسوب والمعدلات',
                      'تُفعَّل مع مرحلة الدرجات والسجل الأكاديمي'),
                  _soon(Icons.account_balance_wallet_rounded,
                      'الميزانية والرسوم المستحصلة',
                      'تُفعَّل مع مرحلة الشؤون المالية'),
                  const SizedBox(height: 8),
                  Text(
                      'المحاضرات المسجلة خلال 30 يوماً: $_sessions30',
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: AppColors.muted, fontSize: 12)),
                ],
              ),
            ),
    );
  }

  Widget _panel(Widget child) => Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
            color: Colors.white, borderRadius: BorderRadius.circular(20)),
        child: child,
      );

  Widget _bar(String label, int n, int total, Gradient g) {
    final f = total == 0 ? 0.0 : n / total;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          SizedBox(
              width: 110,
              child: Text(label, style: const TextStyle(fontSize: 13))),
          Expanded(
            child: LayoutBuilder(
              builder: (_, c) => Stack(
                children: [
                  Container(
                    height: 18,
                    decoration: BoxDecoration(
                      color: AppColors.bg,
                      borderRadius: BorderRadius.circular(9),
                    ),
                  ),
                  Container(
                    height: 18,
                    width: (c.maxWidth * f).clamp(4.0, c.maxWidth).toDouble(),
                    decoration: BoxDecoration(
                      gradient: g,
                      borderRadius: BorderRadius.circular(9),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 44,
            child: Text('$n',
                textAlign: TextAlign.end,
                style: const TextStyle(fontWeight: FontWeight.w800)),
          ),
        ],
      ),
    );
  }

  Widget _pill(String l, int n, Color c) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: c.withOpacity(0.1),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Text('$l: $n',
            style: TextStyle(color: c, fontWeight: FontWeight.w800)),
      );

  Widget _deptCard(_DeptStat d) {
    final rate = d.rate;
    final st = rate < 0 ? null : absenceStatus(100 - rate);
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
          color: Colors.white, borderRadius: BorderRadius.circular(20)),
      child: Row(
        children: [
          CircleProgress(
            percent: rate < 0 ? 0 : rate,
            color: st?.color ?? AppColors.muted,
            size: 56,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(d.dept.name,
                    style: const TextStyle(
                        fontWeight: FontWeight.w800, fontSize: 15)),
                const SizedBox(height: 2),
                Text(
                    '${d.students} طالب • ${d.doctors} تدريسي • ${d.courses} مادة',
                    style: const TextStyle(fontSize: 12)),
                Text(
                    rate < 0
                        ? 'لا محاضرات مسجلة خلال 30 يوماً'
                        : 'حضور ${rate.round()}% في ${d.sessions} محاضرة (30 يوماً)',
                    style:
                        const TextStyle(fontSize: 12, color: AppColors.muted)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _soon(IconData i, String t, String s) => Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.6),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: const Color(0xFFE5E7F0)),
        ),
        child: Row(
          children: [
            Icon(i, color: AppColors.muted),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(t, style: const TextStyle(fontWeight: FontWeight.w700)),
                  Text(s,
                      style: const TextStyle(
                          color: AppColors.muted, fontSize: 12)),
                ],
              ),
            ),
            const Pill('قريباً', color: AppColors.muted),
          ],
        ),
      );
}
