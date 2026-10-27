import 'package:http/http.dart';

/// One client for every 4chan API call, so requests reuse the keep-alive
/// connection to a.4cdn.org instead of opening a new one each time.
final Client httpClient = Client();
