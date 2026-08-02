import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/date.dart';
import '../../../core/theme/app_theme.dart';
import '../../../data/database.dart';
import '../../../data/providers.dart';
import '../../../features/calendar/korean_holidays.dart';
import '../../../features/notes/note_schedule.dart';
import '../../shared/calendar_entries.dart';
import 'package:my_little_budget/features/calendar/providers.dart';
import '../../shared/notes_calendar.dart' as note_calendar;
import 'package:my_little_budget/features/notes/providers.dart';

class CalendarScreen extends ConsumerStatefulWidget {
  const CalendarScreen({super.key});

  @override
  ConsumerState<CalendarScreen> createState() => _CalendarScreenState();
}

class _CalendarScreenState extends ConsumerState<CalendarScreen> {
  String _month = currentMonthKey();

  @override
  Widget build(BuildContext context) {
    final events = ref.watch(calendarEventsProvider);
    final notes = ref.watch(notesProvider);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '캘린더',
                    style: TextStyle(fontSize: 26, fontWeight: FontWeight.bold),
                  ),
                  SizedBox(height: 4),
                  Text('일정, 반복 일정, 알림 리드를 월간 보기로 관리합니다.'),
                ],
              ),
            ),
            FilledButton.icon(
              key: const ValueKey('desktop-calendar-add-button'),
              onPressed: () => _CalendarEventDialog.show(context),
              icon: const Icon(Icons.add, size: 18),
              label: const Text('일정 추가'),
            ),
          ],
        ),
        const SizedBox(height: 20),
        _MonthNav(
          month: _month,
          onChanged: (value) => setState(() => _month = value),
        ),
        const SizedBox(height: 16),
        Expanded(
          child: events.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (error, _) => Center(child: Text('캘린더를 불러오지 못했습니다. $error')),
            data: (value) {
              final eventEntries = calendarOccurrencesByDate(value, _month);
              final holidays = koreanHolidaysForMonth(_month);
              return notes.when(
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (error, _) =>
                    Center(child: Text('메모를 불러오지 못했습니다. $error')),
                data: (noteRows) {
                  final noteEntries = note_calendar.noteCalendarEntriesByDate(
                    noteRows,
                    _month,
                  );
                  final entries = _combineCalendarEntries(
                    eventEntries,
                    noteEntries,
                    holidays,
                  );
                  return LayoutBuilder(
                    builder: (context, constraints) {
                      final showAgenda = constraints.maxWidth >= 1200;
                      return Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            flex: 3,
                            child: _CalendarGrid(
                              month: _month,
                              entries: entries,
                            ),
                          ),
                          if (showAgenda) ...[
                            const SizedBox(width: 16),
                            SizedBox(
                              width: 360,
                              child: _AgendaList(
                                month: _month,
                                entries: entries,
                              ),
                            ),
                          ],
                        ],
                      );
                    },
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }
}

class _MonthNav extends StatelessWidget {
  const _MonthNav({required this.month, required this.onChanged});

  final String month;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        IconButton(
          onPressed: () => onChanged(shiftMonth(month, -1)),
          icon: const Icon(Icons.chevron_left),
          tooltip: '이전 달',
        ),
        SizedBox(
          width: 180,
          child: Center(
            child: Text(
              calendarMonthLabel(month),
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
            ),
          ),
        ),
        IconButton(
          onPressed: () => onChanged(shiftMonth(month, 1)),
          icon: const Icon(Icons.chevron_right),
          tooltip: '다음 달',
        ),
        TextButton.icon(
          onPressed: () => onChanged(currentMonthKey()),
          icon: const Icon(Icons.today, size: 18),
          label: const Text('오늘'),
        ),
      ],
    );
  }
}

class _CalendarGrid extends StatelessWidget {
  const _CalendarGrid({required this.month, required this.entries});

  final String month;
  final Map<String, List<_CalendarEntry>> entries;

