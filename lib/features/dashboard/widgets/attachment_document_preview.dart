import 'dart:async';
import 'dart:ffi';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_widget_from_html_core/flutter_widget_from_html_core.dart';
import 'package:pdfrx/pdfrx.dart';
import 'package:path/path.dart' as p;
import 'package:html/dom.dart' as dom;

import '../services/office_preview_service.dart';

Future<void>? _pdfRuntimeReady;

/// Check and preload the app-local DLL before PDFium's worker starts. This also
/// avoids the engine's module-path initialization race in standalone test hosts.
Future<void> initializeAttachmentPdf({String? libraryPath}) async {
  try {
    await (_pdfRuntimeReady ??= () async {
      if (Platform.isWindows) {
        final dll =
            libraryPath ??
            p.join(p.dirname(Platform.resolvedExecutable), 'pdfium.dll');
        if (!File(dll).existsSync()) {
          throw const DocumentPreviewException(
            'PDF preview component unavailable. Open it in a system app.',
          );
        }
        DynamicLibrary.open(dll);
        Pdfrx.pdfiumModulePath = dll;
      }
      await pdfrxFlutterInitialize(dismissPdfiumWasmWarnings: true);
    }());
  } catch (_) {
    _pdfRuntimeReady = null;
    throw const DocumentPreviewException(
      'PDF preview component unavailable. Open it in a system app.',
    );
  }
}

bool attachmentSupportsDocumentPreview(String name) => {
  'pdf',
  'doc',
  'docx',
  'xls',
  'xlsx',
}.contains(name.split('.').last.toLowerCase());

abstract class AttachmentDocumentRenderer {
  Widget build(BuildContext context);
  Future<void> load();

  /// Revoke the surface immediately; join pending work before cache deletion.
  Future<void> dispose();
}

typedef AttachmentDocumentFactory =
    AttachmentDocumentRenderer Function(
      String path,
      String fileName,
      Future<void> Function() onOpenSystem,
    );

class NativeAttachmentDocument implements AttachmentDocumentRenderer {
  NativeAttachmentDocument(
    this.path,
    this.fileName,
    this.onOpenSystem, {
    this.office = const OfficePreviewService(),
  });
  final String path;
  final String fileName;
  final Future<void> Function() onOpenSystem;
  final OfficePreviewService office;
  final _changes = ValueNotifier<int>(0);
  PdfDocument? _pdf;
  ui.Image? _image;
  String? _html;
  String? _error;
  int _page = 1;
  bool _busy = true;
  bool _closed = false;
  Future<void>? _loading;
  Future<void>? _rendering;
  Future<void>? _disposal;

  @override
  Future<void> load() => _loading ??= _load();
  Future<void> _load() async {
    if (_closed) return;
    try {
      if (fileName.toLowerCase().endsWith('.pdf')) {
        await initializeAttachmentPdf();
        if (_closed) return;
        _pdf = await PdfDocument.openFile(path, passwordProvider: () => null);
        if (_closed) return;
        if (_pdf!.pages.isEmpty) {
          throw const DocumentPreviewException('This PDF has no pages.');
        }
        await _renderPage(1);
      } else {
        final content = await office.load(path);
        if (!_closed) _html = content;
      }
    } on PdfPasswordException {
      _error = 'This PDF requires its own password. Open it in a system app.';
    } on DocumentPreviewException catch (error) {
      _error = error.message;
    } catch (_) {
      _error =
          'Document preview unavailable. The file may be damaged or unsupported.';
    } finally {
      _busy = false;
      if (!_closed) _changes.value++;
    }
  }

  Future<void> _renderPage(int page) async {
    final pdfPage = _pdf!.pages[page - 1];
    if (!pdfPage.width.isFinite ||
        !pdfPage.height.isFinite ||
        pdfPage.width <= 0 ||
        pdfPage.height <= 0) {
      throw const DocumentPreviewException(
        'This PDF page has invalid dimensions.',
      );
    }
    // One bounded page image, never a whole-file byte array or page cache.
    final scale = math.min(2.0, 2048 / math.max(pdfPage.width, pdfPage.height));
    final width = math.max(1, (pdfPage.width * scale).round());
    final height = math.max(1, (pdfPage.height * scale).round());
    final pixels = await pdfPage.render(
      width: width,
      height: height,
      fullWidth: width.toDouble(),
      fullHeight: height.toDouble(),
    );
    if (pixels == null) {
      throw const DocumentPreviewException('PDF page preview unavailable.');
    }
    try {
      if (_closed) return;
      final image = await pixels.createImage();
      if (_closed) {
        image.dispose();
        return;
      }
      final old = _image;
      _image = image;
      _page = page;
      old?.dispose();
    } finally {
      pixels.dispose();
    }
  }

