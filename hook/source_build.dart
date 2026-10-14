import 'dart:convert';
import 'dart:ffi';
import 'dart:io';

import 'package:code_assets/code_assets.dart';
import 'package:crypto/crypto.dart';
import 'package:hooks/hooks.dart';
import 'package:native_prebuilt/native_prebuilt.dart';
import 'package:native_prebuilt/src/locks.dart';
import 'package:path/path.dart' as p;

import 'upstream_ort.dart';

/// The hook and CI use this same build: pinned upstream ORT and the
/// package-owned session finalizer. No output goes into the package. The tiny
/// finalizer is also prebuilt for consumer builds.
Future<void> buildFromSource(
  BuildInput input,
  BuildOutputBuilder output,
  SourceBuild source,
  void Function(String) log,
) async {
  final target = TargetName.of(input.config.code);
  final upstream = (await loadUpstreamOrt(input.packageRoot))[target.name];
  if (upstream == null) {
    throw UnsupportedError(
      'No ORT input for $target. Intel Apple targets are not supported.',
    );
  }
  final out = Directory.fromUri(input.outputDirectory);
  await out.create(recursive: true);
  final cache = input.userDefines.path('native_prebuilt_cache');
  final cacheRoot = cache == null
      ? defaultCacheRoot()
      : Directory.fromUri(cache);
  final ort = await fetchVerified(
    upstream.fetchSpec,
    File(p.join(cacheRoot.path, upstream.sha256, upstream.name)),
    archiveCache: cacheRoot,
    log: log,
  );
  await ort.copy(p.join(out.path, upstream.name));
  output.assets.code.add(
    CodeAsset(
      package: input.packageName,
      name: ortAsset,
      linkMode: DynamicLoadingBundled(),
      file: out.uri.resolve(upstream.name),
    ),
  );

  if (!_canBuild(target)) {
    throw UnsupportedError(
      'Cannot build $target on ${Platform.operatingSystem}. '
      'Use the fonnx native release workflow to publish prebuilt files.',
    );
  }
  final targetArguments = _targetArguments(input, target);
  final identity = <String>[
    await _run('cmake', ['--version'], log),
    ...targetArguments,
    for (final name in [
      'CC',
      'CXX',
      'CFLAGS',
      'CXXFLAGS',
      'LDFLAGS',
      'DEVELOPER_DIR',
    ])
      '$name=${Platform.environment[name]}',
  ];
  if (target.os == OS.android) {
    final toolchain = targetArguments.singleWhere(
      (a) => a.startsWith('-DCMAKE_TOOLCHAIN_FILE='),
    );
    final ndk = File(toolchain.split('=').last).parent.parent.parent;
    identity.add(
      await File(p.join(ndk.path, 'source.properties')).readAsString(),
    );
  } else if (Platform.isMacOS) {
    identity.add(await _run('xcrun', ['clang', '--version'], log));
    identity.add(await _run('xcodebuild', ['-version'], log));
  } else if (Platform.isLinux) {
    final compiler = targetArguments
        .where((a) => a.startsWith('-DCMAKE_CXX_COMPILER='))
        .firstOrNull;
    identity.add(
      await _run(
        compiler?.split('=').last ?? Platform.environment['CXX'] ?? 'g++',
        ['--version'],
        log,
      ),
    );
  } else if (Platform.isWindows) {
    final vswhere = p.join(
      Platform.environment['ProgramFiles(x86)']!,
      'Microsoft Visual Studio',
      'Installer',
      'vswhere.exe',
    );
    identity.add(
      await _run(vswhere, [
        '-latest',
        '-products',
        '*',
        '-format',
        'json',
      ], log),
    );
  }
  final toolchainKey = sha256
      .convert(utf8.encode(identity.join('\n')))
      .toString()
      .substring(0, 16);
  final work = Directory.fromUri(
    input.outputDirectoryShared.resolve(
      // Leave room for CMake object paths on Windows.
      's/${source.sourceKey.short}/${target.name}/$toolchainKey/',
    ),
  );
  await withFileLock(File(p.join(work.path, 'build.lock')), () async {
    await work.create(recursive: true);
    final build = Directory(p.join(work.path, 'build'));
    final project = Directory(p.join(work.path, 'finalizer'));
    await project.create(recursive: true);
    String cmakePath(Uri uri) => uri.toFilePath().replaceAll(r'\', '/');
    await File(p.join(project.path, 'CMakeLists.txt')).writeAsString('''
cmake_minimum_required(VERSION 3.15)
project(fonnx_ort_session_finalizer C)
add_library(fonnx_ort_session_finalizer SHARED "${cmakePath(input.packageRoot.resolve('src/ort_session_finalizer.c'))}")
target_include_directories(fonnx_ort_session_finalizer PRIVATE "${cmakePath(input.packageRoot.resolve('src/'))}")
if(CMAKE_SYSTEM_NAME STREQUAL "iOS")
  # This C-only shim needs no ORT APIs. Keep its old iOS 13 minimum so
  # Flutter's framework plist is correct without another packaging fix.
  set_target_properties(fonnx_ort_session_finalizer PROPERTIES
    XCODE_ATTRIBUTE_IPHONEOS_DEPLOYMENT_TARGET "13.0")
endif()
if(WIN32)
  target_link_libraries(fonnx_ort_session_finalizer PRIVATE ole32)
endif()
''');
    final args = <String>[
      '-S',
      project.path,
      '-B',
      build.path,
      '-DCMAKE_BUILD_TYPE=Release',
      ...targetArguments,
    ];
    await _run('cmake', args, log);
    await _run('cmake', [
      '--build',
      build.path,
      '--config',
      'Release',
      '--target',
      'fonnx_ort_session_finalizer',
      '--parallel',
      '8',
    ], log);
    final finalizerName = target.os.dylibFileName(
      'fonnx_ort_session_finalizer',
    );
    final finalizers = await build
        .list(recursive: true, followLinks: false)
        .where((e) => e is File && p.basename(e.path) == finalizerName)
        .cast<File>()
        .toList();
    if (finalizers.length != 1) {
      throw StateError('Expected one finalizer library, got $finalizers');
    }
    final finalizer = await finalizers.single.copy(
      p.join(out.path, finalizerName),
    );
    output.assets.code.add(
      CodeAsset(
        package: input.packageName,
        name: finalizerAsset,
        linkMode: DynamicLoadingBundled(),
        file: finalizer.uri,
      ),
    );
    if (source.release != null && target.os == OS.linux) {
      for (final file in [File(p.join(out.path, upstream.name)), finalizer]) {
        await _checkLinuxBaseline(file, log);
      }
    }
  });
}

bool _canBuild(TargetName target) => switch (target.os) {
  OS.macOS || OS.iOS => Platform.isMacOS,
  OS.android => Platform.isMacOS || Platform.isLinux || Platform.isWindows,
  OS.windows => Platform.isWindows,
  OS.linux => Platform.isLinux,
  _ => false,
};

List<String> _targetArguments(BuildInput input, TargetName target) {
  final code = input.config.code;
  switch (target.os) {
    case OS.macOS:
      return [
        '-DCMAKE_OSX_ARCHITECTURES=arm64',
        '-DCMAKE_OSX_DEPLOYMENT_TARGET=14.0',
      ];
    case OS.iOS:
      return [
        '-G',
        'Xcode',
        '-DCMAKE_SYSTEM_NAME=iOS',
        '-DCMAKE_OSX_SYSROOT=${target.iosSdk == IOSSdk.iPhoneOS ? 'iphoneos' : 'iphonesimulator'}',
        '-DCMAKE_OSX_ARCHITECTURES=arm64',
        '-DCMAKE_OSX_DEPLOYMENT_TARGET=15.1',
        '-DCMAKE_XCODE_ATTRIBUTE_CODE_SIGNING_ALLOWED=NO',
        '-DCMAKE_XCODE_ATTRIBUTE_CODE_SIGNING_REQUIRED=NO',
      ];
    case OS.windows:
      return [
        '-A',
        target.architecture == Architecture.arm64 ? 'ARM64' : 'x64',
      ];
    case OS.linux:
      if (target.architecture == Architecture.arm64 &&
          !Abi.current().toString().contains('arm64')) {
        return [
          '-DCMAKE_SYSTEM_NAME=Linux',
          '-DCMAKE_SYSTEM_PROCESSOR=aarch64',
          '-DCMAKE_C_COMPILER=aarch64-linux-gnu-gcc',
          '-DCMAKE_CXX_COMPILER=aarch64-linux-gnu-g++',
        ];
      }
      if (target.architecture == Architecture.x64 &&
          !Abi.current().toString().contains('x64')) {
        return [
          '-DCMAKE_SYSTEM_NAME=Linux',
          '-DCMAKE_SYSTEM_PROCESSOR=x86_64',
          '-DCMAKE_C_COMPILER=x86_64-linux-gnu-gcc',
          '-DCMAKE_CXX_COMPILER=x86_64-linux-gnu-g++',
        ];
      }
      return [];
    case OS.android:
      final ndk =
          input.userDefines.path('android_ndk_home')?.toFilePath() ??
          Platform.environment['ANDROID_NDK_HOME'];
      if (ndk == null) {
        throw StateError(
          'Set the android_ndk_home user define to the NDK directory',
        );
      }
      if (code.android.targetNdkApi < 24) {
        throw UnsupportedError('ORT needs Android API 24 or later');
      }
      final abi = switch (target.architecture) {
        Architecture.arm => 'armeabi-v7a',
        Architecture.arm64 => 'arm64-v8a',
        Architecture.x64 => 'x86_64',
        _ => throw UnsupportedError('$target'),
      };
      return [
        '-DCMAKE_TOOLCHAIN_FILE=${p.join(ndk, 'build', 'cmake', 'android.toolchain.cmake')}',
        '-DANDROID_ABI=$abi',
        '-DANDROID_PLATFORM=android-${code.android.targetNdkApi}',
        '-DANDROID_STL=c++_static',
      ];
    default:
      throw UnsupportedError('$target');
  }
}

Future<String> _run(
  String executable,
  List<String> args,
  void Function(String) log,
) async {
  log('$executable ${args.join(' ')}');
  final result = await Process.run(executable, args);
  if (result.exitCode != 0) {
    throw ProcessException(
      executable,
      args,
      '${result.stdout}\n${result.stderr}',
      result.exitCode,
    );
  }
  return '${result.stdout}';
}

/// A release must work with Ubuntu 22.04's glibc and libstdc++, even if the
/// runner installs a newer compiler. Local source builds use their own host.
Future<void> _checkLinuxBaseline(
  File library,
  void Function(String) log,
) async {
  final versions = await _run('readelf', ['--version-info', library.path], log);
  for (final (prefix, ceiling) in [('GLIBC', '2.35'), ('GLIBCXX', '3.4.30')]) {
    final required =
        RegExp(
            '${prefix}_([0-9]+(?:\\.[0-9]+)*)',
          ).allMatches(versions).map((m) => m.group(1)!).toSet().toList()
          ..sort(_compareVersions);
    if (required.isEmpty) continue;
    final maximum = required.last;
    if (_compareVersions(maximum, ceiling) > 0) {
      throw StateError(
        '${library.path} needs ${prefix}_$maximum. '
        'Release files must need no more than ${prefix}_$ceiling. Use the Ubuntu 22.04 release runner.',
      );
    }
    log(
      '${p.basename(library.path)} needs ${prefix}_$maximum (baseline $ceiling)',
    );
  }
}

int _compareVersions(String a, String b) {
  final left = a.split('.').map(int.parse).toList();
  final right = b.split('.').map(int.parse).toList();
  for (var i = 0; i < left.length || i < right.length; i++) {
    final order = (i < left.length ? left[i] : 0).compareTo(
      i < right.length ? right[i] : 0,
    );
    if (order != 0) return order;
  }
  return 0;
}
