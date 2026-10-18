/// Real byte work within one stage; never a time estimate for the whole job.
class FileOperationProgress {
  const FileOperationProgress({
    required this.stage,
    required this.fileName,
    required this.fileIndex,
    required this.fileCount,
    required this.bytes,
    required this.total,
    required this.overallBytes,
    required this.overallTotal,
  });
  final String stage;
  final String fileName;
  final int fileIndex;
  final int fileCount;
  final int bytes;
  final int total;
  final int overallBytes;
  final int overallTotal;
}
