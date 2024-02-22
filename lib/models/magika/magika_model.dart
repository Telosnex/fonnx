enum MagikaGroup {
  application,
  archive,
  audio,
  code,
  document,
  executable,
  font,
  image,
  text,
  unknown,
  video,
}

enum MagikaTag {
  archive,
  binary,
  cdf,
  dlTarget,
  elf,
  macho,
  media,
  ooxml,
  text,
  zipArchive,
}

enum MagikaType {
  ai(
    name: 'ai',
    description: 'Adobe Illustrator Artwork',
    mimeType: 'application/pdf',
    targetLabel: 'ai',
    extensions: {
      'ai',
    },
    tags: {
      MagikaTag.binary,
    },
    groups: {
      MagikaGroup.document,
    },
  ),
  apk(
    name: 'apk',
    description: 'Android package',
    mimeType: 'application/vnd.android.package-archive',
    targetLabel: 'apk',
    extensions: {
      'apk',
    },
    tags: {
      MagikaTag.binary,
      MagikaTag.zipArchive,
      MagikaTag.archive,
    },
    groups: {
      MagikaGroup.executable,
    },
  ),
  appleplist(
    name: 'appleplist',
    description: 'Apple property list',
    mimeType: 'application/x-plist',
    targetLabel: 'appleplist',
    extensions: {
      'bplist',
      'plist',
    },
    tags: {
      MagikaTag.binary,
      MagikaTag.text,
    },
    groups: {
      MagikaGroup.application,
    },
  ),
  asm(
    name: 'asm',
    description: 'Assembly',
    mimeType: 'text/x-asm',
    targetLabel: 'asm',
    extensions: {
      'S',
      'asm',
    },
    tags: {
      MagikaTag.text,
      MagikaTag.dlTarget,
    },
    groups: {
      MagikaGroup.code,
    },
  ),
  asp(
    name: 'asp',
    description: 'ASP source',
    mimeType: 'text/html',
    targetLabel: 'asp',
    extensions: {
      'aspx',
      'asp',
    },
    tags: {
      MagikaTag.text,
      MagikaTag.dlTarget,
    },
    groups: {
      MagikaGroup.code,
    },
  ),
  batch(
    name: 'batch',
    description: 'DOS batch file',
    mimeType: 'text/x-msdos-batch',
    targetLabel: 'batch',
    extensions: {
      'bat',
    },
    tags: {
      MagikaTag.text,
      MagikaTag.dlTarget,
    },
    groups: {
      MagikaGroup.code,
    },
  ),
  bmp(
    name: 'bmp',
    description: 'BMP image data',
    mimeType: 'image/bmp',
    targetLabel: 'bmp',
    extensions: {
      'bmp',
    },
    tags: {
      MagikaTag.binary,
      MagikaTag.media,
    },
    groups: {
      MagikaGroup.image,
    },
  ),
  bzip(
    name: 'bzip',
    description: 'bzip2 compressed data',
    mimeType: 'application/x-bzip2',
    targetLabel: 'bzip',
    extensions: {
      'bz2',
      'tbz2',
      'tar.bz2',
    },
    tags: {
      MagikaTag.binary,
      MagikaTag.archive,
    },
    groups: {
      MagikaGroup.archive,
    },
  ),
  c(
    name: 'c',
    description: 'C source',
    mimeType: 'text/x-c',
    targetLabel: 'c',
    extensions: {
      'c',
      'cpp',
      'h',
      'hpp',
      'cc',
    },
    tags: {
      MagikaTag.text,
      MagikaTag.dlTarget,
    },
    groups: {
      MagikaGroup.code,
    },
  ),
  cab(
    name: 'cab',
    description: 'Microsoft Cabinet archive data',
    mimeType: 'application/vnd.ms-cab-compressed',
    targetLabel: 'cab',
    extensions: {
      'cab',
    },
    tags: {
      MagikaTag.binary,
    },
    groups: {
      MagikaGroup.archive,
    },
  ),
  cat(
    name: 'cat',
    description: 'Windows Catalog file',
    mimeType: 'application/octet-stream',
    targetLabel: 'cat',
    extensions: {
      'cat',
    },
    tags: {
      MagikaTag.binary,
    },
    groups: {
      MagikaGroup.application,
    },
  ),
  chm(
    name: 'chm',
    description: 'MS Windows HtmlHelp Data',
    mimeType: 'application/chm',
    targetLabel: 'chm',
    extensions: {
      'chm',
    },
    tags: {
      MagikaTag.binary,
    },
    groups: {
      MagikaGroup.application,
    },
  ),
  coff(
    name: 'coff',
    description: 'Intel 80386 COFF',
    mimeType: 'application/x-coff',
    targetLabel: 'coff',
    extensions: {},
    tags: {
      MagikaTag.binary,
    },
    groups: {
      MagikaGroup.executable,
    },
  ),
  crx(
    name: 'crx',
    description: 'Google Chrome extension',
    mimeType: 'application/x-chrome-extension',
    targetLabel: 'crx',
    extensions: {
      'crx',
    },
    tags: {
      MagikaTag.binary,
      MagikaTag.zipArchive,
      MagikaTag.archive,
    },
    groups: {
      MagikaGroup.executable,
    },
  ),
  cs(
    name: 'cs',
    description: 'C# source',
    mimeType: 'text/plain',
    targetLabel: 'cs',
    extensions: {
      'cs',
    },
    tags: {
      MagikaTag.text,
      MagikaTag.dlTarget,
    },
    groups: {
      MagikaGroup.code,
    },
  ),
  css(
    name: 'css',
    description: 'CSS source',
    mimeType: 'text/css',
    targetLabel: 'css',
    extensions: {
      'css',
    },
    tags: {
      MagikaTag.text,
      MagikaTag.dlTarget,
    },
    groups: {
      MagikaGroup.code,
    },
  ),
  csv(
    name: 'csv',
    description: 'CSV document',
    mimeType: 'text/csv',
    targetLabel: 'csv',
    extensions: {
      'csv',
    },
    tags: {
      MagikaTag.text,
      MagikaTag.dlTarget,
    },
    groups: {
      MagikaGroup.code,
    },
  ),
  deb(
    name: 'deb',
    description: 'Debian binary package',
    mimeType: 'application/vnd.debian.binary-package',
    targetLabel: 'deb',
    extensions: {
      'deb',
    },
    tags: {
      MagikaTag.binary,
      MagikaTag.archive,
    },
    groups: {
      MagikaGroup.archive,
    },
  ),
  dex(
    name: 'dex',
    description: 'Dalvik dex file',
    mimeType: 'application/x-android-dex',
    targetLabel: 'dex',
    extensions: {
      'dex',
    },
    tags: {
      MagikaTag.binary,
    },
    groups: {
      MagikaGroup.executable,
    },
  ),
  dmg(
    name: 'dmg',
    description: 'Apple disk image',
    mimeType: 'application/x-apple-diskimage',
    targetLabel: 'dmg',
    extensions: {
      'dmg',
    },
    tags: {
      MagikaTag.binary,
    },
    groups: {
      MagikaGroup.archive,
    },
  ),
  doc(
    name: 'doc',
    description: 'Microsoft Word CDF document',
    mimeType: 'application/msword',
    targetLabel: 'doc',
    extensions: {
      'doc',
    },
    tags: {
      MagikaTag.binary,
      MagikaTag.cdf,
    },
    groups: {
      MagikaGroup.document,
    },
  ),
  docx(
    name: 'docx',
    description: 'Microsoft Word 2007+ document',
    mimeType:
        'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
    targetLabel: 'docx',
    extensions: {
      'docx',
      'docm',
    },
    tags: {
      MagikaTag.binary,
      MagikaTag.ooxml,
      MagikaTag.zipArchive,
      MagikaTag.archive,
    },
    groups: {
      MagikaGroup.document,
    },
  ),
  elf(
    name: 'elf',
    description: 'ELF executable',
    mimeType: 'application/x-executable-elf',
    targetLabel: 'elf',
    extensions: {
      'elf',
      'so',
    },
    tags: {
      MagikaTag.binary,
      MagikaTag.elf,
    },
    groups: {
      MagikaGroup.executable,
    },
  ),
  emf(
    name: 'emf',
    description: 'Windows Enhanced Metafile image data',
    mimeType: 'application/octet-stream',
    targetLabel: 'emf',
    extensions: {
      'emf',
    },
    tags: {
      MagikaTag.binary,
    },
    groups: {
      MagikaGroup.application,
    },
  ),
  eml(
    name: 'eml',
    description: 'RFC 822 mail',
    mimeType: 'message/rfc822',
    targetLabel: 'eml',
    extensions: {
      'eml',
    },
    tags: {
      MagikaTag.text,
    },
    groups: {
      MagikaGroup.text,
    },
  ),
  epub(
    name: 'epub',
    description: 'EPUB document',
    mimeType: 'application/epub+zip',
    targetLabel: 'epub',
    extensions: {
      'epub',
    },
    tags: {
      MagikaTag.binary,
      MagikaTag.zipArchive,
      MagikaTag.archive,
    },
    groups: {
      MagikaGroup.document,
    },
  ),
  flac(
    name: 'flac',
    description: 'FLAC audio bitstream data',
    mimeType: 'audio/flac',
    targetLabel: 'flac',
    extensions: {
      'flac',
    },
    tags: {
      MagikaTag.binary,
    },
    groups: {
      MagikaGroup.audio,
    },
  ),
  gif(
    name: 'gif',
    description: 'GIF image data',
    mimeType: 'image/gif',
    targetLabel: 'gif',
    extensions: {
      'gif',
    },
    tags: {
      MagikaTag.binary,
      MagikaTag.media,
    },
    groups: {
      MagikaGroup.image,
    },
  ),
  go(
    name: 'go',
    description: 'Golang source',
    mimeType: 'text/x-golang',
    targetLabel: 'go',
    extensions: {
      'go',
    },
    tags: {
      MagikaTag.text,
      MagikaTag.dlTarget,
    },
    groups: {
      MagikaGroup.code,
    },
  ),
  gzip(
    name: 'gzip',
    description: 'gzip compressed data',
    mimeType: 'application/gzip',
    targetLabel: 'gzip',
    extensions: {
      'gz',
      'gzip',
      'tgz',
      'tar.gz',
    },
    tags: {
      MagikaTag.binary,
      MagikaTag.archive,
    },
    groups: {
      MagikaGroup.archive,
    },
  ),
  hlp(
    name: 'hlp',
    description: 'MS Windows help',
    mimeType: 'application/winhlp',
    targetLabel: 'hlp',
    extensions: {
      'hlp',
    },
    tags: {
      MagikaTag.binary,
    },
    groups: {
      MagikaGroup.application,
    },
  ),
  html(
    name: 'html',
    description: 'HTML document',
    mimeType: 'text/html',
    targetLabel: 'html',
    extensions: {
      'html',
      'htm',
      'xhtml',
      'xht',
    },
    tags: {
      MagikaTag.text,
      MagikaTag.dlTarget,
    },
    groups: {
      MagikaGroup.code,
    },
  ),
  ico(
    name: 'ico',
    description: 'MS Windows icon resource',
    mimeType: 'image/vnd.microsoft.icon',
    targetLabel: 'ico',
    extensions: {
      'ico',
    },
    tags: {
      MagikaTag.binary,
    },
    groups: {
      MagikaGroup.image,
    },
  ),
  ini(
    name: 'ini',
    description: 'INI configuration file',
    mimeType: 'text/plain',
    targetLabel: 'ini',
    extensions: {
      'ini',
    },
    tags: {
      MagikaTag.text,
      MagikaTag.dlTarget,
    },
    groups: {
      MagikaGroup.text,
    },
  ),
  internetshortcut(
    name: 'internetshortcut',
    description: 'MS Windows Internet shortcut',
    mimeType: 'application/x-mswinurl',
    targetLabel: 'internetshortcut',
    extensions: {
      'url',
    },
    tags: {
      MagikaTag.text,
    },
    groups: {
      MagikaGroup.application,
    },
  ),
  iso(
    name: 'iso',
    description: 'ISO 9660 CD-ROM filesystem data',
    mimeType: 'application/x-iso9660-image',
    targetLabel: 'iso',
    extensions: {
      'iso',
    },
    tags: {
      MagikaTag.binary,
    },
    groups: {
      MagikaGroup.archive,
    },
  ),
  jar(
    name: 'jar',
    description: 'Java archive data (JAR)',
    mimeType: 'application/java-archive',
    targetLabel: 'jar',
    extensions: {
      'jar',
    },
    tags: {
      MagikaTag.binary,
      MagikaTag.zipArchive,
      MagikaTag.archive,
    },
    groups: {
      MagikaGroup.archive,
    },
  ),
  java(
    name: 'java',
    description: 'Java source',
    mimeType: 'text/x-java',
    targetLabel: 'java',
    extensions: {
      'java',
    },
    tags: {
      MagikaTag.text,
      MagikaTag.dlTarget,
    },
    groups: {
      MagikaGroup.code,
    },
  ),
  javabytecode(
    name: 'javabytecode',
    description: 'Java compiled bytecode',
    mimeType: 'application/x-java-applet',
    targetLabel: 'javabytecode',
    extensions: {
      'class',
    },
    tags: {
      MagikaTag.binary,
    },
    groups: {
      MagikaGroup.executable,
    },
  ),
  javascript(
    name: 'javascript',
    description: 'JavaScript source',
    mimeType: 'application/javascript',
    targetLabel: 'javascript',
    extensions: {
      'js',
    },
    tags: {
      MagikaTag.text,
      MagikaTag.dlTarget,
    },
    groups: {
      MagikaGroup.code,
    },
  ),
  jpeg(
    name: 'jpeg',
    description: 'JPEG image data',
    mimeType: 'image/jpeg',
    targetLabel: 'jpeg',
    extensions: {
      'jpg',
      'jpeg',
    },
    tags: {
      MagikaTag.binary,
      MagikaTag.media,
    },
    groups: {
      MagikaGroup.image,
    },
  ),
  json(
    name: 'json',
    description: 'JSON document',
    mimeType: 'application/json',
    targetLabel: 'json',
    extensions: {
      'json',
    },
    tags: {
      MagikaTag.text,
      MagikaTag.dlTarget,
    },
    groups: {
      MagikaGroup.code,
    },
  ),
  latex(
    name: 'latex',
    description: 'LaTeX document',
    mimeType: 'text/x-tex',
    targetLabel: 'latex',
    extensions: {
      'tex',
    },
    tags: {
      MagikaTag.text,
      MagikaTag.dlTarget,
    },
    groups: {
      MagikaGroup.text,
    },
  ),
  lisp(
    name: 'lisp',
    description: 'Lisp source',
    mimeType: 'text/x-lisp',
    targetLabel: 'lisp',
    extensions: {
      'lisp',
    },
    tags: {
      MagikaTag.text,
      MagikaTag.dlTarget,
    },
    groups: {
      MagikaGroup.code,
    },
  ),
  lnk(
    name: 'lnk',
    description: 'MS Windows shortcut',
    mimeType: 'application/x-ms-shortcut',
    targetLabel: 'lnk',
    extensions: {
      'lnk',
    },
    tags: {
      MagikaTag.binary,
    },
    groups: {
      MagikaGroup.application,
    },
  ),
  m3u(
    name: 'm3u',
    description: 'M3U playlist',
    mimeType: 'text/plain',
    targetLabel: 'm3u',
    extensions: {
      'm3u8',
      'm3u',
    },
    tags: {
      MagikaTag.binary,
    },
    groups: {
      MagikaGroup.application,
    },
  ),
  macho(
    name: 'macho',
    description: 'Mach-O executable',
    mimeType: 'application/x-mach-o',
    targetLabel: 'macho',
    extensions: {},
    tags: {
      MagikaTag.binary,
      MagikaTag.macho,
    },
    groups: {
      MagikaGroup.executable,
    },
  ),
  makefile(
    name: 'makefile',
    description: 'Makefile source',
    mimeType: 'text/x-makefile',
    targetLabel: 'makefile',
    extensions: {
      '=Makefile',
    },
    tags: {
      MagikaTag.text,
      MagikaTag.dlTarget,
    },
    groups: {
      MagikaGroup.code,
    },
  ),
  markdown(
    name: 'markdown',
    description: 'Markdown document',
    mimeType: 'text/markdown',
    targetLabel: 'markdown',
    extensions: {
      'md',
    },
    tags: {
      MagikaTag.text,
      MagikaTag.dlTarget,
    },
    groups: {
      MagikaGroup.text,
    },
  ),
  mht(
    name: 'mht',
    description: 'MHTML document',
    mimeType: 'application/x-mimearchive',
    targetLabel: 'mht',
    extensions: {
      'mht',
    },
    tags: {
      MagikaTag.text,
    },
    groups: {
      MagikaGroup.code,
    },
  ),
  mp3(
    name: 'mp3',
    description: 'MP3 media file',
    mimeType: 'audio/mpeg',
    targetLabel: 'mp3',
    extensions: {
      'mp3',
    },
    tags: {
      MagikaTag.binary,
      MagikaTag.media,
    },
    groups: {
      MagikaGroup.audio,
    },
  ),
  mp4(
    name: 'mp4',
    description: 'MP4 media file',
    mimeType: 'video/mp4',
    targetLabel: 'mp4',
    extensions: {
      'mov',
      'mp4',
    },
    tags: {
      MagikaTag.binary,
      MagikaTag.media,
    },
    groups: {
      MagikaGroup.video,
    },
  ),
  mscompress(
    name: 'mscompress',
    description: 'MS Compress archive data',
    mimeType: 'application/x-ms-compress-szdd',
    targetLabel: 'mscompress',
    extensions: {},
    tags: {
      MagikaTag.binary,
    },
    groups: {
      MagikaGroup.archive,
    },
  ),
  msi(
    name: 'msi',
    description: 'Microsoft Installer file',
    mimeType: 'application/x-msi',
    targetLabel: 'msi',
    extensions: {
      'msi',
    },
    tags: {
      MagikaTag.binary,
      MagikaTag.cdf,
    },
    groups: {
      MagikaGroup.archive,
    },
  ),
  mum(
    name: 'mum',
    description: 'Windows Update Package file',
    mimeType: 'text/xml',
    targetLabel: 'mum',
    extensions: {
      'mum',
    },
    tags: {
      MagikaTag.text,
    },
    groups: {
      MagikaGroup.application,
    },
  ),
  odex(
    name: 'odex',
    description: 'ODEX ELF executable',
    mimeType: 'application/x-executable-elf',
    targetLabel: 'odex',
    extensions: {
      'odex',
    },
    tags: {
      MagikaTag.binary,
      MagikaTag.elf,
    },
    groups: {
      MagikaGroup.executable,
    },
  ),
  odp(
    name: 'odp',
    description: 'OpenDocument Presentation',
    mimeType: 'application/vnd.oasis.opendocument.presentation',
    targetLabel: 'odp',
    extensions: {
      'odp',
    },
    tags: {
      MagikaTag.binary,
      MagikaTag.zipArchive,
    },
    groups: {
      MagikaGroup.document,
    },
  ),
  ods(
    name: 'ods',
    description: 'OpenDocument Spreadsheet',
    mimeType: 'application/vnd.oasis.opendocument.spreadsheet',
    targetLabel: 'ods',
    extensions: {
      'ods',
    },
    tags: {
      MagikaTag.binary,
      MagikaTag.zipArchive,
    },
    groups: {
      MagikaGroup.document,
    },
  ),
  odt(
    name: 'odt',
    description: 'OpenDocument Text',
    mimeType: 'application/vnd.oasis.opendocument.text',
    targetLabel: 'odt',
    extensions: {
      'odt',
    },
    tags: {
      MagikaTag.binary,
      MagikaTag.zipArchive,
    },
    groups: {
      MagikaGroup.document,
    },
  ),
  ogg(
    name: 'ogg',
    description: 'Ogg data',
    mimeType: 'audio/ogg',
    targetLabel: 'ogg',
    extensions: {
      'ogg',
    },
    tags: {
      MagikaTag.binary,
      MagikaTag.media,
    },
    groups: {
      MagikaGroup.audio,
    },
  ),
  outlook(
    name: 'outlook',
    description: 'MS Outlook Message',
    mimeType: 'application/vnd.ms-outlook',
    targetLabel: 'outlook',
    extensions: {},
    tags: {
      MagikaTag.binary,
      MagikaTag.cdf,
    },
    groups: {
      MagikaGroup.application,
    },
  ),
  pcap(
    name: 'pcap',
    description: 'pcap capture file',
    mimeType: 'application/vnd.tcpdump.pcap',
    targetLabel: 'pcap',
    extensions: {
      'pcap',
      'pcapng',
    },
    tags: {
      MagikaTag.binary,
    },
    groups: {
      MagikaGroup.application,
    },
  ),
  pdf(
    name: 'pdf',
    description: 'PDF document',
    mimeType: 'application/pdf',
    targetLabel: 'pdf',
    extensions: {
      'pdf',
    },
    tags: {
      MagikaTag.binary,
    },
    groups: {
      MagikaGroup.document,
    },
  ),
  pebin(
    name: 'pebin',
    description: 'PE executable',
    mimeType: 'application/x-dosexec',
    targetLabel: 'pebin',
    extensions: {
      'exe',
      'dll',
      'sys',
    },
    tags: {},
    groups: {
      MagikaGroup.executable,
    },
  ),
  pem(
    name: 'pem',
    description: 'PEM certificate',
    mimeType: 'application/x-pem-file',
    targetLabel: 'pem',
    extensions: {
      'pem',
      'pub',
    },
    tags: {
      MagikaTag.text,
    },
    groups: {
      MagikaGroup.application,
    },
  ),
  perl(
    name: 'perl',
    description: 'Perl source',
    mimeType: 'text/x-perl',
    targetLabel: 'perl',
    extensions: {
      'pl',
    },
    tags: {
      MagikaTag.text,
      MagikaTag.dlTarget,
    },
    groups: {
      MagikaGroup.code,
    },
  ),
  php(
    name: 'php',
    description: 'PHP source',
    mimeType: 'text/x-php',
    targetLabel: 'php',
    extensions: {
      'php',
    },
    tags: {
      MagikaTag.text,
      MagikaTag.dlTarget,
    },
    groups: {
      MagikaGroup.code,
    },
  ),
  png(
    name: 'png',
    description: 'PNG image data',
    mimeType: 'image/png',
    targetLabel: 'png',
    extensions: {
      'png',
    },
    tags: {
      MagikaTag.binary,
      MagikaTag.media,
    },
    groups: {
      MagikaGroup.image,
    },
  ),
  postscript(
    name: 'postscript',
    description: 'PostScript document',
    mimeType: 'application/postscript',
    targetLabel: 'postscript',
    extensions: {
      'ps',
    },
    tags: {
      MagikaTag.binary,
    },
    groups: {
      MagikaGroup.document,
    },
  ),
  powershell(
    name: 'powershell',
    description: 'Powershell source',
    mimeType: 'application/x-powershell',
    targetLabel: 'powershell',
    extensions: {
      'ps1',
    },
    tags: {
      MagikaTag.text,
      MagikaTag.dlTarget,
    },
    groups: {
      MagikaGroup.code,
    },
  ),
  ppt(
    name: 'ppt',
    description: 'Microsoft PowerPoint CDF document',
    mimeType: 'application/vnd.ms-powerpoint',
    targetLabel: 'ppt',
    extensions: {
      'ppt',
    },
    tags: {
      MagikaTag.binary,
      MagikaTag.cdf,
    },
    groups: {
      MagikaGroup.document,
    },
  ),
  pptx(
    name: 'pptx',
    description: 'Microsoft PowerPoint 2007+ document',
    mimeType:
        'application/vnd.openxmlformats-officedocument.presentationml.presentation',
    targetLabel: 'pptx',
    extensions: {
      'pptx',
      'pptm',
    },
    tags: {
      MagikaTag.binary,
      MagikaTag.ooxml,
      MagikaTag.zipArchive,
      MagikaTag.archive,
    },
    groups: {
      MagikaGroup.document,
    },
  ),
  python(
    name: 'python',
    description: 'Python source',
    mimeType: 'text/x-python',
    targetLabel: 'python',
    extensions: {
      'py',
    },
    tags: {
      MagikaTag.text,
      MagikaTag.dlTarget,
    },
    groups: {
      MagikaGroup.code,
    },
  ),
  pythonbytecode(
    name: 'pythonbytecode',
    description: 'Python compiled bytecode',
    mimeType: 'application/x-bytecode.python',
    targetLabel: 'pythonbytecode',
    extensions: {
      'pyc',
      'pyo',
    },
    tags: {
      MagikaTag.binary,
    },
    groups: {
      MagikaGroup.executable,
    },
  ),
  rar(
    name: 'rar',
    description: 'RAR archive data',
    mimeType: 'application/x-rar',
    targetLabel: 'rar',
    extensions: {
      'rar',
    },
    tags: {
      MagikaTag.binary,
      MagikaTag.archive,
    },
    groups: {
      MagikaGroup.archive,
    },
  ),
  rdf(
    name: 'rdf',
    description: 'Resource Description Framework document (RDF)',
    mimeType: 'application/rdf+xml',
    targetLabel: 'rdf',
    extensions: {
      'rdf',
    },
    tags: {
      MagikaTag.text,
    },
    groups: {
      MagikaGroup.text,
    },
  ),
  rpm(
    name: 'rpm',
    description: 'RedHat Package Manager archive (RPM)',
    mimeType: 'application/x-rpm',
    targetLabel: 'rpm',
    extensions: {
      'rpm',
    },
    tags: {
      MagikaTag.binary,
      MagikaTag.archive,
    },
    groups: {
      MagikaGroup.archive,
    },
  ),
  rst(
    name: 'rst',
    description: 'ReStructuredText document',
    mimeType: 'text/x-rst',
    targetLabel: 'rst',
    extensions: {
      'rst',
    },
    tags: {
      MagikaTag.text,
      MagikaTag.dlTarget,
    },
    groups: {
      MagikaGroup.text,
    },
  ),
  rtf(
    name: 'rtf',
    description: 'Rich Text Format document',
    mimeType: 'text/rtf',
    targetLabel: 'rtf',
    extensions: {
      'rtf',
    },
    tags: {
      MagikaTag.text,
    },
    groups: {
      MagikaGroup.text,
    },
  ),
  ruby(
    name: 'ruby',
    description: 'Ruby source',
    mimeType: 'application/x-ruby',
    targetLabel: 'ruby',
    extensions: {
      'rb',
    },
    tags: {
      MagikaTag.text,
      MagikaTag.dlTarget,
    },
    groups: {
      MagikaGroup.code,
    },
  ),
  rust(
    name: 'rust',
    description: 'Rust source',
    mimeType: 'application/x-rust',
    targetLabel: 'rust',
    extensions: {
      'rs',
    },
    tags: {
      MagikaTag.text,
      MagikaTag.dlTarget,
    },
    groups: {
      MagikaGroup.code,
    },
  ),
  scala(
    name: 'scala',
    description: 'Scala source',
    mimeType: 'application/x-scala',
    targetLabel: 'scala',
    extensions: {
      'scala',
    },
    tags: {
      MagikaTag.text,
      MagikaTag.dlTarget,
    },
    groups: {
      MagikaGroup.code,
    },
  ),
  sevenzip(
    name: 'sevenzip',
    description: '7-zip archive data',
    mimeType: 'application/x-7z-compressed',
    targetLabel: 'sevenzip',
    extensions: {
      '7z',
    },
    tags: {
      MagikaTag.binary,
      MagikaTag.archive,
    },
    groups: {
      MagikaGroup.archive,
    },
  ),
  shell(
    name: 'shell',
    description: 'Shell script',
    mimeType: 'text/x-shellscript',
    targetLabel: 'shell',
    extensions: {
      'sh',
    },
    tags: {
      MagikaTag.text,
      MagikaTag.dlTarget,
    },
    groups: {
      MagikaGroup.code,
    },
  ),
  smali(
    name: 'smali',
    description: 'Smali source',
    mimeType: 'application/x-smali',
    targetLabel: 'smali',
    extensions: {
      'smali',
    },
    tags: {
      MagikaTag.text,
    },
    groups: {
      MagikaGroup.code,
    },
  ),
  sql(
    name: 'sql',
    description: 'SQL source',
    mimeType: 'application/x-sql',
    targetLabel: 'sql',
    extensions: {
      'sql',
    },
    tags: {
      MagikaTag.text,
      MagikaTag.dlTarget,
    },
    groups: {
      MagikaGroup.code,
    },
  ),
  squashfs(
    name: 'squashfs',
    description: 'Squash filesystem',
    mimeType: 'application/octet-stream',
    targetLabel: 'squashfs',
    extensions: {},
    tags: {
      MagikaTag.binary,
    },
    groups: {
      MagikaGroup.archive,
    },
  ),
  svg(
    name: 'svg',
    description: 'SVG Scalable Vector Graphics image data',
    mimeType: 'image/svg+xml',
    targetLabel: 'svg',
    extensions: {
      'svg',
    },
    tags: {
      MagikaTag.text,
    },
    groups: {
      MagikaGroup.image,
    },
  ),
  swf(
    name: 'swf',
    description: 'Macromedia Flash data',
    mimeType: 'application/x-shockwave-flash',
    targetLabel: 'swf',
    extensions: {
      'swf',
    },
    tags: {
      MagikaTag.binary,
    },
    groups: {
      MagikaGroup.executable,
    },
  ),
  symlinktext(
    name: 'symlinktext',
    description: 'Symbolic link (textual representation)',
    mimeType: 'text/plain',
    targetLabel: 'symlinktext',
    extensions: {},
    tags: {
      MagikaTag.text,
    },
    groups: {
      MagikaGroup.application,
    },
  ),
  tar(
    name: 'tar',
    description: 'POSIX tar archive',
    mimeType: 'application/x-tar',
    targetLabel: 'tar',
    extensions: {
      'tar',
    },
    tags: {
      MagikaTag.binary,
      MagikaTag.archive,
    },
    groups: {
      MagikaGroup.archive,
    },
  ),
  tga(
    name: 'tga',
    description: 'Targa image data',
    mimeType: 'image/x-tga',
    targetLabel: 'tga',
    extensions: {
      'tga',
    },
    tags: {
      MagikaTag.binary,
    },
    groups: {
      MagikaGroup.image,
    },
  ),
  tiff(
    name: 'tiff',
    description: 'TIFF image data',
    mimeType: 'image/tiff',
    targetLabel: 'tiff',
    extensions: {
      'tiff',
      'tif',
    },
    tags: {
      MagikaTag.binary,
      MagikaTag.media,
    },
    groups: {
      MagikaGroup.image,
    },
  ),
  torrent(
    name: 'torrent',
    description: 'BitTorrent file',
    mimeType: 'application/x-bittorrent',
    targetLabel: 'torrent',
    extensions: {
      'torrent',
    },
    tags: {
      MagikaTag.binary,
    },
    groups: {
      MagikaGroup.application,
    },
  ),
  ttf(
    name: 'ttf',
    description: 'TrueType Font data',
    mimeType: 'font/sfnt',
    targetLabel: 'ttf',
    extensions: {
      'ttf',
    },
    tags: {
      MagikaTag.binary,
    },
    groups: {
      MagikaGroup.font,
    },
  ),
  txt(
    name: 'txt',
    description: 'Generic text document',
    mimeType: 'text/plain',
    targetLabel: 'txt',
    extensions: {
      'txt',
    },
    tags: {
      MagikaTag.text,
      MagikaTag.dlTarget,
    },
    groups: {
      MagikaGroup.text,
    },
  ),
  unknown(
    name: 'unknown',
    description: 'Unknown binary data',
    mimeType: 'application/octet-stream',
    targetLabel: 'unknown',
    extensions: {},
    tags: {
      MagikaTag.binary,
    },
    groups: {
      MagikaGroup.unknown,
    },
  ),
  vba(
    name: 'vba',
    description: 'MS Visual Basic source (VBA)',
    mimeType: 'text/vbscript',
    targetLabel: 'vba',
    extensions: {
      'vbs',
    },
    tags: {
      MagikaTag.text,
    },
    groups: {
      MagikaGroup.code,
    },
  ),
  wav(
    name: 'wav',
    description: 'Waveform Audio file (WAV)',
    mimeType: 'audio/x-wav',
    targetLabel: 'wav',
    extensions: {
      'wav',
    },
    tags: {
      MagikaTag.binary,
      MagikaTag.media,
    },
    groups: {
      MagikaGroup.audio,
    },
  ),
  webm(
    name: 'webm',
    description: 'WebM data',
    mimeType: 'video/webm',
    targetLabel: 'webm',
    extensions: {
      'webm',
    },
    tags: {
      MagikaTag.binary,
      MagikaTag.media,
    },
    groups: {
      MagikaGroup.video,
    },
  ),
  webp(
    name: 'webp',
    description: 'WebP data',
    mimeType: 'image/webp',
    targetLabel: 'webp',
    extensions: {
      'webp',
    },
    tags: {
      MagikaTag.binary,
      MagikaTag.media,
    },
    groups: {
      MagikaGroup.image,
    },
  ),
  winregistry(
    name: 'winregistry',
    description: 'Windows Registry text',
    mimeType: 'text/x-ms-regedit',
    targetLabel: 'winregistry',
    extensions: {
      'reg',
    },
    tags: {
      MagikaTag.text,
      MagikaTag.dlTarget,
    },
    groups: {
      MagikaGroup.application,
    },
  ),
  wmf(
    name: 'wmf',
    description: 'Windows metafile',
    mimeType: 'image/wmf',
    targetLabel: 'wmf',
    extensions: {
      'wmf',
    },
    tags: {
      MagikaTag.binary,
    },
    groups: {
      MagikaGroup.image,
    },
  ),
  xar(
    name: 'xar',
    description: 'XAR archive compressed data',
    mimeType: 'application/x-xar',
    targetLabel: 'xar',
    extensions: {
      'pkg',
      'xar',
    },
    tags: {
      MagikaTag.binary,
      MagikaTag.archive,
    },
    groups: {
      MagikaGroup.archive,
    },
  ),
  xls(
    name: 'xls',
    description: 'Microsoft Excel CDF document',
    mimeType: 'application/vnd.ms-excel',
    targetLabel: 'xls',
    extensions: {
      'xls',
    },
    tags: {
      MagikaTag.binary,
      MagikaTag.cdf,
    },
    groups: {
      MagikaGroup.document,
    },
  ),
  xlsb(
    name: 'xlsb',
    description: 'Microsoft Excel 2007+ document (binary format)',
    mimeType:
        'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
    targetLabel: 'xlsb',
    extensions: {
      'xlsb',
    },
    tags: {
      MagikaTag.binary,
      MagikaTag.ooxml,
      MagikaTag.zipArchive,
      MagikaTag.archive,
    },
    groups: {
      MagikaGroup.document,
    },
  ),
  xlsx(
    name: 'xlsx',
    description: 'Microsoft Excel 2007+ document',
    mimeType:
        'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
    targetLabel: 'xlsx',
    extensions: {
      'xlsx',
      'xlsm',
    },
    tags: {
      MagikaTag.binary,
      MagikaTag.ooxml,
      MagikaTag.zipArchive,
      MagikaTag.archive,
    },
    groups: {
      MagikaGroup.document,
    },
  ),
  xml(
    name: 'xml',
    description: 'XML document',
    mimeType: 'text/xml',
    targetLabel: 'xml',
    extensions: {
      'xml',
    },
    tags: {
      MagikaTag.text,
      MagikaTag.dlTarget,
    },
    groups: {
      MagikaGroup.code,
    },
  ),
  xpi(
    name: 'xpi',
    description: 'Compressed installation archive (XPI)',
    mimeType: 'application/zip',
    targetLabel: 'xpi',
    extensions: {
      'xpi',
    },
    tags: {
      MagikaTag.binary,
      MagikaTag.zipArchive,
      MagikaTag.archive,
    },
    groups: {
      MagikaGroup.archive,
    },
  ),
  xz(
    name: 'xz',
    description: 'XZ compressed data',
    mimeType: 'application/x-xz',
    targetLabel: 'xz',
    extensions: {
      'xz',
    },
    tags: {
      MagikaTag.binary,
      MagikaTag.archive,
    },
    groups: {
      MagikaGroup.archive,
    },
  ),
  yaml(
    name: 'yaml',
    description: 'YAML source',
    mimeType: 'application/x-yaml',
    targetLabel: 'yaml',
    extensions: {
      'yml',
      'yaml',
    },
    tags: {
      MagikaTag.text,
      MagikaTag.dlTarget,
    },
    groups: {
      MagikaGroup.code,
    },
  ),
  zip(
    name: 'zip',
    description: 'Zip archive data',
    mimeType: 'application/zip',
    targetLabel: 'zip',
    extensions: {
      'zip',
    },
    tags: {
      MagikaTag.binary,
      MagikaTag.zipArchive,
      MagikaTag.archive,
    },
    groups: {
      MagikaGroup.archive,
    },
  ),
  zlibstream(
    name: 'zlibstream',
    description: 'zlib compressed data',
    mimeType: 'application/zlib',
    targetLabel: 'zlibstream',
    extensions: {},
    tags: {
      MagikaTag.binary,
    },
    groups: {
      MagikaGroup.application,
    },
  );

  const MagikaType({
    required this.name,
    required this.description,
    required this.mimeType,
    required this.targetLabel,
    required this.extensions,
    required this.tags,
    required this.groups,
  });

  final String name;
  final String description;
  final String mimeType;
  final String targetLabel;
  final Set<String> extensions;
  final Set<MagikaTag> tags;
  final Set<MagikaGroup> groups;
}
