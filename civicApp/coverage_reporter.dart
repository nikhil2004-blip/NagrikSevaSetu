// ignore_for_file: avoid_print
import 'dart:io' as io;

void main() async {
  final file = io.File('coverage/lcov.info');
  if (!file.existsSync()) {
    print('No coverage/lcov.info found.');
    return;
  }
  
  final lines = await file.readAsLines();
  
  int totalLines = 0;
  int hitLines = 0;
  
  String currentFile = '';
  int fileTotal = 0;
  int fileHit = 0;
  List<int> uncovered = [];
  
  print('-------------------------------------------------------------------------------------------------');
  print('File                               | % Stmts | % Branch | % Funcs | % Lines | Uncovered Line #s');
  print('-------------------------------------------------------------------------------------------------');
  
  void printRow(String file, int total, int hit, List<int> uncov) {
    if (total == 0) return;
    
    double pct = (hit / total) * 100;
    String stmtStr = pct.toStringAsFixed(2).padLeft(7);
    String lineStr = pct.toStringAsFixed(2).padLeft(7);
    
    // Format Uncovered Lines (e.g. 12-15, 20, 22-25)
    String uncovStr = '';
    if (uncov.isNotEmpty) {
      uncov.sort();
      List<String> ranges = [];
      int start = uncov[0];
      int end = uncov[0];
      
      for (int i = 1; i < uncov.length; i++) {
        if (uncov[i] == end + 1) {
          end = uncov[i];
        } else {
          ranges.add(start == end ? start.toString() : '\${start}-\${end}');
          start = uncov[i];
          end = uncov[i];
        }
      }
      ranges.add(start == end ? start.toString() : '\${start}-\${end}');
      uncovStr = ranges.join(', ');
      if (uncovStr.length > 35) {
        uncovStr = '${uncovStr.substring(0, 32)}...';
      }
    }
    
    // Truncate path for display
    var displayPath = file;
    if (displayPath.startsWith('lib/')) {
      displayPath = displayPath.substring(4);
    }
    if (displayPath.startsWith('lib\\\\')) {
      displayPath = displayPath.substring(4);
    }
    if (displayPath.length > 32) {
      displayPath = '...${displayPath.substring(displayPath.length - 29)}';
    }
    
    // We put '--' for Branch and Funcs since Dart lcov.info doesn't generate them by default
    print('${displayPath.padRight(34)} | $stmtStr |       -- |      -- | $lineStr | $uncovStr');
  }
  
  for (final line in lines) {
    if (line.startsWith('SF:')) {
      currentFile = line.substring(3).replaceAll('\\\\', '/');
      fileTotal = 0;
      fileHit = 0;
      uncovered = [];
    } else if (line.startsWith('DA:')) {
      // DA:line,hit
      final parts = line.substring(3).split(',');
      if (parts.length >= 2) {
        int lineNum = int.tryParse(parts[0]) ?? 0;
        int hits = int.tryParse(parts[1]) ?? 0;
        fileTotal++;
        totalLines++;
        if (hits > 0) {
          fileHit++;
          hitLines++;
        } else {
          uncovered.add(lineNum);
        }
      }
    } else if (line == 'end_of_record') {
      printRow(currentFile, fileTotal, fileHit, uncovered);
    }
  }
  
  print('-------------------------------------------------------------------------------------------------');
  double totalPct = totalLines > 0 ? (hitLines / totalLines) * 100 : 0.0;
  String totalStr = totalPct.toStringAsFixed(2).padLeft(7);
  print('All files                          | $totalStr |       -- |      -- | $totalStr |');
  print('-------------------------------------------------------------------------------------------------');
}
