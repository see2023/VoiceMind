import 'package:isar/isar.dart';

part 'user.g.dart';

@Collection()
class User {
  Id id = Isar.autoIncrement;

  @Index()
  final String name; // 用户名称

  User({
    required this.name,
  });
}
