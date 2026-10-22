import 'package:flutter/material.dart';

import '../../app_state.dart';
import '../../models.dart';
import '../../theme.dart';
import '../../widgets/common.dart';
import '../common/course_picker.dart';
import '../common/profile_sheet.dart';
import '../common/reports_screen.dart';
import '../common/lessons_screen.dart';
import 'grades_screen.dart';
import 'live_session_screen.dart';
import 'results_upload_screen.dart';

class DoctorHome extends StatefulWidget {
  /// true عند فتحها من لوحة الإدارة (رئيس قسم/عميد يدرّس).
  final bool embedded;
  const DoctorHome({super.key, this.embedded = false});

  @override
  State<DoctorHome> createState() => _DoctorHomeState();
}

class _DoctorHomeState extends State<DoctorHome> {
  bool _loading = true;
  List<Course> _courses = [];
  List<LectureSession> _sessions = [];
  Map<String, String> _deptNames = {};
  bool _allTerms = false;

  Staff get _me => AppState.user.value!.staff!;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final r = await Future.wait([
        repo.courses(),
        repo.sessionsForDoctor(_me.id),
        repo.departments(),
      ]);
      final mine = _me.courseIds.toSet();
      _courses = (r[0] as List<Course>)
          .where((c) => mine.contains(c.id))
          .toList()
        ..sort((a, b) => a.semester != b.semester
            ? a.semester.compareTo(b.semester)
            : a.nameAr.compareTo(b.nameAr));
      _sessions = r[1] as List<LectureSession>;
      _deptNames = {for (final d in r[2] as List<Department>) d.id: d.name};
    } catch (e) {
      if (mounted) showSnack(context, friendlyError(e), error: true);
    }
    if (mounted) setState(() => _loading = false);
  }

  List<Course> get _shownCourses => _allTerms
      ? _courses
      : _courses
          .where((c) => c.term == AppState.settings.currentTerm)
          .toList();

  Future<void> _manageCourses() async {
    final r = await Navigator.push<List<String>>(
      context,
      MaterialPageRoute(
        builder: (_) => CoursePickerScreen(
          initial: _me.courseIds.toSet(),
          title: 'موادي الدراسية',
          initialDept: _me.deptId,
        ),
      ),
    );
    if (r == null || !mounted) return;
    final updated = _me.copyWith(courseIds: r);
    final ok = await runBusy(context, () async {
      await repo.saveStaff(updated);
      return true;
    }, success: 'تم تحديث موادك');
    if (ok == true) {
      AppState.user.value = AppUser.staff(updated);
      _load();
    }
  }

  Future<void> _start(Course c) async {
    String shift = 'all';
    final title = TextEditingController();
    final n = _sessions.where((s) => s.courseId == c.id).length + 1;
    final ok = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) => Padding(
          padding: EdgeInsets.fromLTRB(
              20, 0, 20, 20 + MediaQuery.of(ctx).viewInsets.bottom),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text('بدء محاضرة جديدة',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
              Text('${c.nameAr} • ${stageName(c.stage)}',
                  style: const TextStyle(color: AppColors.muted)),
              const SizedBox(height: 16),
              const Text('الدوام', style: TextStyle(fontWeight: FontWeight.w700)),
              const SizedBox(height: 8),
              SegmentedButton<String>(
                segments: const [
                  ButtonSegment(
                      value: 'all',
                      label: Text('الكل'),
                      icon: Icon(Icons.all_inclusive)),
                  ButtonSegment(
                      value: 'morning',
                      label: Text('صباحي'),
                      icon: Icon(Icons.wb_sunny_outlined)),
                  ButtonSegment(
                      value: 'evening',
                      label: Text('مسائي'),
                      icon: Icon(Icons.nights_stay_outlined)),
                ],
                selected: {shift},
                onSelectionChanged: (v) => setS(() => shift = v.first),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: title,
                decoration: InputDecoration(
                  labelText: 'عنوان المحاضرة (اختياري)',
                  hintText: 'المحاضرة $n',
                  prefixIcon: const Icon(Icons.title),
                ),
              ),
              const SizedBox(height: 18),
              ElevatedButton.icon(
                onPressed: () => Navigator.pop(ctx, true),
                icon: const Icon(Icons.qr_code_2),
                label: const Text('بدء تسجيل الحضور'),
              ),
            ],
          ),
        ),
      ),
    );
    if (ok != true || !mounted) return;
    final session = LectureSession(
      id: '',
      courseId: c.id,
      courseName: c.nameAr,
      deptId: c.deptId,
      stage: c.stage,
      shift: shift,
      doctorId: _me.id,
      doctorName: _me.name,
      title: title.text.trim().isEmpty ? 'المحاضرة $n' : title.text.trim(),
      startedAt: DateTime.now().millisecondsSinceEpoch,
    );
    final created = await runBusy(context, () => repo.createSession(session));
    if (created == null || !mounted) return;
    await Navigator.push(
        context,
        MaterialPageRoute(
            builder: (_) => LiveSessionScreen(session: created, course: c)));
    _load();
  }

  Future<void> _resume(LectureSession s) async {
    final c = _courses.where((x) => x.id == s.courseId).firstOrNull ??
        (await repo.courses()).where((x) => x.id == s.courseId).firstOrNull;
    if (c == null || !mounted) return;
    await Navigator.push(
        context,
        MaterialPageRoute(
            builder: (_) => LiveSessionScreen(session: s, course: c)));
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final active = _sessions.where((s) => s.active).toList();
    final now = DateTime.now();
    final today = _sessions
        .where((s) =>
            s.startTime.year == now.year &&
            s.startTime.month == now.month &&
            s.startTime.day == now.day)
        .length;
    final p = AppColors.tilePalette;
    final shown = _shownCourses;

    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _manageCourses,
        icon: const Icon(Icons.library_add),
        label: const Text('موادي'),
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: EdgeInsets.zero,
          children: [
            GradientHeader(
              title: _me.name,
              subtitle:
                  '${roleName(_me.role)} • ${_me.deptId != null ? (_deptNames[_me.deptId] ?? '') : termName(AppState.settings.currentTerm)}',
              roleIcon: Icons.co_present_rounded,
              actions: widget.embedded
                  ? [
                      IconButton(
                        onPressed: () => Navigator.pop(context),
                        icon: const Icon(Icons.arrow_back,
                            color: Colors.white),
                      ),
                    ]
                  : [
                IconButton(
                  onPressed: () => showProfileSheet(context),
                  icon: const Icon(Icons.account_circle_outlined,
                      color: Colors.white),
                ),
                IconButton(
                  onPressed: () => logout(context),
                  icon: const Icon(Icons.logout, color: Colors.white),
                ),
              ],
              bottom: Row(
                children: [
                  Expanded(
                      child: StatCard(
                          label: 'موادي',
                          value: '${_courses.length}',
                          icon: Icons.menu_book_rounded,
                          gradient: p[1])),
                  const SizedBox(width: 10),
                  Expanded(
                      child: StatCard(
                          label: 'محاضرات اليوم',
                          value: '$today',
                          icon: Icons.today_rounded,
                          gradient: p[3])),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  ...active.map(_activeBanner),
                  _resultsCard(),
                  SectionTitle(
                    'موادي • ${_allTerms ? 'كل الفصول' : termName(AppState.settings.currentTerm)}',
                    trailing: TextButton(
                      onPressed: () => setState(() => _allTerms = !_allTerms),
                      child: Text(_allTerms ? 'الفصل الحالي' : 'عرض الكل'),
                    ),
                  ),
                  if (_loading)
                    const Padding(
                        padding: EdgeInsets.all(30),
                        child: Center(child: CircularProgressIndicator()))
                  else if (shown.isEmpty)
                    Column(
                      children: [
                        const EmptyState(
                            icon: Icons.library_books,
                            text:
                                'لا توجد مواد مسندة إليك لهذا الفصل.\nاضغط "موادي" لاختيار موادك.'),
                        OutlinedButton.icon(
                          onPressed: _manageCourses,
                          icon: const Icon(Icons.add),
                          label: const Text('اختيار المواد'),
                        ),
                      ],
                    )
                  else
                    ..._grouped(shown),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _openResults([Course? c]) async {
    await Navigator.push(
        context,
        MaterialPageRoute(
            builder: (_) =>
                ResultsUploadScreen(myCourses: _courses, initialCourse: c)));
    if (mounted) _load();
  }

  Widget _resultsCard() => Card(
        margin: const EdgeInsets.only(top: 8, bottom: 4),
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: () => _openResults(),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              children: [
                Container(
                  width: 50,
                  height: 50,
                  decoration: BoxDecoration(
                      gradient: AppColors.tilePalette[2],
                      borderRadius: BorderRadius.circular(14)),
                  child: const Icon(Icons.cloud_upload_rounded,
                      color: Colors.white, size: 28),
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('رفع نتائج الطلبة',
                          style: TextStyle(
                              fontWeight: FontWeight.w800, fontSize: 16)),
                      Text(
                          'ملف Excel بصيغة سجل النتائج التفصيلي، يُزامَن ويظهر في «الدرجات» لدى الطالب',
                          style: TextStyle(
                              fontSize: 12, color: AppColors.muted)),
                    ],
                  ),
                ),
                const Icon(Icons.chevron_left),
              ],
            ),
          ),
        ),
      );

  Widget _smallBtn(IconData i, String t, Widget Function() page) => Expanded(
        child: OutlinedButton.icon(
          style: OutlinedButton.styleFrom(
              minimumSize: const Size.fromHeight(42),
              padding: const EdgeInsets.symmetric(horizontal: 6)),
          onPressed: () async {
            await Navigator.push(
                context, MaterialPageRoute(builder: (_) => page()));
            _load();
          },
          icon: Icon(i, size: 18),
          label: Text(t, style: const TextStyle(fontSize: 13)),
        ),
      );

  /// تجميع المواد: القسم ← المرحلة، ثم مواد الكورس.
  List<Widget> _grouped(List<Course> list) {
    final groups = <String, List<Course>>{};
    for (final c in list) {
      groups.putIfAbsent('${c.deptId}|${c.stage}', () => []).add(c);
    }
    final keys = groups.keys.toList()
      ..sort((a, b) {
        final ga = groups[a]!.first, gb = groups[b]!.first;
        final d = (_deptNames[ga.deptId] ?? '').compareTo(_deptNames[gb.deptId] ?? '');
        return d != 0 ? d : ga.stage.compareTo(gb.stage);
      });
    final out = <Widget>[];
    for (final k in keys) {
      final g = groups[k]!..sort((a, b) => a.term != b.term
          ? a.term.compareTo(b.term)
          : a.nameAr.compareTo(b.nameAr));
      final first = g.first;
      out.add(Padding(
        padding: const EdgeInsets.fromLTRB(4, 10, 4, 8),
        child: Row(
          children: [
            const Icon(Icons.apartment_rounded, size: 18, color: AppColors.royal),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                  '${_deptNames[first.deptId] ?? first.deptId} • ${stageName(first.stage)}',
                  style: const TextStyle(
                      fontWeight: FontWeight.w800, color: AppColors.royal)),
            ),
            Pill('${g.length} مادة'),
          ],
        ),
      ));
      out.addAll(g.map(_courseCard));
    }
    return out;
  }

  Widget _activeBanner(LectureSession s) {
    return Container(
      margin: const EdgeInsets.only(top: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        gradient: AppColors.grad(AppColors.emerald, const Color(0xFF0D9488)),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        children: [
          const Icon(Icons.sensors, color: Colors.white, size: 30),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('محاضرة جارية الآن',
                    style: TextStyle(
                        color: Colors.white, fontWeight: FontWeight.w800)),
                Text('${s.courseName} • ${fmtTime(s.startTime)}',
                    style: const TextStyle(color: Colors.white70)),
              ],
            ),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
                backgroundColor: Colors.white,
                foregroundColor: AppColors.emerald),
            onPressed: () => _resume(s),
            child: const Text('متابعة'),
          ),
        ],
      ),
    );
  }

  Widget _courseCard(Course c) {
    final count = _sessions.where((s) => s.courseId == c.id).length;
    final g = AppColors.tilePalette[c.semester % AppColors.tilePalette.length];
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        boxShadow: [
          BoxShadow(
              color: AppColors.royal.withOpacity(0.06),
              blurRadius: 16,
              offset: const Offset(0, 6))
        ],
      ),
      child: Column(
        children: [
          ListTile(
            contentPadding: const EdgeInsets.fromLTRB(14, 10, 14, 0),
            leading: Container(
              width: 50,
              height: 50,
              decoration: BoxDecoration(
                  gradient: g, borderRadius: BorderRadius.circular(16)),
              child: const Icon(Icons.auto_stories, color: Colors.white),
            ),
            title: Text(c.nameAr,
                style:
                    const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
            subtitle: Text(
                '${c.code} • ${termName(c.term)}\n$count محاضرة مسجّلة',
                style: const TextStyle(fontSize: 12)),
            isThreeLine: true,
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 8, 14, 14),
            child: Column(
              children: [
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                      minimumSize: const Size.fromHeight(46)),
                  onPressed: () => _start(c),
                  icon: const Icon(Icons.qr_code_scanner),
                  label: const Text('بدء محاضرة وتسجيل الحضور'),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    _smallBtn(Icons.grading_rounded, 'الدرجات',
                        () => GradesScreen(course: c)),
                    const SizedBox(width: 8),
                    _smallBtn(Icons.menu_book_rounded, 'الدروس',
                        () => LessonsScreen(course: c, canEdit: true)),
                    const SizedBox(width: 8),
                    _smallBtn(Icons.insights, 'الغياب',
                        () => CourseReportScreen(course: c)),
                  ],
                ),
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  child: TextButton.icon(
                    onPressed: () => _openResults(c),
                    icon: const Icon(Icons.cloud_upload_rounded),
                    label: const Text('رفع ملف نتائج الطلبة لهذه المادة'),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