  @override
  Widget build(BuildContext context) {
    final days = calendarVisibleDays(month);
    final currentMonth = parseMonthKey(month).month;
    return Column(
      children: [
        Row(
          children: [
            for (final (index, label) in [
              '일',
              '월',
              '화',
              '수',
              '목',
              '금',
              '토',
            ].indexed)
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text(
                    label,
                    key: ValueKey('desktop-calendar-weekday-$index'),
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontWeight: FontWeight.w800,
                      color: _weekdayColor(index, theme: Theme.of(context)),
                    ),
                  ),
                ),
              ),
          ],
        ),
        Expanded(
          child: GridView.builder(
            itemCount: days.length,
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 7,
              crossAxisSpacing: 8,
              mainAxisSpacing: 8,
              childAspectRatio: 1.18,
            ),
            itemBuilder: (context, index) {
              final day = days[index];
              final key = toDateKey(day);
              return _DayCell(
                day: day,
                inMonth: day.month == currentMonth,
                entries: entries[key] ?? const [],
              );
            },
          ),
        ),
      ],
    );
  }
}

class _DayCell extends StatelessWidget {
  const _DayCell({
    required this.day,
    required this.inMonth,
    required this.entries,
  });

  final DateTime day;
  final bool inMonth;
  final List<_CalendarEntry> entries;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final repeating = entries
        .where((entry) => entry.event != null && _isRepeating(entry.event!))
        .toList();
    final oneTime = entries
        .where((entry) => entry.event == null || !_isRepeating(entry.event!))
        .toList();
    final visibleOneTimeCount = repeating.isEmpty ? 3 : 2;
    final isHoliday = entries.any((entry) => entry.holiday != null);
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        border: Border.all(color: theme.dividerColor),
        borderRadius: BorderRadius.circular(8),
        color: inMonth
            ? theme.cardTheme.color
            : theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.35),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${day.day}',
            key: ValueKey('desktop-calendar-day-${toDateKey(day)}'),
            style: TextStyle(
              fontWeight: FontWeight.w800,
              color: _calendarDayColor(
                day,
                theme: theme,
                inMonth: inMonth,
                isHoliday: isHoliday,
              ),
            ),
          ),
          const SizedBox(height: 6),
          for (final entry in oneTime.take(visibleOneTimeCount))
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: _EntryPill(entry: entry),
            ),
          if (repeating.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: _RepeatingPill(entries: repeating),
            ),
          if (entries.length >
              visibleOneTimeCount + (repeating.isEmpty ? 0 : 1))
            Text(
              '+${entries.length - visibleOneTimeCount - (repeating.isEmpty ? 0 : 1)}',
              style: TextStyle(fontSize: 11, color: context.desktopMuted),
            ),
        ],
      ),
    );
  }
}

class _EntryPill extends StatelessWidget {
  const _EntryPill({required this.entry});

  final _CalendarEntry entry;

  @override
  Widget build(BuildContext context) {
    final color = entry.color(context);
    return InkWell(
      onTap: () => entry.open(context),
      borderRadius: BorderRadius.circular(6),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Text(
          entry.shortLabel,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            color: color,
          ),
        ),
      ),
    );
  }
}

class _RepeatingPill extends StatelessWidget {
  const _RepeatingPill({required this.entries});

  final List<_CalendarEntry> entries;

