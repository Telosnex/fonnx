// Copyright (c) 2016, Agilord. All rights reserved. Use of this source code
// is governed by a BSD-style license that can be found in the LICENSE file.

import 'package:fonnx/third_party/diacritic/replacement_map.dart';

/// Removes common accents and diacritical signs from a
/// string by replacing them with an equivalent character.

/// Removes accents and diacritics from the given String.
String removeDiacritics(String text) =>
    String.fromCharCodes(replaceCodeUnits(text.codeUnits));