import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../services/attendance_service.dart';
import '../services/leave_request_service.dart';
import '../services/profile_service.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final AttendanceService _attendanceService = AttendanceService();
  final LeaveRequestService _leaveRequestService = LeaveRequestService();
  final ProfileService _profileService = ProfileService();

  Map<String, dynamic>? _attendance;
  Map<String, dynamic>? _profile;
  Map<String, dynamic>? _paySummary;
  List<Map<String, dynamic>> _history = [];
  List<Map<String, dynamic>> _leaveRequests = [];
  final TextEditingController _leaveReasonController = TextEditingController();
  String _leaveType = 'Vacation';
  DateTime? _leaveStartDate;
  DateTime? _leaveEndDate;
  bool _isLoading = true;
  int _selectedIndex = 0;

  @override
  void initState() {
    super.initState();
    _loadDashboard();
  }

  Future<void> _loadDashboard() async {
    try {
      final results = await Future.wait([
        _attendanceService.getTodayAttendance(),
        _profileService.getProfile(),
        _attendanceService.getAttendanceHistory(),
        _leaveRequestService.getMyRequests(),
        _attendanceService.getMonthlyPaySummary(),
      ]);

      if (!mounted) return;

      setState(() {
        _attendance = results[0] as Map<String, dynamic>?;
        _profile = results[1] as Map<String, dynamic>?;
        _history = results[2] as List<Map<String, dynamic>>;
        _leaveRequests = results[3] as List<Map<String, dynamic>>;
        _paySummary = results[4] as Map<String, dynamic>;
        _isLoading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      _showMessage('Failed to load dashboard: $error');
    }
  }

  Future<void> _runAction(
    Future<void> Function() action,
    String successMessage,
  ) async {
    setState(() => _isLoading = true);

    try {
      await action();
      await _loadDashboard();
      if (!mounted) return;
      _showMessage(successMessage);
    } catch (error) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      _showMessage(error.toString().replaceFirst('Bad state: ', ''));
    }
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _selectLeaveDate({required bool isStartDate}) async {
    final selectedDate = await showDatePicker(
      context: context,
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 730)),
      initialDate: isStartDate
          ? (_leaveStartDate ?? DateTime.now())
          : (_leaveEndDate ?? _leaveStartDate ?? DateTime.now()),
    );

    if (selectedDate == null || !mounted) return;

    setState(() {
      if (isStartDate) {
        _leaveStartDate = selectedDate;
        if (_leaveEndDate != null && _leaveEndDate!.isBefore(selectedDate)) {
          _leaveEndDate = selectedDate;
        }
      } else {
        _leaveEndDate = selectedDate;
      }
    });
  }

  Future<void> _submitLeaveRequest() async {
    if (_leaveStartDate == null || _leaveEndDate == null) {
      _showMessage('Please select a start and end date.');
      return;
    }

    if (_leaveEndDate!.isBefore(_leaveStartDate!)) {
      _showMessage('The end date cannot be before the start date.');
      return;
    }

    setState(() => _isLoading = true);

    try {
      await _leaveRequestService.createRequest(
        leaveType: _leaveType,
        startDate: _leaveStartDate!,
        endDate: _leaveEndDate!,
        reason: _leaveReasonController.text,
      );

      _leaveReasonController.clear();
      _leaveStartDate = null;
      _leaveEndDate = null;
      await _loadDashboard();

      if (!mounted) return;
      _showMessage('Leave request submitted.');
    } catch (error) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      _showMessage('Unable to submit leave request.');
    }
  }

  Future<void> _logout() async {
    await Supabase.instance.client.auth.signOut();
    if (!mounted) return;
    Navigator.pushNamedAndRemoveUntil(context, '/', (route) => false);
  }

  String get _displayName {
    final name = _profile?['full_name'] as String?;
    if (name != null && name.trim().isNotEmpty) return name.trim();
    return Supabase.instance.client.auth.currentUser?.email ?? 'Employee';
  }

  String get _todayLabel {
    final now = DateTime.now();
    const months = [
      'January',
      'February',
      'March',
      'April',
      'May',
      'June',
      'July',
      'August',
      'September',
      'October',
      'November',
      'December',
    ];
    return '${months[now.month - 1]} ${now.day}, ${now.year}';
  }

  String _formatDate(String? value) {
    if (value == null || value.isEmpty) return '-';
    final date = DateTime.tryParse(value);
    if (date == null) return value;
    return '${date.month}/${date.day}/${date.year}';
  }

  String _timeValue(String? value) {
    if (value == null || value.isEmpty) return '--:--';

    final timestamp = DateTime.tryParse(value);

    if (timestamp != null) {
      final hour = timestamp.toLocal().hour;
      final minute = timestamp.toLocal().minute.toString().padLeft(2, '0');
      final suffix = hour >= 12 ? 'PM' : 'AM';
      final displayHour = hour % 12 == 0 ? 12 : hour % 12;
      return '$displayHour:$minute $suffix';
    }

    final parts = value.split(':');
    if (parts.length < 2) return value;
    final hour = int.tryParse(parts[0]) ?? 0;
    final suffix = hour >= 12 ? 'PM' : 'AM';
    final displayHour = hour % 12 == 0 ? 12 : hour % 12;
    return '$displayHour:${parts[1]} $suffix';
  }

  @override
  Widget build(BuildContext context) {
    final pages = [
      _buildDashboard(),
      _buildHistory(),
      _buildLeaveRequests(),
      _buildProfile(),
    ];

    return Scaffold(
      backgroundColor: const Color(0xfff3f5f9),
      appBar: AppBar(
        backgroundColor: const Color(0xfff3f5f9),
        titleSpacing: 20,
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: const Color(0xff4f46e5),
                borderRadius: BorderRadius.circular(14),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x334f46e5),
                    offset: Offset(4, 4),
                    blurRadius: 10,
                  ),
                ],
              ),
              child: const Icon(Icons.access_time, color: Colors.white),
            ),
            const SizedBox(width: 10),
            const Text(
              'TimeTrack',
              style: TextStyle(
                color: Color(0xff1f2937),
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Sign out',
            onPressed: _logout,
            icon: const Icon(Icons.logout_rounded),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SafeArea(child: pages[_selectedIndex]),
      bottomNavigationBar: NavigationBar(
        backgroundColor: const Color(0xffe9edf4),
        indicatorColor: const Color(0x264f46e5),
        selectedIndex: _selectedIndex,
        onDestinationSelected: (index) {
          setState(() => _selectedIndex = index);
          if (index == 2) {
            _loadDashboard();
          }
        },
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.dashboard_outlined),
            selectedIcon: Icon(Icons.dashboard),
            label: 'Dashboard',
          ),
          NavigationDestination(
            icon: Icon(Icons.event_note_outlined),
            selectedIcon: Icon(Icons.event_note),
            label: 'History',
          ),
          NavigationDestination(
            icon: Icon(Icons.beach_access_outlined),
            selectedIcon: Icon(Icons.beach_access),
            label: 'Leave',
          ),
          NavigationDestination(
            icon: Icon(Icons.person_outline),
            selectedIcon: Icon(Icons.person),
            label: 'Profile',
          ),
        ],
      ),
    );
  }

  Widget _buildDashboard() {
    final hasTimeIn = _attendance?['time_in'] != null;
    final hasBreakIn = _attendance?['break_in'] != null;
    final hasBreakOut = _attendance?['break_out'] != null;
    final hasTimeOut = _attendance?['time_out'] != null;
    final completedCount = [
      hasTimeIn,
      hasBreakIn,
      hasBreakOut,
      hasTimeOut,
    ].where((value) => value).length;

    return RefreshIndicator(
      onRefresh: _loadDashboard,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
        children: [
          Text(
            'Good day, ${_displayName.split(' ').first}',
            style: const TextStyle(
              color: Color(0xff1f2937),
              fontSize: 28,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Here is your attendance overview for today.',
            style: TextStyle(color: Colors.blueGrey.shade600, fontSize: 15),
          ),
          const SizedBox(height: 20),
          _buildSummaryCard(completedCount),
          const SizedBox(height: 18),
          _buildPaySummaryCard(),
          const SizedBox(height: 18),
          _sectionTitle('Today\'s time log', _todayLabel),
          const SizedBox(height: 10),
          _buildTimeline(hasTimeIn, hasBreakIn, hasBreakOut, hasTimeOut),
          if (_overbreakMinutes > 0) ...[
            const SizedBox(height: 14),
            _buildOverbreakNotice(),
          ],
          const SizedBox(height: 18),
          _buildActionCard(hasTimeIn, hasBreakIn, hasBreakOut, hasTimeOut),
        ],
      ),
    );
  }

  Widget _buildSummaryCard(int completedCount) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xff4f46e5),
        boxShadow: const [
          BoxShadow(
            color: Color(0x409ba8bb),
            offset: Offset(8, 8),
            blurRadius: 18,
          ),
          BoxShadow(
            color: Colors.white,
            offset: Offset(-6, -6),
            blurRadius: 14,
          ),
        ],
        borderRadius: BorderRadius.circular(22),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'ATTENDANCE STATUS',
                  style: TextStyle(
                    color: Color(0xffc7d2fe),
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.1,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  completedCount == 4 ? 'Shift completed' : 'In progress',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  '$completedCount of 4 checkpoints recorded',
                  style: const TextStyle(color: Color(0xffe0e7ff)),
                ),
              ],
            ),
          ),
          SizedBox(
            width: 74,
            height: 74,
            child: Stack(
              alignment: Alignment.center,
              children: [
                CircularProgressIndicator(
                  value: completedCount / 4,
                  strokeWidth: 8,
                  backgroundColor: const Color(0xff3730a3),
                  valueColor: const AlwaysStoppedAnimation(Color(0xffa5b4fc)),
                ),
                Text(
                  '${completedCount * 25}%',
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPaySummaryCard() {
    final summary = _paySummary;
    final regularHours = _numberValue(summary?['regular_hours']);
    final overtimeHours = _numberValue(summary?['overtime_hours']);
    final estimatedPay = _numberValue(summary?['estimated_gross_pay']);
    final completedDays = _numberValue(summary?['completed_days']).toInt();

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xffdbe7f3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'THIS MONTH\'S WORK & PAY ESTIMATE',
            style: TextStyle(
              color: Color(0xff41637a),
              fontSize: 11,
              fontWeight: FontWeight.w800,
              letterSpacing: 1,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            _formatPeso(estimatedPay),
            style: const TextStyle(
              color: Color(0xff12343b),
              fontSize: 28,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Estimated gross pay from completed shifts only.',
            style: TextStyle(color: Colors.blueGrey.shade600, fontSize: 12),
          ),
          const Divider(height: 24),
          Row(
            children: [
              Expanded(child: _payMetric('Regular', _formatHours(regularHours))),
              Expanded(child: _payMetric('Overtime', _formatHours(overtimeHours))),
              Expanded(child: _payMetric('Completed days', '$completedDays')),
            ],
          ),
        ],
      ),
    );
  }

  Widget _payMetric(String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: TextStyle(color: Colors.blueGrey.shade500, fontSize: 12)),
        const SizedBox(height: 3),
        Text(
          value,
          style: const TextStyle(color: Color(0xff12343b), fontWeight: FontWeight.w800),
        ),
      ],
    );
  }

  double _numberValue(dynamic value) {
    if (value is num) return value.toDouble();
    return double.tryParse(value?.toString() ?? '') ?? 0;
  }

  String _formatHours(double hours) {
    final totalMinutes = (hours * 60).round();
    return '${totalMinutes ~/ 60}h ${totalMinutes % 60}m';
  }

  String _formatPeso(double value) {
    final amount = value.toStringAsFixed(2);
    final parts = amount.split('.');
    final whole = parts.first;
    final grouped = whole.replaceAllMapped(
      RegExp(r'(?<!^)(?=(\d{3})+$)'),
      (_) => ',',
    );
    return '₱$grouped.${parts.last}';
  }

  Widget _sectionTitle(String title, String trailing) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          title,
          style: const TextStyle(
            color: Color(0xff12343b),
            fontSize: 18,
            fontWeight: FontWeight.w800,
          ),
        ),
        Text(
          trailing,
          style: TextStyle(
            color: Colors.blueGrey.shade600,
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }

  Widget _buildTimeline(
    bool hasTimeIn,
    bool hasBreakIn,
    bool hasBreakOut,
    bool hasTimeOut,
  ) {
    final steps = [
      ('Time In', _attendance?['time_in'] as String?, Icons.login),
      ('Break In', _attendance?['break_in'] as String?, Icons.free_breakfast),
      ('Break Out', _attendance?['break_out'] as String?, Icons.restart_alt),
      ('Time Out', _attendance?['time_out'] as String?, Icons.logout),
    ];
    final completed = [hasTimeIn, hasBreakIn, hasBreakOut, hasTimeOut];

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xffe1e9e9)),
      ),
      child: Column(
        children: [
          for (var index = 0; index < steps.length; index++)
            _timelineRow(steps[index], completed[index], index != 0),
        ],
      ),
    );
  }

  Widget _timelineRow(
    (String, String?, IconData) step,
    bool isComplete,
    bool hasTopLine,
  ) {
    return Row(
      children: [
        SizedBox(
          width: 64,
          child: Column(
            children: [
              if (hasTopLine)
                Container(height: 14, width: 2, color: const Color(0xffd9e5e4)),
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: isComplete
                      ? const Color(0xffd9f1e9)
                      : const Color(0xffeef2f2),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  isComplete ? Icons.check : step.$3,
                  size: 16,
                  color: isComplete
                      ? const Color(0xff087f5b)
                      : Colors.blueGrey.shade400,
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 10),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  step.$1,
                  style: TextStyle(
                    color: isComplete
                        ? const Color(0xff12343b)
                        : Colors.blueGrey.shade500,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                Text(
                  _timeValue(step.$2),
                  style: TextStyle(
                    color: isComplete
                        ? const Color(0xff0c6b68)
                        : Colors.blueGrey.shade400,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(width: 18),
      ],
    );
  }

  Widget _buildActionCard(
    bool hasTimeIn,
    bool hasBreakIn,
    bool hasBreakOut,
    bool hasTimeOut,
  ) {
    String label;
    String description;
    IconData icon;
    Future<void> Function()? action;

    if (!hasTimeIn) {
      label = 'Start your shift';
      description = 'Record your Time In to begin today\'s attendance.';
      icon = Icons.login;
      action = _attendanceService.timeIn;
    } else if (!hasBreakIn) {
      label = 'Start your break';
      description = 'Your next step is Break In.';
      icon = Icons.free_breakfast;
      action = _attendanceService.breakIn;
    } else if (!hasBreakOut) {
      label = 'End your break';
      description = 'Record Break Out when you return to work.';
      icon = Icons.restart_alt;
      action = _attendanceService.breakOut;
    } else if (!hasTimeOut) {
      label = 'Finish your shift';
      description = 'Record Time Out when your workday is complete.';
      icon = Icons.logout;
      action = _attendanceService.timeOut;
    } else {
      label = 'All done for today';
      description = 'Your complete attendance record is securely saved to your account.';
      icon = Icons.verified;
      action = null;
    }

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xfffff4e6),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xffffdfb4)),
      ),
      child: Row(
        children: [
          Icon(icon, color: const Color(0xffb85c00), size: 28),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(
                    color: Color(0xff6d3d0d),
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  description,
                  style: const TextStyle(color: Color(0xff8a633c)),
                ),
              ],
            ),
          ),
          if (action != null)
            IconButton(
              tooltip: label,
              onPressed: _isLoading
                  ? null
                  : () => _runAction(action!, '$label recorded.'),
              icon: const Icon(Icons.arrow_forward_rounded),
              color: const Color(0xffb85c00),
            ),
        ],
      ),
    );
  }

  int get _overbreakMinutes {
    final breakIn = DateTime.tryParse(_attendance?['break_in'] as String? ?? '');
    final breakOut = DateTime.tryParse(
      _attendance?['break_out'] as String? ?? '',
    );

    if (breakIn == null || breakOut == null) return 0;

    final breakMinutes = breakOut.difference(breakIn).inMinutes;
    return breakMinutes > 60 ? breakMinutes - 60 : 0;
  }

  Widget _buildOverbreakNotice() {
    final hours = _overbreakMinutes ~/ 60;
    final minutes = _overbreakMinutes % 60;
    final duration = hours > 0
        ? '${hours}h ${minutes}m'
        : '${minutes}m';

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xfffff4e6),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xffffd08a)),
      ),
      child: Row(
        children: [
          const Icon(Icons.warning_amber_rounded, color: Color(0xffd97706)),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              'Overbreak noted: $duration beyond the 1-hour break allowance.',
              style: const TextStyle(
                color: Color(0xff92400e),
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHistory() {
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 28),
      children: [
        const Text(
          'Attendance history',
          style: TextStyle(
            color: Color(0xff12343b),
            fontSize: 28,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 5),
        Text(
          'Your attendance records saved to your account.',
          style: TextStyle(color: Colors.blueGrey.shade600),
        ),
        const SizedBox(height: 18),
        if (_history.isEmpty)
          _emptyState(Icons.event_busy, 'No attendance records yet.')
        else
          for (final record in _history) _historyCard(record),
      ],
    );
  }

  Widget _historyCard(Map<String, dynamic> record) {
    final complete = record['time_out'] != null;
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xffe1e9e9)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                _formatDate(record['date'] as String?),
                style: const TextStyle(
                  color: Color(0xff12343b),
                  fontWeight: FontWeight.w800,
                ),
              ),
              Text(
                complete ? 'Complete' : 'In progress',
                style: TextStyle(
                  color: complete
                      ? const Color(0xff087f5b)
                      : const Color(0xffb85c00),
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const Divider(height: 22),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _historyTime('In', record['time_in'] as String?),
              _historyTime('Break', record['break_in'] as String?),
              _historyTime('Out', record['time_out'] as String?),
            ],
          ),
        ],
      ),
    );
  }

  Widget _historyTime(String label, String? value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(color: Colors.blueGrey.shade500, fontSize: 12),
        ),
        const SizedBox(height: 3),
        Text(
          _timeValue(value),
          style: const TextStyle(
            color: Color(0xff12343b),
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }

  Widget _buildLeaveRequests() {
    return RefreshIndicator(
      onRefresh: _loadDashboard,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 28),
        children: [
          const Text(
            'Leave requests',
            style: TextStyle(
              color: Color(0xff12343b),
              fontSize: 28,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 5),
          Text(
            'Submit a request and track its status.',
            style: TextStyle(color: Colors.blueGrey.shade600),
          ),
          const SizedBox(height: 18),
          _buildLeaveForm(),
          const SizedBox(height: 20),
          const Text(
            'My requests',
            style: TextStyle(
              color: Color(0xff12343b),
              fontSize: 20,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 10),
          if (_leaveRequests.isEmpty)
            _emptyState(Icons.event_busy, 'No leave requests yet.')
          else
            for (final request in _leaveRequests) _leaveRequestCard(request),
        ],
      ),
    );
  }

  Widget _buildLeaveForm() {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xffe1e9e9)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          DropdownButtonFormField<String>(
            initialValue: _leaveType,
            decoration: const InputDecoration(labelText: 'Leave type'),
            items: const [
              DropdownMenuItem(value: 'Vacation', child: Text('Vacation')),
              DropdownMenuItem(value: 'Sick', child: Text('Sick')),
              DropdownMenuItem(value: 'Personal', child: Text('Personal')),
            ],
            onChanged: (value) {
              if (value != null) setState(() => _leaveType = value);
            },
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => _selectLeaveDate(isStartDate: true),
                  icon: const Icon(Icons.calendar_today_outlined),
                  label: Text(_leaveStartDate == null
                      ? 'Start date'
                      : _formatDate(_dateOnly(_leaveStartDate!))),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _leaveStartDate == null
                      ? null
                      : () => _selectLeaveDate(isStartDate: false),
                  icon: const Icon(Icons.calendar_today_outlined),
                  label: Text(_leaveEndDate == null
                      ? 'End date'
                      : _formatDate(_dateOnly(_leaveEndDate!))),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _leaveReasonController,
            maxLines: 3,
            decoration: const InputDecoration(
              labelText: 'Reason (optional)',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _isLoading ? null : _submitLeaveRequest,
              icon: const Icon(Icons.send_outlined),
              label: const Text('Submit request'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _leaveRequestCard(Map<String, dynamic> request) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xffe1e9e9)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                request['leave_type'] as String? ?? 'Leave',
                style: const TextStyle(
                  color: Color(0xff12343b),
                  fontWeight: FontWeight.w800,
                ),
              ),
              Text(
                (request['status'] as String? ?? 'pending').toUpperCase(),
                style: const TextStyle(
                  color: Color(0xffb85c00),
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            '${_formatDate(request['start_date'] as String?)} - ${_formatDate(request['end_date'] as String?)}',
            style: TextStyle(color: Colors.blueGrey.shade600),
          ),
          if ((request['reason'] as String?)?.isNotEmpty == true) ...[
            const SizedBox(height: 6),
            Text(request['reason'] as String),
          ],
        ],
      ),
    );
  }

  String _dateOnly(DateTime date) {
    return '${date.year.toString().padLeft(4, '0')}-'
        '${date.month.toString().padLeft(2, '0')}-'
        '${date.day.toString().padLeft(2, '0')}';
  }

  Widget _buildProfile() {
    final email =
        Supabase.instance.client.auth.currentUser?.email ?? 'No email';
    final initial = _displayName.isEmpty
        ? 'E'
        : _displayName.substring(0, 1).toUpperCase();
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 28),
      children: [
        const Text(
          'Employee profile',
          style: TextStyle(
            color: Color(0xff12343b),
            fontSize: 28,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 18),
        Container(
          padding: const EdgeInsets.all(22),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: const Color(0xffe1e9e9)),
          ),
          child: Column(
            children: [
              CircleAvatar(
                radius: 36,
                backgroundColor: const Color(0xffd9f1e9),
                child: Text(
                  initial,
                  style: const TextStyle(
                    color: Color(0xff087f5b),
                    fontSize: 28,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              const SizedBox(height: 14),
              Text(
                _displayName,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Color(0xff12343b),
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 4),
              Text(email, style: TextStyle(color: Colors.blueGrey.shade600)),
              const SizedBox(height: 24),
              _profileRow(
                Icons.badge_outlined,
                'Employee number',
                _profile?['employee_number'] as String? ?? '-',
              ),
              _profileRow(
                Icons.calendar_today_outlined,
                'Account',
                'Active employee',
              ),
            ],
          ),
        ),
      ],
    );
  }

  @override
  void dispose() {
    _leaveReasonController.dispose();
    super.dispose();
  }

  Widget _profileRow(IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(top: 14),
      child: Row(
        children: [
          Icon(icon, color: const Color(0xff0c6b68), size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              label,
              style: TextStyle(color: Colors.blueGrey.shade600),
            ),
          ),
          Text(
            value,
            style: const TextStyle(
              color: Color(0xff12343b),
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }

  Widget _emptyState(IconData icon, String text) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 48),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xffe1e9e9)),
      ),
      child: Column(
        children: [
          Icon(icon, color: Colors.blueGrey.shade300, size: 42),
          const SizedBox(height: 12),
          Text(text, style: TextStyle(color: Colors.blueGrey.shade600)),
        ],
      ),
    );
  }
}
