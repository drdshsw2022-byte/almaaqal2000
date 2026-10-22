import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../app_state.dart';
import '../../models.dart';
import '../../theme.dart';
import '../../widgets/common.dart';

/// فتح رابط (ملف على Google Drive، فيديو، محاضرة عن بُعد...).
Future<void> openLink(BuildContext context, String? link) async {
  if (link == null || link.trim().isEmpty) return;
  var t = link.trim();
  if (!t.startsWith('http')) t = 'https://$t';
  final ok = await launchUrl(Uri.parse(t), mode: LaunchMode.externalApplication);
  if (!ok && context.mounted) {
    showSnack(context, 'تعذّر فتح الرابط', error: true);
  }
}

/// دروس مادة: الدكتور يضيف ويعدّل، والطالب يستعرض.
class LessonsScreen extends StatefulWidget {
  final Course course;
  final bool canEdit;
  const LessonsScreen({super.key, required this.course, this.canEdit = false});

  @override
  State<LessonsScreen> createState() => _LessonsScreenState();
}

class _LessonsScreenState extends State<LessonsScreen> {
  bool _loading = true;
  List<Lesson> _lessons = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      _lessons = await repo.lessonsForCourse(widget.course.id);
    } catch (e) {
      if (mounted) showSnack(context, friendlyError(e), error: true);
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _edit([Lesson? l]) async {
    final title = TextEditingController(text: l?.title);
    final desc = TextEditingController(text: l?.description);
    final link = TextEditingController(text: l?.link);
    final week = TextEditingController(
        text: '${l?.week ?? (_lessons.isEmpty ? 1 : _lessons.last.week + 1)}');
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(l == null ? 'إضافة درس' : 'تعديل الدرس'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                  controller: title,
                  decoration:
                      const InputDecoration(labelText: 'عنوان الدرس / المحاضرة')),
              const SizedBox(height: 10),
              TextField(
                  controller: week,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'الأسبوع')),
              const SizedBox(height: 10),
              TextField(
                  controller: desc,
                  maxLines: 3,
                  decoration: const InputDecoration(
                      labelText: 'وصف مختصر / واجب مطلوب')),
              const SizedBox(height: 10),
              TextField(
                  controller: link,
                  keyboardType: TextInputType.url,
                  textDirection: TextDirection.ltr,
                  decoration: const InputDecoration(
                      labelText: 'رابط الملف أو المحاضرة',
                      hintText: 'https://drive.google.com/...')),
              const SizedBox(height: 6),
              const Text(
                  'ارفع ملف المحاضرة إلى Google Drive الخاص ببريدك الجامعي، واختر "مشاركة ← أي شخص في الجامعة لديه الرابط"، ثم الصق الرابط هنا.',
                  style: TextStyle(fontSize: 11.5, color: AppColors.muted)),
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
      ),
    );
    if (ok != true || !mounted) return;
    if (title.text.trim().isEmpty) {
      showSnack(context, 'اكتب عنوان الدرس', error: true);
      return;
    }
    final x = Lesson(
      id: l?.id ?? '',
      courseId: widget.course.id,
      title: title.text.trim(),
      week: int.tryParse(week.text.trim()) ?? 1,
      description: desc.text.trim(),
      link: link.text.trim().isEmpty ? null : link.text.trim(),
      date: l?.date,
      by: AppState.user.value?.name ?? '',
    );
    await runBusy(context, () => repo.saveLesson(x), success: 'تم الحفظ');
    _load();
  }

  Future<void> _delete(Lesson l) async {
    final ok = await confirmDialog(context, 'حذف الدرس', 'حذف "${l.title}"؟',
        ok: 'حذف', danger: true);
    if (!ok || !mounted) return;
    await runBusy(context, () => repo.deleteLesson(l.id), success: 'تم الحذف');
    _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: gradientAppBar('دروس ${widget.course.nameAr}'),
      floatingActionButton: widget.canEdit
          ? FloatingActionButton.extended(
              onPressed: () => _edit(),
              icon: const Icon(Icons.add),
              label: const Text('درس'),
            )
          : null,
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _lessons.isEmpty
              ? const EmptyState(
                  icon: Icons.menu_book, text: 'لم تُضف دروس لهذه المادة بعد')
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView.builder(
                    padding: const EdgeInsets.fromLTRB(12, 12, 12, 90),
                    itemCount: _lessons.length,
                    itemBuilder: (_, i) => LessonTile(
                      lesson: _lessons[i],
                      onEdit: widget.canEdit ? () => _edit(_lessons[i]) : null,
                      onDelete:
                          widget.canEdit ? () => _delete(_lessons[i]) : null,
                    ),
                  ),
                ),
    );
  }
}

class LessonTile extends StatelessWidget {
  final Lesson lesson;
  final String? courseName;
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;
  const LessonTile(
      {super.key,
      required this.lesson,
      this.courseName,
      this.onEdit,
      this.onDelete});

  @override
  Widget build(BuildContext context) {
    final l = lesson;
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: l.link == null ? onEdit : () => openLink(context, l.link),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 48,
                height: 48,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  gradient: AppColors.tilePalette[l.week % 8],
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Text('أسبوع',
                        style: TextStyle(color: Colors.white, fontSize: 9)),
                    Text('${l.week}',
                        style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w900,
                            fontSize: 17,
                            height: 1)),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (courseName != null)
                      Text(courseName!,
                          style: const TextStyle(
                              color: AppColors.royal,
                              fontSize: 11.5,
                              fontWeight: FontWeight.w700)),
                    Text(l.title,
                        style: const TextStyle(
                            fontWeight: FontWeight.w800, fontSize: 15)),
                    if (l.description.isNotEmpty)
                      Text(l.description,
                          style: const TextStyle(fontSize: 12.5)),
                    const SizedBox(height: 4),
                    Text(
                        '${fmtDate(DateTime.fromMillisecondsSinceEpoch(l.date))}${l.by.isNotEmpty ? ' • ${l.by}' : ''}',
                        style: const TextStyle(
                            color: AppColors.muted, fontSize: 11.5)),
                  ],
                ),
              ),
              if (l.link != null)
                const Padding(
                  padding: EdgeInsets.only(top: 4),
                  child: Icon(Icons.open_in_new, color: AppColors.royal),
                ),
              if (onEdit != null || onDelete != null)
                PopupMenuButton<String>(
                  onSelected: (v) => v == 'e' ? onEdit?.call() : onDelete?.call(),
                  itemBuilder: (_) => const [
                    PopupMenuItem(value: 'e', child: Text('تعديل')),
                    PopupMenuItem(value: 'd', child: Text('حذف')),
                  ],
                ),
            ],
          ),
        ),
      ),
    );
  }
}
