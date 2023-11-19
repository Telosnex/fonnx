import 'dart:io';
import 'dart:typed_data';

Future<bool> LoadPhData(int srate) async {
  int ix;
  int version;
  int length = 0;
  int rate;
  String p;

  bool status;
  final pathHome = '';
  // TODO: Actually load
  final phonemeTabData = await readPhFile(pathHome, 'phontab');
  final phonemeIndex = await readPhFile(pathHome, 'phonindex');
  final phondata = await readPhFile(pathHome, 'phondata');
  final tunes = await readPhFile(pathHome, 'intonations');
  return true;
  final wavefileData = phondata;
  // final n_tunes = length / sizeof(TUNE);

  // read the version number and sample rate from the first 8 bytes of phondata
  // version = 0; // bytes 0-3, version number
  // rate = 0;    // bytes 4-7, sample rate
  // for (ix = 0; ix < 4; ix++) {
  // 	version += (wavefile_data[ix] << (ix*8));
  // 	rate += (wavefile_data[ix+4] << (ix*8));
  // }

  // if (version != version_phdata)
  // 	return create_version_mismatch_error_context(context, path_home, version, version_phdata);

  // // set up phoneme tables
  // p = phoneme_tab_data;
  // n_phoneme_tables = p[0];
  // p += 4;

  // for (ix = 0; ix < n_phoneme_tables; ix++) {
  // 	int n_phonemes = p[0];
  // 	phoneme_tab_list[ix].n_phonemes = p[0];
  // 	phoneme_tab_list[ix].includes = p[1];
  // 	p += 4;
  // 	memcpy(phoneme_tab_list[ix].name, p, N_PHONEME_TAB_NAME);
  // 	p += N_PHONEME_TAB_NAME;
  // 	phoneme_tab_list[ix].phoneme_tab_ptr = (PHONEME_TAB *)p;
  // 	p += (n_phonemes * sizeof(PHONEME_TAB));
  // }

  // if (phoneme_tab_number >= n_phoneme_tables)
  // 	phoneme_tab_number = 0;

  // if (srate != NULL)
  // 	*srate = rate;
  // return ENS_OK;
}

Future<Uint8List> readPhFile(String pathHome, String filename) async {
  final String filePath = pathHome + filename; // assuming pathHome is defined
  final File file = File(filePath);

  if (!await file.exists()) {
    throw FileSystemException('File does not exist', filePath);
  }

  final contents = await file.readAsBytes();

  return contents;

  // if (!ptr) return EINVAL;

  // FILE *f_in;
  // int length;
  // char buf[sizeof(path_home)+40];

  // sprintf(buf, "%s%c%s", path_home, PATHSEP, fname);
  // length = GetFileLength(buf);
  // if (length < 0) // length == -errno
  // 	return create_file_error_context(context, -length, buf);

  // if ((f_in = fopen(buf, "rb")) == NULL)
  // 	return create_file_error_context(context, errno, buf);

  // if (*ptr != NULL)
  // 	free(*ptr);

  // if ((*ptr = malloc(length)) == NULL) {
  // 	fclose(f_in);
  // 	return ENOMEM;
  // }
  // if (fread(*ptr, 1, length, f_in) != length) {
  // 	int error = errno;
  // 	fclose(f_in);
  // 	free(*ptr);
  // 	return create_file_error_context(context, error, buf);
  // }

  // fclose(f_in);
  // if (size != NULL)
  // 	*size = length;
  // return ENS_OK;
}
