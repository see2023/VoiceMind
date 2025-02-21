import 'package:simple_logger/simple_logger.dart';

class Log {
  static final SimpleLogger log = SimpleLogger()
    ..setLevel(Level.FINEST, includeCallerInfo: true);
}
