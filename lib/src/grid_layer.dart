import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:flutter_map/plugin_api.dart';
import 'package:vector_map_tiles/src/tile_pair_cache.dart';
import 'package:vector_tile_renderer/vector_tile_renderer.dart';
import 'disposable_state.dart';
import 'tile_identity.dart';
import 'vector_tile_provider.dart';
import 'tile_widgets.dart';

enum RenderMode { vector, mixed }

class VectorTileLayerOptions extends LayerOptions {
  final VectorTileProvider tileProvider;
  final Theme theme;
  final RenderMode renderMode;
  final int maxCachedTiles;

  VectorTileLayerOptions(
      {required this.tileProvider,
      required this.theme,
      this.maxCachedTiles = 40,
      this.renderMode = RenderMode.mixed});
}

class VectorTileLayer extends StatefulWidget {
  final VectorTileLayerOptions options;
  final MapState mapState;
  final Stream<Null> stream;

  const VectorTileLayer(this.options, this.mapState, this.stream);

  @override
  State<StatefulWidget> createState() {
    return _VectorTileLayerState();
  }
}

class _VectorTileLayerState extends DisposableState<VectorTileLayer>
    with WidgetsBindingObserver {
  StreamSubscription<Null>? _subscription;
  late final TileWidgets _tileWidgets;
  TilePairCache? _cache;

  MapState get _mapState => widget.mapState;
  double get _clampedZoom => _mapState.zoom.roundToDouble();
  double _paintZoomScale = 1.0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance?.addObserver(this);
    final cache = TilePairCache(widget.options);
    _cache = cache;
    _tileWidgets = TileWidgets(
        widget.options.tileProvider,
        () => _paintZoomScale,
        () => _mapState.zoom,
        widget.options.theme,
        cache);
    _subscription = widget.stream.listen((event) {
      _update();
    });
    _update();
  }

  @override
  void dispose() {
    super.dispose();
    WidgetsBinding.instance?.removeObserver(this);
    _cache?.dispose();
    _cache = null;
    _subscription?.cancel();
  }

  @override
  void didHaveMemoryPressure() {
    _cache?.releaseMemory();
  }

  @override
  Widget build(BuildContext context) {
    if (_tileWidgets.all.isEmpty) {
      return Container();
    }
    _updatePaintZoomScale();
    final tileWidgets = _tileWidgets.all.entries
        .map((entry) => _positionTile(entry.key, entry.value))
        .toList();
    return Stack(children: tileWidgets);
  }

  void _update() {
    if (disposed) {
      return;
    }
    final center = _mapState.center;
    final pixelBounds = _tiledPixelBounds(center);
    final tileRange = _pixelBoundsToTileRange(pixelBounds);
    final tiles = _expand(tileRange);
    _tileWidgets.update(tiles);
    setState(() {});
  }

  Bounds _tiledPixelBounds(LatLng center) {
    var scale = _mapState.getZoomScale(_mapState.zoom, _clampedZoom);
    var centerPoint = _mapState.project(center, _clampedZoom).floor();
    var halfSize = _mapState.size / (scale * 2);

    return Bounds(centerPoint - halfSize, centerPoint + halfSize);
  }

  Bounds _pixelBoundsToTileRange(Bounds bounds) => Bounds(
        bounds.min.unscaleBy(_tileSize).floor(),
        bounds.max.unscaleBy(_tileSize).ceil() - const CustomPoint(1, 1),
      );

  List<TileIdentity> _expand(Bounds range) {
    final zoom = _clampedZoom;
    final tiles = <TileIdentity>[];
    for (num x = range.min.x; x <= range.max.x; ++x) {
      for (num y = range.min.y; y <= range.max.y; ++y) {
        tiles.add(TileIdentity(zoom.toInt(), x.toInt(), y.toInt()));
      }
    }
    return tiles;
  }

  Widget _positionTile(TileIdentity tile, Widget tileWidget) {
    final zoomScale = _paintZoomScale;
    final pixelOrigin =
        _mapState.getNewPixelOrigin(_mapState.center, _mapState.zoom).round();
    final origin =
        _mapState.project(_mapState.unproject(pixelOrigin), _mapState.zoom);
    final translate = origin.multiplyBy(zoomScale) - pixelOrigin;
    final tilePosition =
        (tile.scaleBy(_tileSize) - origin).multiplyBy(zoomScale) + translate;
    return Positioned(
        key: Key('PositionedGridTile_${tile.z}_${tile.x}_${tile.y}'),
        top: tilePosition.y.toDouble(),
        left: tilePosition.x.toDouble(),
        width: (_tileSize.x * zoomScale),
        height: (_tileSize.y * zoomScale),
        child: tileWidget);
  }

  double _zoomScale(double mapZoom, double tileZoom) {
    final crs = _mapState.options.crs;
    return crs.scale(mapZoom) / crs.scale(tileZoom);
  }

  void _updatePaintZoomScale() {
    final tileZoom = _tileWidgets.all.keys.first.z;
    _paintZoomScale = _zoomScale(_mapState.zoom, tileZoom.toDouble());
  }
}

final _tileSize = CustomPoint(256, 256);
