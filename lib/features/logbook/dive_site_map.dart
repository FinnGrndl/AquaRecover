import 'package:flutter/cupertino.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../../core/logbook/dive_log.dart';
import '../../shared/reduce_motion.dart';
import '../timeline/timeline_theme.dart';

/// Builds the site map; widget tests pass a stand-in since they have no
/// network for tiles.
typedef DiveMapBuilder =
    Widget Function(
      BuildContext context,
      List<DiveSite> sites,
      ValueChanged<DiveSite> onSiteTap,
    );

/// OpenStreetMap with a pin per dive site. Tiles are the logbook's only
/// network traffic.
class DiveSiteMap extends StatelessWidget {
  const DiveSiteMap({super.key, required this.sites, required this.onSiteTap});

  final List<DiveSite> sites;
  final ValueChanged<DiveSite> onSiteTap;

  static Widget builder(
    BuildContext context,
    List<DiveSite> sites,
    ValueChanged<DiveSite> onSiteTap,
  ) => DiveSiteMap(sites: sites, onSiteTap: onSiteTap);

  @override
  Widget build(BuildContext context) {
    final points = [for (final s in sites) LatLng(s.latitude!, s.longitude!)];
    final reduceMotion = reduceMotionOf(context);
    return Stack(
      children: [
        FlutterMap(
          options: MapOptions(
            initialCenter: points.length == 1
                ? points.first
                : const LatLng(20, 0),
            initialZoom: points.length == 1 ? 10 : 2,
            initialCameraFit: points.length > 1
                ? CameraFit.coordinates(
                    coordinates: points,
                    padding: const EdgeInsets.all(56),
                    maxZoom: 12,
                  )
                : null,
            interactionOptions: InteractionOptions(
              flags: reduceMotion
                  ? InteractiveFlag.all & ~InteractiveFlag.flingAnimation
                  : InteractiveFlag.all,
            ),
          ),
          children: [
            TileLayer(
              urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
              userAgentPackageName: 'io.github.finngrndl.aquarecover',
            ),
            MarkerLayer(
              markers: [
                for (final site in sites)
                  Marker(
                    point: LatLng(site.latitude!, site.longitude!),
                    width: 44,
                    height: 44,
                    child: Semantics(
                      button: true,
                      label: 'Dive site ${site.name}',
                      excludeSemantics: true,
                      child: GestureDetector(
                        onTap: () => onSiteTap(site),
                        child: const Icon(
                          CupertinoIcons.location_solid,
                          color: TimelineColors.accent,
                          size: 34,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ],
        ),
        Positioned(
          right: 0,
          bottom: 0,
          child: SafeArea(
            child: Container(
              margin: const EdgeInsets.all(8),
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: CupertinoColors.black.withValues(alpha: .7),
                borderRadius: BorderRadius.circular(6),
              ),
              child: const Text(
                '© OpenStreetMap contributors',
                style: TextStyle(color: CupertinoColors.white, fontSize: 11),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
