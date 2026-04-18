import 'config.dart';

class Environment {
  static const String development = 'development';
  static const String production = 'production';

  static final Environment _instance = Environment._internal();
  factory Environment() => _instance;
  Environment._internal();

  late BaseConfig _config;

  void initConfig(String flavor) {
    _config = switch (flavor) {
      Environment.production => ProdConfig(),
      _ => DevConfig(),
    };
  }

  BaseConfig get config => _config;
}
