String _now() {
  return DateTime.now().toString();
}

void log(Object message) {
  print('[${_now()}]: ${message}');
}