  @override
  Widget build(BuildContext context) {
    final color = context.desktopAccent;
    final first = entries.first;
    return InkWell(
      onTap: () => first.open(context),
      borderRadius: BorderRadius.circular(6),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Row(
          children: [
            Icon(Icons.repeat, size: 12, color: color),
            SizedBox(width: 4),
            Expanded(
              child: Text(
                entries.length == 1 ? '반복 일정' : '반복 ${entries.length}개',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: color,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AgendaList extends StatelessWidget {
  const _AgendaList({required this.month, required this.entries});

  final String month;
  final Map<String, List<_CalendarEntry>> entries;

  @override
  Widget build(BuildContext context) {
    final keys = entries.keys.toList()..sort();
    if (keys.isEmpty) {
      return const Center(child: Text('이번 달 일정이 없습니다.'));
    }
    final seenRepeating = <int>{};
    final sections = <Widget>[];
    for (final key in keys) {
      final visible = entries[key]!.where((entry) {
        final event = entry.event;
        if (event == null || !_isRepeating(event)) return true;
        return seenRepeating.add(event.id);
      }).toList();
      if (visible.isEmpty) continue;
      sections.add(
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Text(
            calendarDayLabel(parseDateKey(key)),
            style: const TextStyle(fontWeight: FontWeight.w800),
          ),
        ),
      );
      for (final entry in visible) {
        sections.add(
          Card(
            elevation: 0,
            child: ListTile(
              dense: true,
              leading: Icon(entry.icon, color: entry.color(context)),
              title: Text(entry.title),
              subtitle: Text(entry.subtitle),
              onTap: () => entry.open(context),
            ),
          ),
        );
      }
      sections.add(const SizedBox(height: 8));
    }
    if (sections.isEmpty) {
      return const Center(child: Text('이번 달 일정이 없습니다.'));
    }
    return ListView(children: sections);
  }
}

bool _isRepeating(CalendarEvent event) {
  return NoteScheduleTypeStorage.parse(event.scheduleType).isRepeating;
}

const _holidayRed = Color(0xFFDC2626);
const _saturdayBlue = Color(0xFF2563EB);

Color _weekdayColor(int index, {required ThemeData theme}) {
  if (index == 0) return _holidayRed;
  if (index == 6) return _saturdayBlue;
  return theme.colorScheme.onSurface;
}

Color _calendarDayColor(
  DateTime day, {
  required ThemeData theme,
  required bool inMonth,
  required bool isHoliday,
}) {
  final color = isHoliday || day.weekday == DateTime.sunday
      ? _holidayRed
      : day.weekday == DateTime.saturday
      ? _saturdayBlue
      : theme.colorScheme.onSurface;
  return inMonth ? color : color.withValues(alpha: 0.45);
}

class _CalendarEntry {
  const _CalendarEntry.event(this.eventEntry)
    : noteEntry = null,
      holiday = null;
  const _CalendarEntry.note(this.noteEntry) : eventEntry = null, holiday = null;
  const _CalendarEntry.holiday(this.holiday)
    : eventEntry = null,
      noteEntry = null;

  final CalendarOccurrence? eventEntry;
  final note_calendar.NoteCalendarEntry? noteEntry;
  final KoreanHoliday? holiday;

  CalendarEvent? get event => eventEntry?.event;
  DateTime get start => eventEntry?.start ?? noteEntry?.date ?? holiday!.date;
  String get title =>
      eventEntry?.event.title ?? noteEntry?.note.title ?? holiday!.name;

  String get shortLabel {
    final event = eventEntry?.event;
    if (event != null) {
      return event.allDay
          ? event.title
          : '${calendarTimeLabel(start)} ${event.title}';
    }
    if (holiday != null) return holiday!.name;
    return '메모 ${noteEntry!.note.title}';
  }

  String get subtitle {
    final event = eventEntry?.event;
    if (event != null) {
      if (_isRepeating(event)) {
        return '반복 일정 · ${event.allDay ? '종일' : calendarTimeLabel(start)}';
      }
      return event.allDay ? '종일' : calendarTimeLabel(start);
    }
    if (holiday != null) return '대한민국 공휴일';
    return noteEntry!.label;
  }

  IconData get icon {
    final event = eventEntry?.event;
    if (event != null) {
      return _isRepeating(event) ? Icons.repeat : Icons.event_outlined;
    }
    if (holiday != null) return Icons.flag_outlined;
    return noteEntry!.overdue
        ? Icons.notification_important_outlined
        : Icons.note_alt_outlined;
  }

  Color color(BuildContext context) {
    final event = eventEntry?.event;
    if (event != null) return _eventColor(event);
    if (holiday != null) return _holidayRed;
    return noteEntry!.overdue ? context.appExpense : context.appIncome;
  }

  void open(BuildContext context) {
    final event = eventEntry?.event;
    if (event != null) {
      _CalendarEventDialog.show(context, event: event);
      return;
    }
    if (holiday != null) return;
    final id = noteEntry!.note.id;
    context.go('/notes?open=$id&tap=${DateTime.now().microsecondsSinceEpoch}');
  }
}

Map<String, List<_CalendarEntry>> _combineCalendarEntries(
  Map<String, List<CalendarOccurrence>> events,
  Map<String, List<note_calendar.NoteCalendarEntry>> notes,
  Map<String, KoreanHoliday> holidays,
) {
  final result = <String, List<_CalendarEntry>>{};
  for (final entry in events.entries) {
    result[entry.key] = [
      ...?result[entry.key],
      for (final item in entry.value) _CalendarEntry.event(item),
    ];
  }
  for (final entry in notes.entries) {
    result[entry.key] = [
      ...?result[entry.key],
      for (final item in entry.value) _CalendarEntry.note(item),
    ];
  }
  for (final entry in holidays.entries) {
    result[entry.key] = [
      _CalendarEntry.holiday(entry.value),
      ...?result[entry.key],
    ];
  }
  for (final value in result.values) {
    value.sort((a, b) {
      final time = a.start.compareTo(b.start);
      if (time != 0) return time;
      return a.title.compareTo(b.title);
    });
  }
  return result;
}

class _CalendarEventDialog extends ConsumerStatefulWidget {
  const _CalendarEventDialog({this.event});

  final CalendarEvent? event;

  static Future<void> show(BuildContext context, {CalendarEvent? event}) {
    return showDialog<void>(
      context: context,
      builder: (_) => _CalendarEventDialog(event: event),
    );
  }

  @override
  ConsumerState<_CalendarEventDialog> createState() =>
      _CalendarEventDialogState();
}

class _CalendarEventDialogState extends ConsumerState<_CalendarEventDialog> {
  late final _title = TextEditingController(text: widget.event?.title ?? '');
  late final _description = TextEditingController(
    text: widget.event?.description ?? '',
  );
  late final _location = TextEditingController(
    text: widget.event?.location ?? '',
  );
  late final _link = TextEditingController(text: widget.event?.linkUrl ?? '');
  late DateTime _date = widget.event == null
      ? DateTime.now()
      : DateTime.parse(widget.event!.startAt).toLocal();
  late TimeOfDay _startTime = TimeOfDay.fromDateTime(_date);
  late TimeOfDay _endTime = TimeOfDay.fromDateTime(
    widget.event?.endAt == null
        ? _date.add(const Duration(hours: 1))
        : DateTime.parse(widget.event!.endAt!).toLocal(),
  );
  late bool _allDay = widget.event?.allDay ?? false;
  late String _color = widget.event?.color ?? '#2563eb';
  late NoteScheduleType _repeat = widget.event == null
      ? NoteScheduleType.none
      : NoteScheduleTypeStorage.parse(widget.event!.scheduleType);
  late bool _notify = widget.event?.notificationEnabled ?? false;
  late final Set<int> _leadMinutes = {
    ...parseNoteIntList(widget.event?.notificationLeadMinutes),
  };
  bool _busy = false;

  @override
  void dispose() {
    _title.dispose();
    _description.dispose();
    _location.dispose();
    _link.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final start = DateTime(
      _date.year,
      _date.month,
      _date.day,
      _allDay ? 0 : _startTime.hour,
      _allDay ? 0 : _startTime.minute,
    );
    final end = _allDay
        ? null
        : DateTime(
            _date.year,
            _date.month,
            _date.day,
            _endTime.hour,
            _endTime.minute,
          );
    setState(() => _busy = true);
    try {
      await ref
          .read(calendarEventsDaoProvider)
          .saveEvent(
            id: widget.event?.id,
            title: _title.text,
            description: _description.text,
            startAt: start,
            endAt: end,
            allDay: _allDay,
            color: _color,
            location: _location.text,
            linkUrl: _link.text,
            schedule: NoteScheduleDraft(
              type: _repeat,
              notificationEnabled: _notify,
              notificationLeadMinutes: _leadMinutes.toList(),
            ),
          );
      if (!mounted) return;
      refreshCalendarEvents(ref);
      Navigator.pop(context);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('$error')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _delete() async {
    final id = widget.event?.id;
    if (id == null) return;
    await ref.read(calendarEventsDaoProvider).deleteEvent(id);
    if (!mounted) return;
    refreshCalendarEvents(ref);
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.event == null ? '일정 추가' : '일정 수정'),
      content: SizedBox(
        width: 460,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: _title,
                enabled: !_busy,
                autofocus: true,
                decoration: const InputDecoration(labelText: '제목'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _description,
                enabled: !_busy,
                maxLines: 3,
                decoration: const InputDecoration(labelText: '설명'),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(child: Text('날짜: ${toDateKey(_date)}')),
                  TextButton.icon(
                    onPressed: _busy ? null : _pickDate,
                    icon: const Icon(Icons.calendar_month, size: 18),
                    label: const Text('변경'),
                  ),
                ],
              ),
              SwitchListTile(
                value: _allDay,
                onChanged: _busy
                    ? null
                    : (value) => setState(() => _allDay = value),
                contentPadding: EdgeInsets.zero,
                title: const Text('종일'),
              ),
              if (!_allDay)
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _busy ? null : () => _pickTime(start: true),
                        icon: const Icon(Icons.schedule, size: 18),
                        label: Text('시작 ${_startTime.format(context)}'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _busy ? null : () => _pickTime(start: false),
                        icon: const Icon(Icons.schedule, size: 18),
                        label: Text('종료 ${_endTime.format(context)}'),
                      ),
                    ),
                  ],
                ),
              const SizedBox(height: 12),
              DropdownButtonFormField<NoteScheduleType>(
                initialValue: _repeat,
                decoration: const InputDecoration(labelText: '반복'),
                items: const [
                  DropdownMenuItem(
                    value: NoteScheduleType.none,
                    child: Text('없음'),
                  ),
                  DropdownMenuItem(
                    value: NoteScheduleType.daily,
                    child: Text('매일'),
                  ),
                  DropdownMenuItem(
                    value: NoteScheduleType.weekly,
                    child: Text('매주'),
                  ),
                  DropdownMenuItem(
                    value: NoteScheduleType.monthly,
                    child: Text('매월'),
                  ),
                  DropdownMenuItem(
                    value: NoteScheduleType.yearly,
                    child: Text('매년'),
                  ),
                ],
                onChanged: _busy
                    ? null
                    : (value) => setState(() => _repeat = value!),
              ),
              SwitchListTile(
                value: _notify,
                onChanged: _busy
                    ? null
                    : (value) => setState(() => _notify = value),
                contentPadding: EdgeInsets.zero,
                title: const Text('알림'),
              ),
              if (_notify)
                _LeadMinuteChips(
                  values: _leadMinutes,
                  onChanged: () => setState(() {}),
                ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: _color,
                decoration: const InputDecoration(labelText: '색상'),
                items: const [
                  DropdownMenuItem(value: '#2563eb', child: Text('파랑')),
                  DropdownMenuItem(value: '#16a34a', child: Text('초록')),
                  DropdownMenuItem(value: '#dc2626', child: Text('빨강')),
                  DropdownMenuItem(value: '#9333ea', child: Text('보라')),
                  DropdownMenuItem(value: '#f59e0b', child: Text('노랑')),
                ],
                onChanged: _busy
                    ? null
                    : (value) => setState(() => _color = value!),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _location,
                enabled: !_busy,
                decoration: const InputDecoration(labelText: '장소'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _link,
                enabled: !_busy,
                decoration: const InputDecoration(labelText: '링크'),
              ),
            ],
          ),
        ),
      ),
      actions: [
        if (widget.event != null)
          TextButton(
            onPressed: _busy ? null : _delete,
            child: Text('삭제', style: TextStyle(color: context.desktopExpense)),
          ),
        TextButton(
          onPressed: _busy ? null : () => Navigator.pop(context),
          child: const Text('취소'),
        ),
        FilledButton(onPressed: _busy ? null : _save, child: const Text('저장')),
      ],
    );
  }

