part of flutter_bluetooth_printer;

class DiscoveryResult extends DiscoveryState {
  final List<BluetoothDevice> devices;
  DiscoveryResult({required this.devices});
}

class FlutterBluetoothPrinter {
  static void registerWith() {
    FlutterBluetoothPrinterPlatform.instance = _MethodChannelBluetoothPrinter();
  }

  static Stream<DiscoveryState> _discovery() async* {
    final result = <BluetoothDevice>[];
    await for (final state in FlutterBluetoothPrinterPlatform.instance.discovery) {
      if (state is BluetoothDevice) {
        result.add(state);
        yield DiscoveryResult(devices: result.toSet().toList());
      } else {
        result.clear();
        yield state;
      }
    }
  }

  static ValueNotifier<BluetoothConnectionState> get connectionStateNotifier =>
      FlutterBluetoothPrinterPlatform.instance.connectionStateNotifier;

  static Stream<DiscoveryState> get discovery => _discovery();

  static Future<void> printBytes({
    required String address,
    required Uint8List data,

    /// if true, you should manually disconnect the printer after finished
    required bool keepConnected,
    ProgressCallback? onProgress,
  }) async {
    await FlutterBluetoothPrinterPlatform.instance.write(
      address: address,
      data: data,
      onProgress: onProgress,
      keepConnected: keepConnected,
    );
  }

  static Future<void> printImage({
    required String address,
    required img.Image image,
    PaperSize paperSize = PaperSize.mm58,
    ProgressCallback? onProgress,
    int addFeeds = 0,
    bool useImageRaster = false,
    required bool keepConnected,
  }) async {
    final optimizedImage = await _optimizeImage(
      paperSize: paperSize,
      src: image,
    );

    final profile = await CapabilityProfile.load();
    final generator = Generator(
      paperSize,
      profile,
      spaceBetweenRows: 0,
    );
    List<int> imageData;
    if (useImageRaster) {
      imageData = generator.imageRaster(
        optimizedImage,
        highDensityHorizontal: true,
        highDensityVertical: true,
        imageFn: PosImageFn.bitImageRaster,
      );
    } else {
      imageData = generator.image(optimizedImage);
    }

    final additional = [
      ...generator.emptyLines(addFeeds),
      ...generator.text('.'),
    ];

    return printBytes(
      keepConnected: keepConnected,
      address: address,
      data: Uint8List.fromList([
        ...generator.reset(),
        ...imageData,
        ...generator.reset(),
        ...additional,
      ]),
      onProgress: onProgress,
    );
  }

  static Future<img.Image> _optimizeImage({
    required img.Image src,
    required PaperSize paperSize,
  }) async {
    final arg = <String, dynamic>{'src': src, 'paperSize': paperSize};

    if (kIsWeb) {
      return _blackwhiteInternal(arg);
    }

    return compute(_blackwhiteInternal, arg);
  }

  static Future<img.Image> _blackwhiteInternal(Map<String, dynamic> arg) async {
    final baseImage = arg['src'] as img.Image;
    final paperSize = arg['paperSize'] as PaperSize;

    img.Image src = baseImage;

    src = img.smooth(src, weight: 1.5);
    for (int y = 0; y < src.height; ++y) {
      for (int x = 0; x < src.width; ++x) {
        final pixel = src.getPixel(x, y);
        final lum = img.getLuminanceRgb(pixel.r, pixel.g, pixel.b) / 255;
        if (lum > 0.8) {
          src.setPixelRgb(x, y, 255, 255, 255);
        } else {
          src.setPixelRgb(x, y, 0, 0, 0);
        }
      }
    }

    src = img.pixelate(
      src,
      size: (src.width / paperSize.width).round(),
      mode: img.PixelateMode.average,
    );

    final dotsPerLine = paperSize.width;
    if (src.width > dotsPerLine) {
      final ratio = dotsPerLine / src.width;
      final height = (src.height * ratio).ceil();
      src = img.copyResize(src, width: dotsPerLine, height: height);
    }
    return src;
  }

  static Future<BluetoothDevice?> selectDevice(BuildContext context) async {
    final selected = await showModalBottomSheet(
      context: context,
      builder: (context) => const BluetoothDeviceSelector(),
    );
    if (selected is BluetoothDevice) {
      return selected;
    }
    return null;
  }

  static Future<bool> disconnect(String address) async {
    return FlutterBluetoothPrinterPlatform.instance.disconnect(address);
  }
}
