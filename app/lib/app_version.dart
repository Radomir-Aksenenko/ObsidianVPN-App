/// App version shown in About and sent in the update check. Override at build time with `--dart-define=APP_VERSION=...`.
const String kAppVersion = String.fromEnvironment(
  'APP_VERSION',
  defaultValue: '2.0.0',
);