  Future<void> _pickDate() async {
    final value = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (value != null) setState(() => _date = value);
  }

  Future<void> _pickTime({required bool start}) async {
    final value = await showTimePicker(
      context: context,
      initialTime: start ? _startTime : _endTime,
    );
    if (value == null) return;
    setState(() {
      if (start) {
        _startTime = value;
      } else {
        _endTime = value;
      }
    });
  }
}

class _LeadMinuteChips extends StatelessWidget {
  const _LeadMinuteChips({required this.values, required this.onChanged});

  final Set<int> values;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    const options = {
      0: '정시',
      10: '10분 전',
      30: '30분 전',
      60: '1시간 전',
      1440: '1일 전',
    };
    return Align(
      alignment: Alignment.centerLeft,
      child: Wrap(
        spacing: 8,
        children: [
          for (final entry in options.entries)
            FilterChip(
              label: Text(entry.value),
              selected: values.contains(entry.key),
              onSelected: (selected) {
                if (selected) {
                  values.add(entry.key);
                } else {
                  values.remove(entry.key);
                }
                onChanged();
              },
            ),
        ],
      ),
    );
  }
}

Color _eventColor(CalendarEvent event) {
  final value = event.color.replaceFirst('#', '');
  final parsed = int.tryParse(value, radix: 16) ?? 0x2563eb;
  return Color(0xFF000000 | parsed);
}
