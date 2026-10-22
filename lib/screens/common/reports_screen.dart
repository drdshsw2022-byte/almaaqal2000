import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import '../../app_state.dart';
import '../../data/repo.dart';
import '../../models.dart';
import '../../theme.dart';
import '../../widgets/common.dart';
import '../doctor/live_session_screen.dart';
import 'course_picker.dart';

/// التقارير (للمدير): اختيار مادة ثم عرض تقريرها.
class ReportsScreen extends StatelessWidget {
  const ReportsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return CoursePickerScreen(
      multi: false,
      title: 'التقارير • اختر مادة',
      onPicked: (ctx, c) => Navigator.push(ctx,
          MaterialPageRoute(builder: (_) => CourseReportScreen(course: c))),
    );
  }
}

/// تقرير حضور مادة: إحصائيات الطلاب وقائمة المحاضرات.
class CourseReportScreen extends StatefulWidget {
  final Course course;
  const CourseReportScreen({super.key, required this.course});

  @override
  State<CourseReportScreen> createState() => _CourseReportScreenState();
}

class _CourseReportScreenState extends State<CourseReportScreen> {
  bool _loading = true;
  String _shift = 'all';
  List<LectureSession> _sessions = [];
  List<Student> _students = [];
  Map<String, Set<String>> _attended = {}; // studentId -> sessionIds
  Map<String, int> _presentCount = {}; // sessionId -> count

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final r = await Future.wait([
        repo.sessionsForCourse(widget.course.id),
        repo.attendanceForCourse(widget.course.id),
        repo.students(),
      ]);
      _sessions = r[0] as List<LectureSession>;
      final recs = r[1] as List<AttendanceRecord>;
      _students = Stats.eligibleStudents(
          r[2] as List<Student>, widget.course, 'all');
      _attended = {};
      _presentCount = {};
      for (final a in recs) {
        _attended.putIfAbsent(a.studentId, () => <String>{}).add(a.sessionId);
        _presentCount[a.sessionId] = (_presentCount[a.sessionId] ?? 0) + 1;
      }
    } catch (e) {
      if (mounted) showSnack(context, friendlyError(e), error: true);
    }
    if (mounted) setState(() => _loading = false);
  }

  List<StudentCourseStat> get _stats {
    final list = _students
        .where((s) => _shift == 'all' || s.shift == _shift)
        .map((s) => Stats.forStudent(s, _sessions, _attended[s.id] ?? {}))
        .toList()
      ..sort((a, b) => b.absencePercent != a.absencePercent
          ? b.absencePercent.compareTo(a.absencePercent)
          : a.student.name.compareTo(b.student.name));
    return list;
  }

  List<LectureSession> get _shownSessions => _sessions
      .where((s) => _shift == 'all' || s.shift == 'all' || s.shift == _shift)
      .toList();

  Future<void> _export() async {
    final stats = _stats;
    final b = StringBuffer('﻿');
    b.writeln(
        'المادة,${widget.course.nameAr} (${widget.course.code}),${stageName(widget.course.stage)}');
    b.writeln('الرقم الجامعي,اسم الطالب,الدوام,عدد المحاضرات,حضور,غياب,نسبة الغياب %,الحالة');
    for (final s in stats) {
      b.writeln([
        s.student.id,
        s.student.name,
        shiftName(s.student.shift),
        s.total,
        s.present,
        s.absent,
        s.absencePercent.toStringAsFixed(1),
        absenceStatus(s.absencePercent).label,
      ].join(','));
    }
    final bytes = Uint8List.fromList(utf8.encode(b.toString()));
    await Share.shareXFiles([
      XFile.fromData(bytes,
          mimeType: 'text/csv',
          name: 'attendance_${widget.course.code}.csv')
    ], subject: 'تقرير حضور ${widget.course.nameAr}');
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.course;
    final stats = _stats;
    final warn = stats
        .where((s) => absenceStatus(s.absencePercent).color == AppColors.orange)
        .length;
    final fail = stats
        .where((s) => absenceStatus(s.absencePercent).color == AppColors.rose)
        .length;
    final avg = stats.isEmpty
        ? 0.0
        : stats.map((s) => s.attendancePercent).reduce((a, b) => a + b) /
            stats.length;

    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: gradientAppBar(
          c.nameAr,
          actions: [
            IconButton(
                tooltip: 'تصدير Excel (CSV)',
                onPressed: _loading ? null : _export,
                icon: const Icon(Icons.ios_share)),
          ],
          bottom: const TabBar(
            labelColor: Colors.white,
            unselectedLabelColor: Colors.white70,
            indicatorColor: AppColors.gold,
            indicatorWeight: 3,
            tabs: [Tab(text: 'الطلاب'), Tab(text: 'المحاضرات')],
          ),
        ),
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : Column(
                children: [
                  Container(
                    color: Colors.white,
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                    child: Column(
                      children: [
                        Row(
                          children: [
                            _mini('المحاضرات', '${_shownSessions.length}',
                                AppColors.royal),
                            _mini('معدل الحضور', '${avg.round()}%',
                                AppColors.emerald),
                            _mini('إنذار', '$warn', AppColors.orange),
                            _mini('محروم', '$fail', AppColors.rose),
                          ],
                        ),
                        const SizedBox(height: 10),
                        SegmentedButton<String>(
                          segments: const [
                            ButtonSegment(value: 'all', label: Text('الكل')),
                            ButtonSegment(
                                value: 'morning', label: Text('صباحي')),
                            ButtonSegment(
                                value: 'evening', label: Text('مسائي')),
                          ],
                          selected: {_shift},
                          onSelectionChanged: (v) =>
                              setState(() => _shift = v.first),
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: TabBarView(
                      children: [
                        _studentsTab(stats),
                        _sessionsTab(),
                      ],
                    ),
                  ),
                ],
              ),
      ),
    );
  }

  Widget _mini(String label, String value, Color color) => Expanded(
        child: Column(
          children: [
            Text(value,
                style: TextStyle(
                    color: color, fontSize: 20, fontWeight: FontWeight.w900)),
            Text(label,
                style: const TextStyle(fontSize: 11, color: AppColors.muted)),
          ],
        ),
      );

  Widget _studentsTab(List<StudentCourseStat> stats) {
    if (stats.isEmpty) {
      return const EmptyState(
          icon: Icons.groups, text: 'لا يوجد طلاب مسجلون في هذه المرحلة');
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.builder(
        padding: const EdgeInsets.all(12),
        itemCount: stats.length,
        itemBuilder: (_, i) {
          final s = stats[i];
          final st = absenceStatus(s.absencePercent);
          return Card(
            margin: const EdgeInsets.only(bottom: 8),
            child: ListTile(
              leading: CircleProgress(
                  percent: s.attendancePercent, color: st.color, size: 46),
              title: Text(s.student.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w700)),
              subtitle: Text(
                  'الرقم الجامعي: ${s.student.id} • ${shiftName(s.student.shift)}\nحضور ${s.present}/${s.total} • غياب ${s.absencePercent.toStringAsFixed(1)}%',
                  style: const TextStyle(fontSize: 12)),
              trailing: Pill(st.label, color: st.color),
            ),
          );
        },
      ),
    );
  }

  Widget _sessionsTab() {
    final list = _shownSessions;
    if (list.isEmpty) {
      return const EmptyState(
          icon: Icons.event_note, text: 'لا توجد محاضرات مسجلة لهذه المادة');
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.builder(
        padding: const EdgeInsets.all(12),
        itemCount: list.length,
        itemBuilder: (_, i) {
          final s = list[i];
          final eligible = _students.where(s.appliesTo).length;
          final present = _presentCount[s.id] ?? 0;
          return Card(
            margin: const EdgeInsets.only(bottom: 8),
            child: ListTile(
              onTap: () async {
                await Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (_) => SessionDetailScreen(
                            session: s, course: widget.course)));
                _load();
              },
              leading: CircleAvatar(
                backgroundColor: (s.active ? AppColors.emerald : AppColors.royal)
                    .withOpacity(0.12),
                child: Text('${list.length - i}',
                    style: TextStyle(
                        fontWeight: FontWeight.w800,
                        color:
                            s.active ? AppColors.emerald : AppColors.royal)),
              ),
              title: Text(
                  s.title.isEmpty ? 'محاضرة ${list.length - i}' : s.title,
                  style: const TextStyle(fontWeight: FontWeight.w700)),
              subtitle: Text(
                  '${dayName(s.startTime)} ${fmtDateTime(s.startTime)} • ${shiftName(s.shift)}\n${s.doctorName}',
                  style: const TextStyle(fontSize: 12)),
              isThreeLine: true,
              trailing: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text('$present/$eligible',
                      style: const TextStyle(
                          fontWeight: FontWeight.w900,
                          color: AppColors.royal)),
                  if (s.active)
                    const Pill('جارية', color: AppColors.emerald)
                  else
                    const Text('حاضر',
                        style:
                            TextStyle(fontSize: 11, color: AppColors.muted)),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

/// تفاصيل محاضرة: الحاضرون والغائبون مع إمكانية التعديل اليدوي.
class SessionDetailScreen extends StatefulWidget {
  final LectureSession session;
  final Course course;
  const SessionDetailScreen(
      {super.key, required this.session, required this.course});

  @override
  State<SessionDetailScreen> createState() => _SessionDetailScreenState();
}

class _SessionDetailScreenState extends State<SessionDetailScreen> {
  List<Student> _eligible = [];
  bool _loading = true;
  late final Stream<List<AttendanceRecord>> _attStream =
      repo.watchAttendance(widget.session.id);

  bool get _canEdit {
    final u = AppState.user.value;
    if (u == null) return false;
    if (u.id == widget.session.doctorId) return true; // صاحب المحاضرة
    if (u.role == Role.admin || u.role == Role.president) return true;
    // العميد ورئيس القسم ضمن نطاقهما
    return (u.role == Role.dean || u.role == Role.head) &&
        AppState.scope.hasDept(widget.session.deptId);
  }

  @override
  void initState() {
    super.initState();
    _loadStudents();
  }

  Future<void> _loadStudents() async {
    try {
      final all = await repo.students();
      _eligible = all.where(widget.session.appliesTo).toList()
        ..sort((a, b) => a.name.compareTo(b.name));
    } catch (e) {
      if (mounted) showSnack(context, friendlyError(e), error: true);
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _toggle(Student s, AttendanceRecord? rec) async {
    if (!_canEdit) return;
    if (rec != null) {
      final ok = await confirmDialog(
          context, 'إلغاء الحضور', 'تسجيل ${s.name} غائباً؟',
          ok: 'تسجيل غياب', danger: true);
      if (!ok || !mounted) return;
      await runBusy(context, () => repo.removeAttendance(rec.id));
    } else {
      await runBusy(
          context,
          () => repo.markAttendance(AttendanceRecord(
                sessionId: widget.session.id,
                courseId: widget.session.courseId,
                studentId: s.id,
                studentName: s.name,
                time: DateTime.now().millisecondsSinceEpoch,
                method: 'manual',
              )),
          success: 'تم تسجيل حضور ${s.name}');
    }
  }

  Future<void> _delete() async {
    final ok = await confirmDialog(context, 'حذف المحاضرة',
        'سيتم حذف المحاضرة وكل سجلات حضورها. متابعة؟',
        ok: 'حذف', danger: true);
    if (!ok || !mounted) return;
    final r = await runBusy(context, () async {
      await repo.deleteSession(widget.session.id);
      return true;
    }, success: 'تم حذف المحاضرة');
    if (r == true && mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.session;
    return Scaffold(
      appBar: gradientAppBar(s.title.isEmpty ? 'تفاصيل المحاضرة' : s.title,
          actions: [
            if (_canEdit)
              IconButton(
                  onPressed: _delete, icon: const Icon(Icons.delete_outline)),
          ]),
      floatingActionButton: s.active && _canEdit
          ? FloatingActionButton.extended(
              onPressed: () => Navigator.pushReplacement(
                  context,
                  MaterialPageRoute(
                      builder: (_) => LiveSessionScreen(
                          session: s, course: widget.course))),
              icon: const Icon(Icons.qr_code_2),
              label: const Text('متابعة التسجيل'),
            )
          : null,
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : StreamBuilder<List<AttendanceRecord>>(
              stream: _attStream,
              builder: (context, snap) {
                final recs = {
                  for (final a in snap.data ?? <AttendanceRecord>[])
                    a.studentId: a
                };
                final present =
                    _eligible.where((x) => recs.containsKey(x.id)).toList();
                final absent =
                    _eligible.where((x) => !recs.containsKey(x.id)).toList();
                // حضور طلاب من خارج القائمة (مثلاً تغيّر قسمهم)
                final extra = recs.values
                    .where((a) => !_eligible.any((e) => e.id == a.studentId))
                    .toList();
                return ListView(
                  padding: const EdgeInsets.fromLTRB(12, 12, 12, 90),
                  children: [
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                          gradient: AppColors.mainGradient,
                          borderRadius: BorderRadius.circular(20)),
                      child: DefaultTextStyle(
                        style: const TextStyle(color: Colors.white),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(widget.course.nameAr,
                                style: const TextStyle(
                                    fontSize: 17,
                                    fontWeight: FontWeight.w800)),
                            Text(
                                '${dayName(s.startTime)} ${fmtDateTime(s.startTime)} • ${shiftName(s.shift)}'),
                            Text(s.doctorName),
                            const SizedBox(height: 8),
                            Row(
                              children: [
                                Pill('حاضر ${present.length + extra.length}',
                                    color: Colors.white),
                                const SizedBox(width: 8),
                                Pill('غائب ${absent.length}',
                                    color: AppColors.gold),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                    if (_canEdit)
                      const Padding(
                        padding: EdgeInsets.only(top: 10),
                        child: Text(
                            'اضغط على اسم الطالب لتبديل حالته (حضور يدوي / غياب)',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                                color: AppColors.muted, fontSize: 12)),
                      ),
                    SectionTitle('الحاضرون (${present.length + extra.length})'),
                    ...present.map((x) => _studentTile(x, recs[x.id])),
                    ...extra.map((a) => Card(
                          margin: const EdgeInsets.only(bottom: 6),
                          child: ListTile(
                            leading: const Icon(Icons.check_circle,
                                color: AppColors.emerald),
                            title: Text(a.studentName),
                            subtitle: Text('الرقم الجامعي: ${a.studentId}'),
                          ),
                        )),
                    SectionTitle('الغائبون (${absent.length})'),
                    ...absent.map((x) => _studentTile(x, null)),
                  ],
                );
              },
            ),
    );
  }

  Widget _studentTile(Student s, AttendanceRecord? rec) {
    final present = rec != null;
    return Card(
      margin: const EdgeInsets.only(bottom: 6),
      child: ListTile(
        onTap: _canEdit ? () => _toggle(s, rec) : null,
        leading: Icon(present ? Icons.check_circle : Icons.cancel,
            color: present ? AppColors.emerald : AppColors.rose),
        title: Text(s.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Text(
            rec != null
                ? 'الرقم الجامعي: ${s.id} • ${fmtTime(rec.dateTime)} • ${methodName(rec.method)}'
                : 'الرقم الجامعي: ${s.id} • ${shiftName(s.shift)}',
            style: const TextStyle(fontSize: 12)),
      ),
    );
  }
}
