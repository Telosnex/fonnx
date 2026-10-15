// Compile the pinned C++ reference to generate acoustic chunking fixtures.
import 'dart:convert';
import 'dart:io';

const _revision = '234f60faa0eb388b01cdf7e60aca232af37aefda';
Future<void> main() async {
  final dir = Directory('build/kokoro/chunk-reference')
    ..createSync(recursive: true);
  final client = HttpClient();
  try {
    for (final file in ['chunk-policy.h', 'chunk-policy.cpp']) {
      final response = await (await client.getUrl(
        Uri.parse(
          'https://raw.githubusercontent.com/'
          'moonshine-ai/moonshine/$_revision/core/moonshine-tts/src/$file',
        ),
      )).close();
      if (response.statusCode != 200) {
        throw HttpException('Download failed for $file');
      }
      await response.pipe(File('${dir.path}/$file').openWrite());
    }
  } finally {
    client.close();
  }
  File('${dir.path}/reference.cpp').writeAsStringSync(_reference);
  final compile = await Process.run('c++', [
    '-std=c++20',
    '-O2',
    '${dir.path}/reference.cpp',
    '${dir.path}/chunk-policy.cpp',
    '-o',
    '${dir.path}/reference',
  ]);
  if (compile.exitCode != 0) throw StateError('${compile.stderr}');
  final result = await Process.run('${dir.path}/reference', []);
  if (result.exitCode != 0) throw StateError('${result.stderr}');
  final json = jsonDecode(result.stdout as String);
  File('test/data/goldens/kokoro_chunking.json').writeAsStringSync(
    '${const JsonEncoder.withIndent('  ').convert({'revision': _revision, 'cases': json})}\n',
  );
}

const _reference = r'''
#include "chunk-policy.h"
#include <iostream>
#include <iomanip>
#include <vector>
using namespace moonshine_tts;
template <typename T> void array(const std::vector<T>& v) {
 std::cout << "["; bool comma=false; for(auto x:v) {if(comma) std::cout<<","; comma=true; std::cout<<x;} std::cout<<"]";
}
int main() {
 std::cout<<std::setprecision(9)<<"[";
 for(int k=0;k<7;k++) {
  if(k) std::cout<<",";
  int frames=std::vector<int>{0,1,10,48,400,733,400}[k];
  ChunkPolicyOptions p; if(k==6) { p.first_chunk_seconds=.5f; p.tolerance_seconds=0; }
  std::vector<float> f0(frames*2), energy(frames*2);
  for(int i=0;i<frames*2;i++) {f0[i]=(i*37)%350; energy[i]=float((i*17)%97-48)/32;}
  auto cost=boundary_cost(f0,energy,frames);
  auto boundaries=plan_boundaries(cost,frames,40,p);
  auto spans=plan_spans(boundaries,frames,600,24000,p);
  std::cout<<"{\"frames\":"<<frames<<",\"first\":"<<p.first_chunk_seconds<<",\"tolerance\":"<<p.tolerance_seconds;
  std::cout<<",\"f0\":"; array(f0); std::cout<<",\"energy\":"; array(energy);
  std::cout<<",\"cost\":"; array(cost); std::cout<<",\"boundaries\":"; array(boundaries);
  std::cout<<",\"spans\":[";
  bool comma=false; for(auto s:spans) {if(comma) std::cout<<","; comma=true;
   std::cout<<"["<<s.decode_first_frame<<","<<s.decode_last_frame<<","<<s.keep_first_sample<<","<<s.keep_last_sample<<"]";}
  std::vector<float> joined; for(auto s:spans) {
   std::vector<float> piece(s.keep_last_sample-s.keep_first_sample);
   for(size_t i=0;i<piece.size();i++) piece[i]=float(i+s.keep_first_sample);
   crossfade_append(joined,piece,joined.empty()?0:600);
  }
  std::cout<<"],\"joined_count\":"<<joined.size()<<",\"samples\":[";
  comma=false; for(size_t i=0;i<joined.size();i+=97) {if(comma) std::cout<<",";comma=true;std::cout<<joined[i];}
  std::cout<<"],\"max_growth\":"<<max_sustainable_growth(p,.25f,40)<<"}";
 }
 std::cout<<"]";
}
''';
