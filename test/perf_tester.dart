// ignore_for_file: avoid_print

import 'dart:convert';
import 'dart:math' as math;

class PerfTester<Input, Output> {
  final String testName;
  final List<Input> testCases;
  final Output? Function(Input) implementation1;
  final Output? Function(Input) implementation2;
  final String impl1Name;
  final String impl2Name;
  final bool Function(Output?, Output?)? equalityCheck;
  
  final _random = math.Random(42);
  final List<double> impl1Times = [];
  final List<double> impl2Times = [];

  PerfTester({
    required this.testName,
    required this.testCases,
    required this.implementation1,
    required this.implementation2,
    this.impl1Name = 'Original',
    this.impl2Name = 'Optimized',
    this.equalityCheck,
  });

  void run({
    int warmupRuns = 100,
    int benchmarkRuns = 100,
    bool skipEqualityCheck = false,
  }) {
    if (!skipEqualityCheck) {
      _verifyImplementations();
    }
    _warmup(warmupRuns);
    _benchmark(benchmarkRuns);
    _printResults();
  }

  void _verifyImplementations() {
    print('Verifying implementations...');
    var allEqual = true;

    for (var i = 0; i < testCases.length; i++) {
      final input = testCases[i];
      final result1 = implementation1(input);
      final result2 = implementation2(input);

      bool isEqual;
      if (equalityCheck != null) {
        isEqual = equalityCheck!(result1, result2);
      } else {
        // Default equality check using JSON encoding for deep comparison
        final str1 = jsonEncode(result1);
        final str2 = jsonEncode(result2);
        isEqual = str1 == str2;
      }

      if (!isEqual) {
        print('\nMismatch found for test case $i:');
        print('Input: $input');
        print('$impl1Name: $result1');
        print('$impl2Name: $result2');
        allEqual = false;
      }
    }

    if (allEqual) {
      print('\nAll test cases produced identical output! ✅');
    } else {
      print('\nWarning: Differences found in outputs! ❌');
    }
  }

  void _warmup(int runs) {
    print('\nWarming up...');
    for (var i = 0; i < runs; i++) {
      final input = testCases[_random.nextInt(testCases.length)];
      implementation1(input);
      implementation2(input);
    }
  }

  void _benchmark(int runs) {
    print('\nRunning benchmark...');
    for (var run = 0; run < runs; run++) {
      var testA = run % 2 == 0;
      // print('\nRun ${run + 1}:');

      // First run
      var startTime = DateTime.now().microsecondsSinceEpoch;
      for (var input in testCases) {
        testA ? implementation1(input) : implementation2(input);
      }
      var time1 = (DateTime.now().microsecondsSinceEpoch - startTime) / 1000.0;

      // Second run
      startTime = DateTime.now().microsecondsSinceEpoch;
      for (var input in testCases) {
        testA ? implementation2(input) : implementation1(input);
      }
      var time2 = (DateTime.now().microsecondsSinceEpoch - startTime) / 1000.0;

      // Store results
      if (testA) {
        impl1Times.add(time1);
        impl2Times.add(time2);
      } else {
        impl2Times.add(time1);
        impl1Times.add(time2);
      }

      // print('${testA ? impl1Name : impl2Name}: ${time1.toStringAsFixed(3)}ms');
      // print('${testA ? impl2Name : impl1Name}: ${time2.toStringAsFixed(3)}ms');
    }
  }

  void _printResults() {
    _printStats();
    _printVisualizations();
  }

