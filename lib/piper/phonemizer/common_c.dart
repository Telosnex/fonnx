bool isspace2(int c) {
  // can't use isspace() because on Windows, isspace(0xe1) gives TRUE !
  if (((c & 0xff) == 0) || (c > 32 /*' ' has ASCII value 32 */)) {
    return false;
  }
  return true;
}