  Future<void> goToPage(int page) async {
    if (_closed ||
        _busy ||
        _pdf == null ||
        page < 1 ||
        page > _pdf!.pages.length) {
      return;
    }
    _busy = true;
    _changes.value++;
    _rendering = _renderPage(page);
    try {
      await _rendering;
    } catch (_) {
      _error = 'PDF page preview unavailable. Open it in a system app.';
    } finally {
      _busy = false;
      if (!_closed) _changes.value++;
    }
  }

  @override
  Future<void> dispose() => _disposal ??= _dispose();
  Future<void> _dispose() async {
    _closed = true;
    _changes.value++;
    await _loading;
    await _rendering?.catchError((Object _) {});
    _image?.dispose();
    _image = null;
    _html = null;
    await _pdf?.dispose();
    _pdf = null;
    _changes.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _changes,
    builder: (context, _) {
      if (_closed) return const SizedBox.shrink();
      if (_error != null) {
        return _DocumentError(message: _error!, onOpenSystem: onOpenSystem);
      }
      if (_html != null) {
        return _OfficeSurface(html: _html!, fileName: fileName);
      }
      if (_image != null) {
        return _PdfSurface(
          image: _image!,
          page: _page,
          pages: _pdf!.pages.length,
          busy: _busy,
          onPage: goToPage,
        );
      }
      return const Center(
        child: CircularProgressIndicator(
          semanticsLabel: 'Preparing document preview',
        ),
      );
    },
  );
}

class _DocumentError extends StatelessWidget {
  const _DocumentError({required this.message, required this.onOpenSystem});
  final String message;
  final Future<void> Function() onOpenSystem;
  @override
  Widget build(BuildContext context) => Center(
    child: SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(message, textAlign: TextAlign.center),
          TextButton.icon(
            onPressed: onOpenSystem,
            icon: const Icon(Icons.open_in_new),
            label: const Text('Open in system app'),
          ),
        ],
      ),
    ),
  );
}

class _PdfSurface extends StatefulWidget {
  const _PdfSurface({
    required this.image,
    required this.page,
    required this.pages,
    required this.busy,
    required this.onPage,
  });
  final ui.Image image;
  final int page;
  final int pages;
  final bool busy;
  final ValueChanged<int> onPage;
  @override
  State<_PdfSurface> createState() => _PdfSurfaceState();
}

