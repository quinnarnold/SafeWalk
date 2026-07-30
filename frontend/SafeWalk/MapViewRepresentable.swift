import SwiftUI
import UIKit
import MapboxMaps
import CoreLocation
import Turf
internal import MapKit

enum MarkerMode { case idle, source, destination }

struct MapViewRepresentable: UIViewRepresentable {
    var featureCollection: FeatureCollection?
    @Binding var sourceCoord: CLLocationCoordinate2D?
    @Binding var destCoord:   CLLocationCoordinate2D?
    @Binding var mode: MarkerMode
    @Binding var selectedCity: String
    var droppedPinCoord: CLLocationCoordinate2D?
    var selectedTransitItinerary: TransitItinerary?
    var onLongPress: ((CLLocationCoordinate2D) -> Void)?
    var onPOITap: ((String, CLLocationCoordinate2D, String?) -> Void)?


    func makeUIView(context: Context) -> MapView {
        let initOptions = MapInitOptions(
            cameraOptions: CameraOptions(
                center: CLLocationCoordinate2D(latitude: 42.36, longitude: -71.06),
                zoom: 12
            ),
            styleURI: AppConfiguration.mapStyleURI
        )

        let mapView = MapView(frame: .zero, mapInitOptions: initOptions)

        var ornaments = mapView.ornaments.options
        ornaments.compass.position = .topTrailing
        ornaments.logo.position = .bottomLeading
        ornaments.attributionButton.position = .bottomLeading
        ornaments.logo.margins = CGPoint(x: 12, y: 8)
        ornaments.attributionButton.margins = CGPoint(x: 12, y: 36)
        ornaments.scaleBar.position = .topLeading
        mapView.ornaments.options = ornaments

        let puckConfig = Puck2DConfiguration.makeDefault(showBearing: true)
        mapView.location.options.puckType = .puck2D(puckConfig)
        mapView.location.options.puckBearing = .heading
        mapView.location.options.puckBearingEnabled = true

        var locationToken: AnyCancelable?
        locationToken = mapView.location.onLocationChange.observeNext { [weak mapView] locations in
            guard let mapView, let location = locations.last else { return }
            mapView.camera.ease(
                to: CameraOptions(center: location.coordinate, zoom: 12),
                duration: 0.5
            )
            locationToken?.cancel()
            locationToken = nil
        }
        if let token = locationToken {
            token.store(in: &context.coordinator.cancelables)
        }

        let tap = UITapGestureRecognizer(target: context.coordinator,
                                         action: #selector(Coordinator.handleTap(_:)))
        tap.delegate = context.coordinator
        mapView.addGestureRecognizer(tap)

        let longPress = UILongPressGestureRecognizer(target: context.coordinator,
                                                      action: #selector(Coordinator.handleLongPress(_:)))
        longPress.minimumPressDuration = 0.5
        mapView.addGestureRecognizer(longPress)

        mapView.mapboxMap.onStyleLoaded.observeNext { [weak mapView] _ in
            guard let mapView else { return }

            func resizedImage(named name: String, width: CGFloat) -> UIImage? {
                guard let image = UIImage(named: name) else { return nil }
                let scale = width / max(image.size.width, image.size.height)
                let newSize = CGSize(width: image.size.width * scale, height: image.size.height * scale)
                let renderer = UIGraphicsImageRenderer(size: newSize)
                return renderer.image { _ in
                    image.draw(in: CGRect(origin: .zero, size: newSize))
                }
            }

            do {
                if let smallSrc = resizedImage(named: "sourcePin", width: 48) {
                    try mapView.mapboxMap.addImage(smallSrc, id: "src-pin")
                }
                if let smallDst = resizedImage(named: "destinationPin", width: 48) {
                    try mapView.mapboxMap.addImage(smallDst, id: "dst-pin")
                }
                if let droppedPin = resizedImage(named: "destinationPin", width: 48) {
                    try mapView.mapboxMap.addImage(droppedPin, id: "dropped-pin")
                }
            } catch {
                #if DEBUG
                print("Unable to add map image.")
                #endif
            }

        }.store(in: &context.coordinator.cancelables)


        context.coordinator.mapView = mapView
        return mapView
    }

    func updateUIView(_ mapView: MapView, context: Context) {
        guard mapView.mapboxMap.isStyleLoaded else { return }

        if let fc = featureCollection {
            do {
                if !(try mapView.mapboxMap.sourceExists(withId: "route-source")) {
                    var source = GeoJSONSource(id: "route-source")
                    source.data = .featureCollection(fc)
                    try mapView.mapboxMap.addSource(source)
                    try addRouteLayers(to: mapView)
                } else {
                    try mapView.mapboxMap.updateGeoJSONSource(
                        withId: "route-source",
                        geoJSON: .featureCollection(fc)
                    )
                }
            } catch {
                #if DEBUG
                print("Unable to update map route.")
                #endif
            }
        } else {
            removeWalkingRouteLayers(from: mapView)
        }

        if let src = sourceCoord {
            addMarker(to: mapView, coord: src, id: "src", icon: "src-pin")
        } else {
            removeMarker(from: mapView, id: "src")
        }
        if let dst = destCoord {
            addMarker(to: mapView, coord: dst, id: "dst", icon: "dst-pin")
        } else {
            removeMarker(from: mapView, id: "dst")
        }

        if let dropped = droppedPinCoord {
            addMarker(to: mapView, coord: dropped, id: "dropped", icon: "dropped-pin")
        } else {
            removeMarker(from: mapView, id: "dropped")
        }

        if let itinerary = selectedTransitItinerary {
            renderTransitItinerary(itinerary, on: mapView)
        } else {
            removeTransitLayers(from: mapView)
        }
    }

    private func addRouteLayers(to mapView: MapView) throws {
        var moderateGlow = LineLayer(id: "moderate-glow", source: "route-source")
        moderateGlow.slot = "middle"
        moderateGlow.filter = Exp(.eq) { Exp(.get) { "type" }; "moderate" }
        moderateGlow.lineColor = .constant(StyleColor(UIColor.systemBlue.withAlphaComponent(0.30)))
        moderateGlow.lineWidth = .constant(10)
        moderateGlow.lineCap   = .constant(.round)
        moderateGlow.lineJoin  = .constant(.round)
        try mapView.mapboxMap.addLayer(moderateGlow)

        var moderate = LineLayer(id: "moderate-layer", source: "route-source")
        moderate.slot = "middle"
        moderate.filter = Exp(.eq) { Exp(.get) { "type" }; "moderate" }
        moderate.lineColor = .constant(StyleColor(.systemBlue))
        moderate.lineWidth = .constant(5)
        moderate.lineCap   = .constant(.round)
        moderate.lineJoin  = .constant(.round)
        try mapView.mapboxMap.addLayer(moderate)

        var safest = LineLayer(id: "safest-layer", source: "route-source")
        safest.slot = "middle"
        safest.filter = Exp(.eq) { Exp(.get) { "type" }; "safest" }
        safest.lineColor = .constant(StyleColor(.systemOrange))
        safest.lineWidth = .constant(4)
        safest.lineCap   = .constant(.round)
        safest.lineJoin  = .constant(.round)
        try mapView.mapboxMap.addLayer(safest)

        var shortest = LineLayer(id: "shortest-layer", source: "route-source")
        shortest.slot = "middle"
        shortest.filter = Exp(.eq) { Exp(.get) { "type" }; "shortest" }
        shortest.lineColor = .constant(StyleColor(.systemRed))
        shortest.lineWidth = .constant(4)
        shortest.lineDasharray = .constant([2, 2])
        shortest.lineCap   = .constant(.round)
        shortest.lineJoin  = .constant(.round)
        try mapView.mapboxMap.addLayer(shortest)
    }

    private func renderTransitItinerary(_ itinerary: TransitItinerary, on mapView: MapView) {
        removeTransitLayers(from: mapView)

        for (index, leg) in itinerary.legs.enumerated() {
            let sourceId = "transit-leg-\(index)"
            let layerId = "transit-leg-layer-\(index)"
            let coordinates = leg.coordinates

            guard coordinates.count >= 2 else { continue }

            var source = GeoJSONSource(id: sourceId)
            source.data = .geometry(.lineString(LineString(coordinates)))

            var layer = LineLayer(id: layerId, source: sourceId)
            layer.lineWidth = .constant(leg.isWalk ? 4 : 6)

            if leg.isWalk {
                switch leg.safetyType {
                case "moderate":
                    layer.lineColor = .constant(StyleColor(.systemBlue))
                case "safest":
                    layer.lineColor = .constant(StyleColor(.systemOrange))
                default:
                    layer.lineColor = .constant(StyleColor(.systemGray))
                }
                layer.lineDasharray = .constant([2, 1])
            } else {
                if let hex = leg.route?.color, let color = UIColor(hex: hex) {
                    layer.lineColor = .constant(StyleColor(color))
                } else {
                    layer.lineColor = .constant(StyleColor(.systemPurple))
                }
            }

            try? mapView.mapboxMap.addSource(source)
            try? mapView.mapboxMap.addLayer(layer)
        }
    }

    private func removeWalkingRouteLayers(from mapView: MapView) {
        let layerIds = ["moderate-glow", "moderate-layer", "safest-layer", "shortest-layer"]
        for id in layerIds {
            try? mapView.mapboxMap.removeLayer(withId: id)
        }
        try? mapView.mapboxMap.removeSource(withId: "route-source")
    }

    private func removeTransitLayers(from mapView: MapView) {
        for i in 0..<20 {
            let layerId = "transit-leg-layer-\(i)"
            let sourceId = "transit-leg-\(i)"
            try? mapView.mapboxMap.removeLayer(withId: layerId)
            try? mapView.mapboxMap.removeSource(withId: sourceId)
        }
    }

    private func addMarker(to mapView: MapView, coord: CLLocationCoordinate2D, id: String, icon: String) {
        do {
            let feature = Feature(geometry: .point(Point(coord)))
            var source = GeoJSONSource(id: id)
            source.data = .feature(feature)

            if try mapView.mapboxMap.sourceExists(withId: id) {
                try mapView.mapboxMap.updateGeoJSONSource(withId: id, geoJSON: .feature(feature))
            } else {
                try mapView.mapboxMap.addSource(source)
                var layer = SymbolLayer(id: "\(id)-layer", source: id)
                layer.slot = "top"
                layer.iconImage = .constant(.name(icon))
                layer.iconAllowOverlap = .constant(true)

                layer.iconSize = .expression(
                    Exp(.interpolate) {
                        Exp(.linear)
                        Exp(.zoom)
                        5; 0.25   // at zoom level 5 → 25% scale
                        10; 0.5   // at zoom level 10 → 50% scale
                        14; 0.8   // at zoom level 14 → 80% scale
                        18; 1.0   // at zoom level 18 → full size
                        22; 1.5   // optional: slightly bigger at very close zoom
                    }
                )

                try mapView.mapboxMap.addLayer(layer)

            }
        } catch {
            #if DEBUG
            print("Unable to add map marker.")
            #endif
        }
    }



    private func removeMarker(from mapView: MapView, id: String) {
        do {
            if try mapView.mapboxMap.layerExists(withId: "\(id)-layer") {
                try mapView.mapboxMap.removeLayer(withId: "\(id)-layer")
            }
            if try mapView.mapboxMap.sourceExists(withId: id) {
                try mapView.mapboxMap.removeSource(withId: id)
            }
        } catch {
            #if DEBUG
            print("Unable to remove map marker.")
            #endif
        }
    }

    func makeCoordinator() -> Coordinator {
        let c = Coordinator(self)
        CoordinatorHolder.shared.coordinator = c
        return c
    }

    class Coordinator: NSObject, UIGestureRecognizerDelegate {
        var parent: MapViewRepresentable
        weak var mapView: MapView?
        var cancelables = Set<AnyCancelable>()
        var lastCity: String?

        init(_ parent: MapViewRepresentable) { self.parent = parent }

        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
            return true
        }

        @objc func handleTap(_ gesture: UITapGestureRecognizer) {
            guard let mapView else { return }
            let point = gesture.location(in: mapView)
            let coord = mapView.mapboxMap.coordinate(for: point)

            switch parent.mode {
            case .source:
                parent.sourceCoord = coord
                parent.mode = .idle
                return
            case .destination:
                parent.destCoord = coord
                parent.mode = .idle
                return
            case .idle:
                break
            }

            queryMapboxPOIAtPoint(point, in: mapView)
        }

        /// Query Mapbox for POI features at the tap point, then enrich with MapKit
        private func queryMapboxPOIAtPoint(_ point: CGPoint, in mapView: MapView) {
            let options = RenderedQueryOptions(layerIds: ["poi-label"], filter: nil)

            mapView.mapboxMap.queryRenderedFeatures(with: point, options: options) { [weak self] result in
                guard let self = self else { return }

                switch result {
                case .success(let features):
                    guard let feature = features.first else {
                        #if DEBUG
                        print("No POI label at tap point")
                        #endif
                        return
                    }

                    let properties = feature.queriedFeature.feature.properties
                    let poiName = properties?["name"]??.string ?? "Unknown Place"
                    let maki = properties?["maki"]??.string

                    guard case .point(let point) = feature.queriedFeature.feature.geometry else {
                        #if DEBUG
                        print("POI feature has no point geometry")
                        #endif
                        return
                    }
                    let poiCoord = point.coordinates

                    self.enrichPOIWithMapKit(name: poiName, coordinate: poiCoord, mapboxCategory: maki)

                case .failure(let error):
                    #if DEBUG
                    print("Mapbox feature query failed.")
                    #endif
                }
            }
        }

        /// Use MapKit to find additional details (phone, website) for the POI
        private func enrichPOIWithMapKit(name: String, coordinate: CLLocationCoordinate2D, mapboxCategory: String?) {
            let region = MKCoordinateRegion(
                center: coordinate,
                latitudinalMeters: 100,
                longitudinalMeters: 100
            )

            let poiRequest = MKLocalPointsOfInterestRequest(coordinateRegion: region)
            poiRequest.pointOfInterestFilter = .includingAll

            let search = MKLocalSearch(request: poiRequest)
            search.start { [weak self] response, error in
                guard let self = self else { return }

                var category: String? = mapboxCategory

                if let response = response {
                    let tapLocation = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
                    var bestMatch: MKMapItem? = nil
                    var bestDistance: CLLocationDistance = .infinity

                    for mapItem in response.mapItems {
                        guard let itemLocation = mapItem.placemark.location else { continue }
                        let distance = tapLocation.distance(from: itemLocation)

                        if let itemName = mapItem.name,
                           itemName.lowercased().contains(name.lowercased()) || name.lowercased().contains(itemName.lowercased()),
                           distance < 50 {
                            bestMatch = mapItem
                            break
                        }

                        if distance < bestDistance && distance < 50 {
                            bestDistance = distance
                            bestMatch = mapItem
                        }
                    }

                    if let match = bestMatch, let poiCategory = match.pointOfInterestCategory {
                        category = poiCategory.rawValue
                            .replacingOccurrences(of: "MKPOICategory", with: "")
                            .replacingOccurrences(of: "([a-z])([A-Z])", with: "$1 $2", options: .regularExpression)
                    }
                }

                DispatchQueue.main.async {
                    self.parent.onPOITap?(name, coordinate, category)
                }
            }
        }

        @objc func handleLongPress(_ gesture: UILongPressGestureRecognizer) {
            guard gesture.state == .began else { return }
            guard let mapView else { return }
            let point = gesture.location(in: mapView)
            let coord = mapView.mapboxMap.coordinate(for: point)
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            parent.onLongPress?(coord)
        }

        /// Converts a map coordinate to a screen point for UI positioning
        func screenPoint(for coordinate: CLLocationCoordinate2D) -> CGPoint? {
            mapView?.mapboxMap.point(for: coordinate)
        }

        /// Returns the user's current location if available
        var userLocation: CLLocationCoordinate2D? {
            mapView?.location.latestLocation?.coordinate
        }

        func recenterOnUser() {
            guard let mapView,
                  let coord = mapView.location.latestLocation?.coordinate else { return }
            mapView.camera.ease(to: CameraOptions(center: coord, zoom: 14), duration: 1.0)
        }
        func recenter(to coord: CLLocationCoordinate2D, zoom: Double = 16.5) {
            mapView?.camera.ease(to: CameraOptions(center: coord, zoom: zoom), duration: 0.9)
        }

        /// Fits the camera to show all provided coordinates with padding
        func fitToBounds(coordinates: [CLLocationCoordinate2D], padding: UIEdgeInsets = UIEdgeInsets(top: 80, left: 40, bottom: 120, right: 40)) {
            guard let mapView, coordinates.count >= 2 else {
                // If only one coordinate, just recenter on it
                if let first = coordinates.first {
                    recenter(to: first, zoom: 15)
                }
                return
            }

            var minLat = coordinates[0].latitude
            var maxLat = coordinates[0].latitude
            var minLon = coordinates[0].longitude
            var maxLon = coordinates[0].longitude

            for coord in coordinates {
                minLat = min(minLat, coord.latitude)
                maxLat = max(maxLat, coord.latitude)
                minLon = min(minLon, coord.longitude)
                maxLon = max(maxLon, coord.longitude)
            }

            let sw = CLLocationCoordinate2D(latitude: minLat, longitude: minLon)
            let ne = CLLocationCoordinate2D(latitude: maxLat, longitude: maxLon)
            let bounds = CoordinateBounds(southwest: sw, northeast: ne)

            let cameraOptions = mapView.mapboxMap.camera(
                for: bounds,
                padding: padding,
                bearing: nil,
                pitch: nil,
                maxZoom: nil,
                offset: .zero
            )

            mapView.camera.ease(to: cameraOptions, duration: 0.9)
        }
    }
}

extension MapViewRepresentable {
    class CoordinatorHolder {
        static var shared = CoordinatorHolder()
        weak var coordinator: Coordinator?
    }
}
