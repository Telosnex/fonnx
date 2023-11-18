int wcslen(String s) {
  // Initialize the length counter to 0.
  int len = 0;

  // Iterate over the string and check each code unit.
  while (len < s.length && s.codeUnitAt(len) != 0) {
    // Increment the counter for each character until a null character is found.
    len++;
  }

  // Return the counted length, which is either up to the first null character or the full string length.
  return len;
}