class _PdfSurfaceState extends State<_PdfSurface> {
  final _transform = TransformationController();
  final _viewportKey = GlobalKey();
  double _gestureStartScale = 1;
  Offset? _gestureSceneCenter;
  bool _pinching = false;
  @override
  void didUpdateWidget(covariant _PdfSurface oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.page != widget.page) _transform.value = Matrix4.identity();
  }

  @override
  void dispose() {
    _transform.dispose();
    super.dispose();
  }

  void _zoom(double factor) =>
      _setScale(_transform.value.getMaxScaleOnAxis() * factor);

  void _setScale(double requestedScale, {Offset? sceneAnchor}) {
    final viewport =
        _viewportKey.currentContext?.findRenderObject() as RenderBox?;
    if (viewport == null || !viewport.hasSize) return;
    final currentScale = _transform.value.getMaxScaleOnAxis();
    final scale = requestedScale.clamp(1.0, 5.0);
    if (scale == currentScale && sceneAnchor == null) return;
    final center = viewport.size.center(Offset.zero);
    final sceneCenter = sceneAnchor ?? _transform.toScene(center);
    // Keep the point currently under the viewport center stationary. Scaling
    // about (0, 0) instead moves the document toward the top-left corner.
    // Keep the viewport covered when zooming back to Fit.
    final x = (center.dx - sceneCenter.dx * scale).clamp(
      viewport.size.width * (1 - scale),
      0.0,
    );
    final y = (center.dy - sceneCenter.dy * scale).clamp(
      viewport.size.height * (1 - scale),
      0.0,
    );
    _transform.value = Matrix4.diagonal3Values(scale, scale, 1)
      ..setTranslationRaw(x, y, 0);
  }

  void _pan(Offset delta) {
    final viewport =
        _viewportKey.currentContext?.findRenderObject() as RenderBox?;
    if (viewport == null || !viewport.hasSize) return;
    final matrix = _transform.value;
    final scale = matrix.getMaxScaleOnAxis();
    final translation = matrix.getTranslation();
    _transform.value = matrix.clone()
      ..setTranslationRaw(
        (translation.x + delta.dx).clamp(
          viewport.size.width * (1 - scale),
          0.0,
        ),
        (translation.y + delta.dy).clamp(
          viewport.size.height * (1 - scale),
          0.0,
        ),
        0,
      );
  }

  void _handlePointerSignal(PointerSignalEvent event) {
    if (event is! PointerScrollEvent && event is! PointerScaleEvent) return;
    GestureBinding.instance.pointerSignalResolver.register(event, (resolved) {
      // Discrete signals must not reset an ongoing native gesture or add pan
      // while it is pinching. Both input paths write through this controller.
      if (_pinching) return;
      if (resolved is PointerScaleEvent) {
        _zoom(resolved.scale);
      } else if (resolved is PointerScrollEvent) {
        if (HardwareKeyboard.instance.isControlPressed) {
          _zoom(
            math.exp(
              -resolved.scrollDelta.dy / kDefaultMouseScrollToScaleFactor,
            ),
          );
        } else {
          _pan(-resolved.scrollDelta);
        }
      }
    });
  }

  void _startInteraction(ScaleStartDetails details) {
    _gestureStartScale = _transform.value.getMaxScaleOnAxis();
    final viewport =
        _viewportKey.currentContext?.findRenderObject() as RenderBox?;
    _gestureSceneCenter = viewport != null && viewport.hasSize
        ? _transform.toScene(viewport.size.center(Offset.zero))
        : null;
    _pinching = false;
  }

  void _updateInteraction(ScaleUpdateDetails details) {
    if (details.scale != 1 || _pinching) {
      // Scale is cumulative. Once classified as a pinch, do not reinterpret
      // centroid motion (even at scale 1) as pan until the gesture ends.
      _pinching = true;
      _setScale(
        _gestureStartScale * details.scale,
        sceneAnchor: _gestureSceneCenter,
      );
    } else {
      _pan(details.focalPointDelta);
    }
  }

  @override
  Widget build(BuildContext context) => Column(
    children: [
      Wrap(
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          IconButton(
            tooltip: 'Previous page',
            onPressed: widget.busy || widget.page == 1
                ? null
                : () => widget.onPage(widget.page - 1),
            icon: const Icon(Icons.chevron_left),
          ),
          Text(
            '${widget.page} / ${widget.pages}',
            semanticsLabel: 'Page ${widget.page} of ${widget.pages}',
          ),
          IconButton(
            tooltip: 'Next page',
            onPressed: widget.busy || widget.page == widget.pages
                ? null
                : () => widget.onPage(widget.page + 1),
            icon: const Icon(Icons.chevron_right),
          ),
          IconButton(
            tooltip: 'Zoom out',
            onPressed: () => _zoom(1 / 1.25),
            icon: const Icon(Icons.zoom_out),
          ),
          IconButton(
            tooltip: 'Zoom in',
            onPressed: () => _zoom(1.25),
            icon: const Icon(Icons.zoom_in),
          ),
          TextButton(
            onPressed: () => _transform.value = Matrix4.identity(),
            child: const Text('Fit page'),
          ),
        ],
      ),
      if (widget.busy) const LinearProgressIndicator(),
      Expanded(
        child: ClipRect(
          child: Listener(
            onPointerSignal: _handlePointerSignal,
            child: GestureDetector(
              key: _viewportKey,
              behavior: HitTestBehavior.opaque,
              onScaleStart: _startInteraction,
              onScaleUpdate: _updateInteraction,
              onScaleEnd: (_) {
                _gestureSceneCenter = null;
                _pinching = false;
              },
              child: AnimatedBuilder(
                key: const ValueKey('pdf-viewport-transform'),
                animation: _transform,
                builder: (context, child) =>
                    Transform(transform: _transform.value, child: child),
                child: Center(
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: RawImage(image: widget.image, fit: BoxFit.contain),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    ],
  );
}

/// Defense in depth: no external image providers, including file:// paths.
class OfflineDocumentWidgetFactory extends WidgetFactory {
  @override
  ImageProvider? imageProviderFromNetwork(String url) => null;
  @override
  ImageProvider? imageProviderFromFileUri(String url) => null;
  @override
  ImageProvider? imageProviderFromAsset(String url) => null;
}

Map<String, String>? officePreviewStyles(dom.Element element) =>
    switch (element.localName) {
      'p' => {'margin': '0 0 14px 0', 'line-height': '1.6'},
      'h1' => {
        'font-size': '26px',
        'margin': '0 0 20px 0',
        'line-height': '1.25',
      },
      'h2' => {
        'font-size': '20px',
        'margin': '24px 0 12px 0',
        'line-height': '1.3',
      },
      'h3' => {'font-size': '17px', 'margin': '20px 0 10px 0'},
      'table' => {
        'border-collapse': 'collapse',
        'width': '100%',
        'margin': '16px 0',
      },
      'tr' => {
        'background-color': element.attributes['data-preview-row'] == '1'
            ? '#f5f7fa'
            : '#ffffff',
      },
      'td' => {
        'padding': '8px 10px',
        'border': '1px solid #dce2ea',
        'vertical-align': 'top',
      },
      'th' => {
        'padding': '9px 10px',
        'border': '1px solid #dce2ea',
        'background-color': '#e8edf4',
        'font-weight': 'bold',
        'vertical-align': 'top',
      },
      'blockquote' => {
        'border-left': '3px solid #cbd5e1',
        'padding': '8px 16px',
        'margin': '16px 0',
      },
      _ => null,
    };

class _OfficeSurface extends StatefulWidget {
  const _OfficeSurface({required this.html, required this.fileName});
  final String html;
  final String fileName;
  @override
  State<_OfficeSurface> createState() => _OfficeSurfaceState();
}

class _OfficeSurfaceState extends State<_OfficeSurface> {
  final _vertical = ScrollController();
  final _horizontal = ScrollController();
  @override
  void dispose() {
    _vertical.dispose();
    _horizontal.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final spreadsheet = RegExp(
      r'\.xlsx?$',
      caseSensitive: false,
    ).hasMatch(widget.fileName);
    return Column(
      children: [
        if (widget.fileName.toLowerCase().endsWith('.doc'))
          const Padding(
            padding: EdgeInsets.all(8),
            child: Text('Legacy DOC preview · layout may differ from Word'),
          ),
        Expanded(
          child: ColoredBox(
            color: Theme.of(context).colorScheme.surfaceContainerLowest,
            child: LayoutBuilder(
              builder: (context, constraints) {
                final viewport = math.max(0.0, constraints.maxWidth - 32);
                final width = spreadsheet
                    ? math.max(1120.0, viewport)
                    : math.min(760.0, viewport);
                return Scrollbar(
                  controller: _vertical,
                  thumbVisibility: true,
                  notificationPredicate: (notification) =>
                      notification.metrics.axis == Axis.vertical,
                  child: Scrollbar(
                    controller: _horizontal,
                    thumbVisibility: spreadsheet,
                    notificationPredicate: (notification) =>
                        notification.metrics.axis == Axis.horizontal,
                    child: ScrollConfiguration(
                      behavior: ScrollConfiguration.of(
                        context,
                      ).copyWith(scrollbars: false),
                      child: SingleChildScrollView(
                        controller: _vertical,
                        primary: false,
                        padding: const EdgeInsets.all(16),
                        child: SingleChildScrollView(
                          controller: _horizontal,
                          primary: false,
                          scrollDirection: Axis.horizontal,
                          child: SizedBox(
                            width: math.max(viewport, width),
                            child: Align(
                              alignment: Alignment.topCenter,
                              child: Container(
                                key: const ValueKey('office-preview-paper'),
                                width: width,
                                constraints: BoxConstraints(
                                  minHeight: math.max(
                                    0.0,
                                    constraints.maxHeight - 32,
                                  ),
                                ),
                                padding: EdgeInsets.all(
                                  spreadsheet || width < 500 ? 20 : 40,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  border: Border.all(
                                    color: const Color(0xffdce2ea),
                                  ),
                                  borderRadius: BorderRadius.circular(4),
                                  boxShadow: const [
                                    BoxShadow(
                                      color: Color(0x18000000),
                                      blurRadius: 12,
                                      offset: Offset(0, 3),
                                    ),
                                  ],
                                ),
                                child: SelectionArea(
                                  child: HtmlWidget(
                                    widget.html,
                                    factoryBuilder:
                                        OfflineDocumentWidgetFactory.new,
                                    onTapUrl: (_) => true,
                                    textStyle: const TextStyle(
                                      color: Color(0xff243044),
                                      fontSize: 14,
                                      height: 1.6,
                                    ),
                                    customStylesBuilder: officePreviewStyles,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      ],
    );
  }
}