  void _printStats() {
    impl1Times.sort();
    impl2Times.sort();

    double mean(List<double> list) =>
        list.reduce((a, b) => a + b) / list.length;
    double median(List<double> list) => list.length.isOdd
        ? list[list.length ~/ 2]
        : (list[list.length ~/ 2 - 1] + list[list.length ~/ 2]) / 2;
    double stdDev(List<double> list, double mean) {
      var squaredDiffs = list.map((x) => math.pow(x - mean, 2));
      return math.sqrt(squaredDiffs.reduce((a, b) => a + b) / (list.length - 1));
    }

    var impl1Mean = mean(impl1Times);
    var impl2Mean = mean(impl2Times);
    var improvement = ((impl1Mean - impl2Mean) / impl1Mean * 100);

    print('\n=== $testName Performance Summary ===');
    print('                  $impl2Name    $impl1Name     Improvement');
    print('Min (ms):         ${impl2Times.first.toStringAsFixed(3).padRight(12)} '
        '${impl1Times.first.toStringAsFixed(3).padRight(12)}');
    print('Max (ms):         ${impl2Times.last.toStringAsFixed(3).padRight(12)} '
        '${impl1Times.last.toStringAsFixed(3).padRight(12)}');
    print('Median (ms):      ${median(impl2Times).toStringAsFixed(3).padRight(12)} '
        '${median(impl1Times).toStringAsFixed(3).padRight(12)}');
    print('Mean (ms):        ${impl2Mean.toStringAsFixed(3).padRight(12)} '
        '${impl1Mean.toStringAsFixed(3).padRight(12)} '
        '${improvement.toStringAsFixed(1)}%');
    print('Std Dev (ms):     ${stdDev(impl2Times, impl2Mean).toStringAsFixed(3).padRight(12)} '
        '${stdDev(impl1Times, impl1Mean).toStringAsFixed(3).padRight(12)}');
  }

  void _printVisualizations() {
    print('\n=== VISUALIZATIONS ===');
    print(_generateBoxPlot(title: 'Time Distribution'));
    print(_generateHistogram(impl2Times, title: '$impl2Name Times'));
    print(_generateHistogram(impl1Times, title: '$impl1Name Times'));
  }

  String _generateBoxPlot({int width = 60, String title = ''}) {
    String boxPlotRow(List<double> data, String label) {
      var sorted = List<double>.of(data)..sort();
      var min = sorted.first;
      var max = sorted.last;
      var q1 = sorted[(sorted.length * 0.25).floor()];
      var median = sorted.length.isOdd
          ? sorted[sorted.length ~/ 2]
          : (sorted[(sorted.length - 1) ~/ 2] + sorted[sorted.length ~/ 2]) / 2;
      var q3 = sorted[(sorted.length * 0.75).floor()];

      var scale = width / (max - min);
      var q1Pos = ((q1 - min) * scale).round();
      var medianPos = ((median - min) * scale).round();
      var q3Pos = ((q3 - min) * scale).round();

      var line = List.filled(width, ' ');

      // Draw the box
      for (var i = q1Pos; i <= q3Pos; i++) {
        line[i] = '─';
      }
      // Draw whiskers
      for (var i = 0; i < q1Pos; i++) {
        line[i] = '─';
      }
      for (var i = q3Pos + 1; i < width; i++) {
        line[i] = '─';
      }

      line[0] = '|';
      line[q1Pos] = '├';
      line[medianPos] = '┼';
      line[q3Pos] = '┤';
      line[width - 1] = '|';

      return '${label.padRight(12)} |${line.join('')}| '
          '${min.toStringAsFixed(1)}-${max.toStringAsFixed(1)}ms';
    }

    var result = StringBuffer();
    if (title.isNotEmpty) {
      result.writeln('\n$title');
      result.writeln('=' * title.length);
    }

    result.writeln(boxPlotRow(impl2Times, impl2Name));
    result.writeln(boxPlotRow(impl1Times, impl1Name));

    return result.toString();
  }

  String _generateHistogram(List<double> data,
      {int bins = 10, int width = 50, String title = ''}) {
    if (data.isEmpty) return '';

    var min = data.reduce(math.min);
    var max = data.reduce(math.max);
    var range = max - min;
    var binWidth = range / bins;

    var histogram = List<int>.filled(bins, 0);
    for (var value in data) {
      var bin = ((value - min) / binWidth).floor();
      bin = math.min(bin, bins - 1);
      histogram[bin]++;
    }

    var maxCount = histogram.reduce(math.max);
    var result = StringBuffer();

    if (title.isNotEmpty) {
      result.writeln('\n$title');
      result.writeln('=' * title.length);
    }

    for (var i = 0; i < bins; i++) {
      var binStart = min + (i * binWidth);
      var binEnd = min + ((i + 1) * binWidth);
      var count = histogram[i];
      var bars = (count / maxCount * width).round();

      result.writeln(
          '${binStart.toStringAsFixed(1).padLeft(7)}-${binEnd.toStringAsFixed(1).padLeft(7)}ms '
          '|${'█' * bars}${' ' * (width - bars)}| $count');
    }

    return result.toString();
  }
}