import 'dart:convert';

String? decodeAttendanceQrToken(String rawValue) {
  try {
    final payload = jsonDecode(rawValue);
    if (payload is! Map ||
        payload['type'] != 'timetrack_attendance' ||
        payload['token'] is! String) {
      return null;
    }

    final token = payload['token'] as String;
    final isUuid = RegExp(
      r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
    ).hasMatch(token);
    return isUuid ? token : null;
  } on FormatException {
    return null;
  }
}
