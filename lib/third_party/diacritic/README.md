Added due to repeated flakes on CI of the form of [^1].

This does not seem to be a problem with the package itself, but rather with the way it is being resolved in the CI environment. This has happened consistently in a dependant app, and for now, stabilizing the CI is more important than root-causing this issue.

# TODO
- AI autocompleted this during editing this README, is it actually true? "The package is being resolved from the `.pub-cache` directory, which is not the usual way of resolving packages in a Flutter project. This is likely causing the package to not be found, leading to the error."

[^1]:
[        ] [   +5 ms] /Users/builder/programs/flutter_3_24_4/bin/cache/dart-sdk/bin/dartaotruntime --disable-dart-dev /Users/builder/programs/flutter_3_24_4/bin/cache/dart-sdk/bin/snapshots/frontend_server_aot.dart.snapshot --sdk-root /Users/builder/programs/flutter_3_24_4/bin/cache/artifacts/engine/common/flutter_patched_sdk_product/ --target=flutter --no-print-incremental-dependencies -Ddart.vm.profile=false -Ddart.vm.product=true --delete-tostring-package-uri=dart:ui --delete-tostring-package-uri=package:flutter --aot --tfa --target-os macos --packages /Users/builder/clone/.dart_tool/package_config.json --output-dill /Users/builder/clone/.dart_tool/flutter_build/b9fd6c26af7e7f0299362d6414300ee1/program.dill --depfile /Users/builder/clone/.dart_tool/flutter_build/b9fd6c26af7e7f0299362d6414300ee1/kernel_snapshot_program.d --source file:///Users/builder/clone/.dart_tool/flutter_build/dart_plugin_registrant.dart --source package:flutter/src/dart_plugin_registrant.dart -Dflutter.dart_plugin_registrant=file:///Users/builder/clone/.dart_tool/flutter_build/dart_plugin_registrant.dart --verbosity=error package:telosnex/main.dart
[        ] [+1895 ms] Error: Couldn't resolve the package 'diacritic' in 'package:diacritic/diacritic.dart'.
[        ] [ +385 ms] ../.pub-cache/git/fonnx-3aa01bb3d523d9d32f23b6f419159f080e89f67e/lib/tokenizers/wordpiece_tokenizer.dart:1:8: Error: Not found: 'package:diacritic/diacritic.dart'
[        ] [        ] import 'package:diacritic/diacritic.dart';
[        ] [        ]        ^
[        ] [+6984 ms] ../.pub-cache/git/fonnx-3aa01bb3d523d9d32f23b6f419159f080e89f67e/lib/tokenizers/wordpiece_tokenizer.dart:113:24: Error: The method 'removeDiacritics' isn't defined for the class 'WordpieceTokenizer'.
[        ] [        ]  - 'WordpieceTokenizer' is from 'package:fonnx/tokenizers/wordpiece_tokenizer.dart' ('../.pub-cache/git/fonnx-3aa01bb3d523d9d32f23b6f419159f080e89f67e/lib/tokenizers/wordpiece_tokenizer.dart').
[        ] [        ] Try correcting the name to the name of an existing method, or defining a method named 'removeDiacritics'.
[        ] [        ]       normalizedWord = removeDiacritics(word.toLowerCase());