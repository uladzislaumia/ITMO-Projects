import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'models.dart';
import 'utils.dart';

import '../core/byte_storage.dart';
import '../encoder/ppm_encoder.dart';

class JpgCompressor {
  static ProcessedJpgData compress(JpgData data) {
    final dcLength = ByteOutputStorage();
    final acLength = ByteOutputStorage();
    final binaryAcDc = ByteOutputStorage();

    var previousDC = 0;
    for (var table in data.tables) {
      // Calculate DC-difference
      final dc = table[0][0];
      final dcDiff = dc - previousDC;
      previousDC = dc;

      // Write DC-Difference length
      final len = (dcDiff != 0) ? getBinaryCodeLength(dcDiff.abs()) : 0;
      for (var k = 3; k >= 0; k--) {
        final bit = (len >> k) & 1;
        dcLength.writeBits(bit == 1 ? Bit.One : Bit.Zero, 1);
      }

      // Write non-nullable DC-Difference
      if (dcDiff != 0) {
        final processedDcDiff = dcDiff > 0 ? dcDiff : (pow(2, len) - dcDiff.abs() - 1).toInt();
        writeStringAsBinary(processedDcDiff.toRadixString(2).padLeft(len, '0'), binaryAcDc);
      }

      // Process ACs
      var run = 0;
      for (var i = 0; i <= 7; i++) {
        for (var j = (i == 0) ? 1 : 0; j <= 7; j++) {
          final ac = table[i][j];
          if (ac == 0) {
            run++;
          } else {
            // Write zero count before AC
            if (run > 15) {
              acLength.writeByte((run ~/ 16) << 4);
              run %= 16;
            }
            writeStringAsBinary(run.toRadixString(2).padLeft(4, '0'), acLength);

            // Write AC length
            final len = getBinaryCodeLength(ac.abs());
            writeStringAsBinary(len.toRadixString(2).padLeft(4, '0'), acLength);

            // Write AC
            final processedAc = ac > 0 ? ac : (pow(2, len) - ac.abs() - 1).toInt();
            writeStringAsBinary(processedAc.toRadixString(2).padLeft(len, '0'), binaryAcDc);

            run = 0;
          }
        }
      }
      // End of block
      acLength.writeByte(0);
    }

    // Compress DC
    final dcPreparedData = dcLength.toList();
    final dcCompressedData = ByteOutputStorage();
    final dcEncoder = PpmEncoder(data: dcPreparedData, output: dcCompressedData, D: 0);
    dcEncoder.compress();

    // Compress AC
    final acPreparedData = acLength.toList();
    final acCompressedData = ByteOutputStorage();
    final acEncoder = PpmEncoder(data: acPreparedData, output: acCompressedData, D: 1);
    acEncoder.compress();

    return ProcessedJpgData(
      dcPreparedData,
      acPreparedData,
      dcCompressedData.toList(),
      acCompressedData.toList(),
      binaryAcDc.toList(),
      data,
    );
  }
}

Future<Uint8List> launchCompression(String jpgPath, [bool debug = false]) async {
  final jpgFileName = extractFileName(jpgPath);
  await Process.run(r'bin/jpg_decoder.exe', [jpgPath]);
  final jpgData = loadJpgData(jpgFileName + '_data');
  File(jpgFileName + '_data').delete();
  final processedJpgData = JpgCompressor.compress(jpgData);
  final compressedJpgData = processedJpgData.serialize();
  saveByteData(jpgFileName + '_compressed', compressedJpgData);
  if (debug) {
    processedJpgData.printStatistics(jpgFileName);
  }
  return compressedJpgData;
}

Future<void> main(List<String> args) async {
  if (args.length > 0) {
    final jpgPath = args[0];
    await launchCompression(jpgPath);
  } else {
    print('Please, specify input file name containing JPG file');
  }
}
