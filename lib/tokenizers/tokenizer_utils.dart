List<String> whitespaceTokenize(String text) {
  text = text.trim();
  if (text.isEmpty) return [];
  return text.split(RegExp(r'\s+'));
}
