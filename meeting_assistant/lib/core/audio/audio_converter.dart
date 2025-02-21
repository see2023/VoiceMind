import 'dart:typed_data';

class AudioConverter {
  static Uint8List convertToInt16PCM(Float32List floatData) {
    final int16Data = Int16List(floatData.length);
    for (var i = 0; i < floatData.length; i++) {
      // 将 float 转换为 int16 (-32768 到 32767)
      int16Data[i] = (floatData[i] * 32767).round().clamp(-32768, 32767);
    }
    return int16Data.buffer.asUint8List();
  }
}
