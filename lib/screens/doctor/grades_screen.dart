import 'package:flutter/material.dart';

import '../../app_state.dart';
import '../../data/repo.dart';
import '../../models.dart';
import '../../services/excel_import.dart';
import '../../theme.dart';
import '../../widgets/common.dart';

/// رصد درجات مادة: تبويب لكل مكوّن (اختبارات، واجبات، مختبر، حضور، فصلي، نهائي) + المجموع.
class GradesScreen extends StatefulWidget {
  final Course course;
  const GradesScreen({super.key, required this.course});

  @override
  State<GradesScreen> createState() => _GradesScreenState();
}

class _GradesScreenState extends State<GradesScreen> {
  bool _loading = true;
  GradeScheme? _scheme;
  List<Student> _students = [];
  Map<String, GradeRecord> _records = {};
  final Map<String, Map<String, double?>> _edits = {}; // studentId -> comp -> value
  int _version = 0; // لإعادة بناء الحقول بعد الاستيراد

  bool get _dirty => _edits.values.any((m) => m.isNotEmpty);

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final r = await Future.wait([
        repo.scheme(widget.course.id),
        repo.students(),
        repo.gradesForCourse(widget.course.id),
      ]);
      _scheme = r[0] as GradeScheme;
      _students =
          Stats.eligibleStudents(r[1] as List<Student>, widget.course, 'all');
      _records = {for (final g in r[2] as List<GradeRecord>) g.studentId: g};
      _edits.clear();
      _version++;
    } catch (e) {
      if (mounted) showSnack(context, friendlyError(e), error: true);
    }
    if (mounted) setState(() => _loading = false);
  }

  double? _value(String sid, String comp) {
    final e = _edits[sid];
    if (e != null && e.containsKey(comp)) return e[comp];
    return _records[sid]?.marks[comp];
  }

  void _set(String sid, String comp, double? v) {
    (_edits[sid] ??= {})[comp] = v;
    setState(() {});
  }

  Future<bool> _save({bool silent = false}) async {
    if (!_dirty) return true;
    final out = <GradeRecord>[];
    for (final e in _edits.entries) {
      final st = _students.where((s) => s.id == e.key).firstOrNull;
      final old = _records[e.key];
      final marks = Map<String, double>.from(old?.marks ?? {});
      e.value.forEach((k, v) {
        if (v == null) {
          marks.remove(k);
        } else {
          marks[k] = v;
        }
      });
      out.add(GradeRecord(
        courseId: widget.course.id,
        studentId: e.key,
        studentName: st?.name ?? old?.studentName ?? '',
        studentEmail: st?.email ?? old?.studentEmail,
        marks: marks,
      ));
    }
    final ok = await runBusy(context, () async {
      await repo.saveGradesBulk(out);
      return true;
    }, success: silent ? null : 'تم حفظ ${out.length} سجل درجات');
    if (ok == true) {
      for (final g in out) {
        _records[g.studentId] = g;
      }
      _edits.clear();
      if (mounted) setState(() {});
      return true;
    }
    return false;
  }

  // ---------------- توزيع الدرجات والنشر ----------------
  Future<void> _editScheme() async {
    final sch = _scheme!;
    final ctrls = {
      for (final k in gradeComponents)
        k: TextEditingController(text: _fmt(sch.max[k] ?? 0))
    };
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => StatefulBuilder(builder: (c, setD) {
        final total = gradeComponents.fold<double>(
            0, (a, k) => a + (double.tryParse(ctrls[k]!.text) ?? 0));
        return AlertDialog(
          title: const Text('توزيع الدرجات'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('اكتب 0 للمكوّن غير المستخدم في هذه المادة.',
                    style: TextStyle(fontSize: 12, color: AppColors.muted)),
                const SizedBox(height: 8),
                ...gradeComponents.map((k) => Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: TextField(
                        controller: ctrls[k],
                        keyboardType: const TextInputType.numberWithOptions(
                            decimal: true),
                        onChanged: (_) => setD(() {}),
                        decoration: InputDecoration(
                            labelText: componentName(k), isDense: true),
                      ),
                    )),
                Text('المجموع: ${_fmt(total)} من 100',
                    style: TextStyle(
                        fontWeight: FontWeight.w800,
                        color: total == 100 ? AppColors.emerald : AppColors.rose)),
              ],
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(c, false),
                child: const Text('إلغاء')),
            FilledButton(
                onPressed: () => Navigator.pop(c, true),
                child: const Text('حفظ')),
          ],
        );
      }),
    );
    if (ok != true || !mounted) return;
    final max = {
      for (final k in gradeComponents)
        k: (double.tryParse(ctrls[k]!.text) ?? 0).clamp(0, 100).toDouble()
    };
    final n = GradeScheme(
        courseId: widget.course.id, max: max, published: sch.published);
    final r = await runBusy(context, () async {
      await repo.saveScheme(n);
      return true;
    }, success: 'تم حفظ التوزيع');
    if (r == true) setState(() => _scheme = n);
  }

  Future<void> _publish() async {
    final sch = _scheme!;
    final sel = {...sch.published};
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, setD) => AlertDialog(
          title: const Text('نشر الدرجات للطلبة'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: sch.active
                .map((k) => CheckboxListTile(
                      value: sel.contains(k),
                      title: Text(componentName(k)),
                      onChanged: (v) =>
                          setD(() => v == true ? sel.add(k) : sel.remove(k)),
                    ))
                .toList(),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(c, false),
                child: const Text('إلغاء')),
            FilledButton(
                onPressed: () => Navigator.pop(c, true),
                child: const Text('حفظ')),
          ],
        ),
      ),
    );
    if (ok != true || !mounted) return;
    final n =
        GradeScheme(courseId: widget.course.id, max: sch.max, published: sel);
    final r = await runBusy(context, () async {
      await repo.saveScheme(n);
      return true;
    }, success: 'تم تحديث ما يراه الطلبة');
    if (r == true) setState(() => _scheme = n);
  }

  // ---------------- Excel ----------------
  Future<void> _template() async {
    await GradesExcel.shareTemplate(
        widget.course, _students, _scheme!, _records);
  }

  Future<void> _import() async {
    GradeFile? file;
    try {
      file = await GradesExcel.pick();
    } catch (e) {
      if (mounted) showSnack(context, friendlyError(e), error: true);
      return;
    }
    if (file == null || !mounted) return;
    final rows = file.rows;
    if (rows.isEmpty) {
      showSnack(context,
          'لم أجد عمود "الرقم المعرفي" مع درجات مرصودة. استخدم سجل الدرجات الجاهز.',
          error: true);
      return;
    }
    // اعتماد الدرجات القصوى المكتوبة في عناوين الملف، مثل "المشروع (10)"
    var sch = _scheme!;
    final changed = file.headerMax.entries
        .where((e) => (sch.max[e.key] ?? 0) != e.value)
        .toList();
    String? schemeNote;
    if (changed.isNotEmpty) {
      final max = Map<String, double>.from(sch.max);
      for (final e in changed) {
        max[e.key] = e.value;
      }
      // المكوّنات غير الموجودة في الملف تبقى كما هي
      final n = GradeScheme(
          courseId: widget.course.id, max: max, published: sch.published);
      try {
        await repo.saveScheme(n);
        sch = n;
        _scheme = n;
        schemeNote = 'حُدِّث توزيع الدرجات حسب الملف: ' +
            changed
                .map((e) => '${componentName(e.key)} ${_fmt(e.value)}')
                .join('، ');
      } catch (_) {}
    }
    final ids = {for (final s in _students) s.id};
    final errors = <String>[];
    var applied = 0;
    for (final r in rows) {
      if (!ids.contains(r.studentId)) {
        errors.add('صف ${r.row}: الرقم ${r.studentId} ليس من طلبة المادة');
        continue;
      }
      var rowOk = false;
      r.marks.forEach((k, v) {
        final mx = sch.max[k] ?? 0;
        if (mx <= 0) return;
        if (v == null) {
          errors.add('صف ${r.row}: قيمة غير رقمية في ${componentName(k)}');
        } else if (v < 0 || v > mx) {
          errors.add(
              'صف ${r.row}: ${componentName(k)} = ${_fmt(v)} خارج المدى (0–${_fmt(mx)})');
        } else {
          (_edits[r.studentId] ??= {})[k] = v;
          rowOk = true;
        }
      });
      if (rowOk) applied++;
    }
    _version++;
    setState(() {});
    if (!mounted) return;
    await showDialog(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('نتيجة قراءة الملف'),
        content: SizedBox(
          width: double.maxFinite,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('قُرئت درجات $applied طالباً. راجعها ثم اضغط "حفظ الدرجات" لمزامنتها مع لوحات الطلبة.',
                  style: const TextStyle(fontWeight: FontWeight.w700)),
              if (schemeNote != null) ...[
                const SizedBox(height: 8),
                Text(schemeNote!,
                    style: const TextStyle(
                        fontSize: 12.5, color: AppColors.royal)),
              ],
              if (errors.isNotEmpty) ...[
                const SizedBox(height: 10),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 220),
                  child: ListView(
                    shrinkWrap: true,
                    children: errors
                        .take(100)
                        .map((e) =>
                            Text('• $e', style: const TextStyle(fontSize: 12)))
                        .toList(),
                  ),
                ),
              ],
            ],
          ),
        ),
        actions: [
          FilledButton(
              onPressed: () => Navigator.pop(c), child: const Text('تم')),
        ],
      ),
    );
  }

  /// احتساب درجة الحضور من سجلات الحضور الفعلية.
  Future<void> _autoAttendance() async {
    final mx = _scheme!.max['attendance'] ?? 0;
    if (mx <= 0) return;
    final ok = await confirmDialog(context, 'احتساب درجة الحضور',
        'ستُحسب درجة الحضور لكل طالب = ${_fmt(mx)} × نسبة حضوره في محاضرات المادة.',
        ok: 'احتساب');
    if (!ok || !mounted) return;
    final r = await runBusy(context, () async {
      final sessions = await repo.sessionsForCourse(widget.course.id);
      final att = await repo.attendanceForCourse(widget.course.id);
      final by = <String, Set<String>>{};
      for (final a in att) {
        (by[a.studentId] ??= {}).add(a.sessionId);
      }
      return (sessions, by);
    });
    if (r == null) return;
    final (sessions, by) = r;
    if (sessions.isEmpty) {
      if (mounted) showSnack(context, 'لا توجد محاضرات مسجلة بعد', error: true);
      return;
    }
    for (final s in _students) {
      final st = Stats.forStudent(s, sessions, by[s.id] ?? {});
      if (st.total == 0) continue;
      final v = (mx * st.present / st.total * 2).round() / 2; // لأقرب نصف درجة
      (_edits[s.id] ??= {})['attendance'] = v;
    }
    _version++;
    setState(() {});
    if (mounted) showSnack(context, 'تم الاحتساب، راجع ثم اضغط حفظ');
  }

  static String _fmt(double v) =>
      v == v.roundToDouble() ? v.toInt().toString() : v.toStringAsFixed(1);

  // ---------------- الواجهة ----------------
  @override
  Widget build(BuildContext context) {
    if (_loading || _scheme == null) {
      return Scaffold(
        appBar: gradientAppBar('الدرجات'),
        body: const Center(child: CircularProgressIndicator()),
      );
    }
    final sch = _scheme!;
    final comps = sch.active;
    return PopScope(
      canPop: !_dirty,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        final leave = await confirmDialog(context, 'تغييرات غير محفوظة',
            'لديك درجات غير محفوظة. هل تريد حفظها؟',
            ok: 'حفظ');
        if (leave) {
          if (await _save() && mounted) Navigator.pop(context);
        } else if (mounted) {
          _edits.clear();
          Navigator.pop(context);
        }
      },
      child: DefaultTabController(
        length: comps.length + 1,
        child: Scaffold(
          appBar: gradientAppBar(
            widget.course.nameAr,
            actions: [
              PopupMenuButton<String>(
                icon: const Icon(Icons.more_vert),
                onSelected: (v) => switch (v) {
                  'scheme' => _editScheme(),
                  'publish' => _publish(),
                  'tpl' => _template(),
                  'imp' => _import(),
                  _ => _autoAttendance(),
                },
                itemBuilder: (_) => const [
                  PopupMenuItem(value: 'imp', child: Text('رفع سجل الدرجات (Excel)')),
                  PopupMenuItem(value: 'tpl', child: Text('تنزيل سجل الدرجات (Excel)')),
                  PopupMenuItem(value: 'att', child: Text('احتساب درجة الحضور تلقائياً')),
                  PopupMenuItem(value: 'publish', child: Text('نشر الدرجات للطلبة')),
                  PopupMenuItem(value: 'scheme', child: Text('توزيع الدرجات')),
                ],
              ),
            ],
            bottom: TabBar(
              isScrollable: true,
              tabAlignment: TabAlignment.start,
              labelColor: Colors.white,
              unselectedLabelColor: Colors.white70,
              indicatorColor: AppColors.gold,
              indicatorWeight: 3,
              tabs: [
                ...comps.map((k) => Tab(
                    text:
                        '${componentName(k)} (${_fmt(sch.max[k]!)})${sch.published.contains(k) ? ' ✓' : ''}')),
                const Tab(text: 'المجموع'),
              ],
            ),
          ),
          floatingActionButton: _dirty
              ? FloatingActionButton.extended(
                  onPressed: () => _save(),
                  icon: const Icon(Icons.save),
                  label: const Text('حفظ الدرجات'),
                )
              : null,
          body: _students.isEmpty
              ? const EmptyState(
                  icon: Icons.groups, text: 'لا يوجد طلبة لهذه المادة')
              : TabBarView(
                  children: [
                    ...comps.map((k) => _compTab(k, sch.max[k]!)),
                    _totalTab(sch),
                  ],
                ),
        ),
      ),
    );
  }

  Widget _compTab(String comp, double max) {
    final filled = _students.where((s) => _value(s.id, comp) != null).length;
    return Column(
      children: [
        Container(
          width: double.infinity,
          color: Colors.white,
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
          child: Row(
            children: [
              Text('من ${_fmt(max)} • مرصود $filled/${_students.length}',
                  style: const TextStyle(color: AppColors.muted)),
              const Spacer(),
              Pill(
                  _scheme!.published.contains(comp) ? 'منشورة للطلبة' : 'غير منشورة',
                  color: _scheme!.published.contains(comp)
                      ? AppColors.emerald
                      : AppColors.muted),
              if (comp == 'attendance') ...[
                const SizedBox(width: 6),
                IconButton(
                  tooltip: 'احتساب تلقائي',
                  onPressed: _autoAttendance,
                  icon: const Icon(Icons.auto_fix_high, color: AppColors.royal),
                ),
              ],
            ],
          ),
        ),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 90),
            itemCount: _students.length,
            itemBuilder: (_, i) {
              final s = _students[i];
              final v = _value(s.id, comp);
              final changed = _edits[s.id]?.containsKey(comp) ?? false;
              return Card(
                margin: const EdgeInsets.only(bottom: 6),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 6, 10, 6),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(s.name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                    fontWeight: FontWeight.w600)),
                            Text('الرقم الجامعي: ${s.id}',
                                style: const TextStyle(
                                    fontSize: 11.5, color: AppColors.muted)),
                          ],
                        ),
                      ),
                      SizedBox(
                        width: 84,
                        child: TextFormField(
                          key: ValueKey('$comp-${s.id}-$_version'),
                          initialValue: v == null ? '' : _fmt(v),
                          textAlign: TextAlign.center,
                          keyboardType: const TextInputType.numberWithOptions(
                              decimal: true),
                          style: TextStyle(
                              fontWeight: FontWeight.w800,
                              color: changed ? AppColors.orange : AppColors.text),
                          decoration: InputDecoration(
                            isDense: true,
                            hintText: '—',
                            contentPadding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 10),
                            errorText: (v != null && (v < 0 || v > max))
                                ? '!'
                                : null,
                          ),
                          onChanged: (t) {
                            final x = double.tryParse(t.replaceAll(',', '.'));
                            if (t.trim().isEmpty) {
                              _set(s.id, comp, null);
                            } else if (x != null) {
                              _set(s.id, comp, x);
                            }
                          },
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _totalTab(GradeScheme sch) {
    final comps = sch.active;
    final rows = _students.map((s) {
      final total = comps.fold<double>(0, (a, k) => a + (_value(s.id, k) ?? 0));
      final hasFinal = _value(s.id, 'final') != null || (sch.max['final'] ?? 0) == 0;
      return (s, total, hasFinal);
    }).toList()
      ..sort((a, b) => b.$2.compareTo(a.$2));
    final finished = rows.where((r) => r.$3).toList();
    final passed = finished.where((r) => gradeLetter(r.$2).pass).length;
    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
              gradient: AppColors.mainGradient,
              borderRadius: BorderRadius.circular(18)),
          child: Row(
            children: [
              _mini('الطلبة', '${rows.length}'),
              _mini('اكتملت درجاتهم', '${finished.length}'),
              _mini('ناجح', '$passed'),
              _mini('راسب', '${finished.length - passed}'),
            ],
          ),
        ),
        const SizedBox(height: 10),
        ...rows.map((r) {
          final (s, total, done) = r;
          final g = gradeLetter(total);
          final color = !done
              ? AppColors.muted
              : (g.pass ? AppColors.emerald : AppColors.rose);
          return Card(
            margin: const EdgeInsets.only(bottom: 6),
            child: ListTile(
              title: Text(s.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w600)),
              subtitle: Text(
                  'الرقم الجامعي: ${s.id}\n${comps.map((k) => '${componentName(k)}: ${_value(s.id, k) == null ? '—' : _fmt(_value(s.id, k)!)}').join(' • ')}',
                  style: const TextStyle(fontSize: 11.5)),
              isThreeLine: true,
              trailing: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(_fmt(total),
                      style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w900,
                          color: color)),
                  Text(done ? g.label : 'غير مكتمل',
                      style: TextStyle(fontSize: 11, color: color)),
                ],
              ),
            ),
          );
        }),
      ],
    );
  }

  Widget _mini(String l, String v) => Expanded(
        child: Column(
          children: [
            Text(v,
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.w900)),
            Text(l,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white70, fontSize: 11)),
          ],
        ),
      );
}
