// backend/ts/src/routes/watch-page.ts

export function watchPageHtml(sessionId: string): string {
  return `<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>SafeWalk - Live Walk</title>
  <script src="https://api.mapbox.com/mapbox-gl-js/v3.25.0/mapbox-gl.js"></script>
  <link href="https://api.mapbox.com/mapbox-gl-js/v3.25.0/mapbox-gl.css" rel="stylesheet">
  <style>
    * { margin: 0; padding: 0; box-sizing: border-box; }
    body { font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', sans-serif; }
    #map { position: absolute; top: 0; bottom: 0; width: 100%; }
    #header {
      position: absolute; top: 0; left: 0; right: 0; z-index: 1;
      background: rgba(255,255,255,0.95); padding: 16px 20px;
      border-bottom: 1px solid #e0e0e0;
      backdrop-filter: blur(10px);
    }
    #header h1 { font-size: 16px; font-weight: 600; color: #1a1a1a; }
    #header p { font-size: 13px; color: #666; margin-top: 2px; }
    #banner {
      display: none; position: absolute; top: 50%; left: 50%; transform: translate(-50%, -50%);
      z-index: 2; background: rgba(255,255,255,0.97); padding: 32px 48px;
      border-radius: 16px; text-align: center;
      box-shadow: 0 4px 24px rgba(0,0,0,0.15);
      backdrop-filter: blur(10px);
    }
    #banner h2 { font-size: 20px; font-weight: 600; color: #1a1a1a; }
    #banner p { font-size: 14px; color: #666; margin-top: 8px; }
    .pulse-dot {
      width: 16px; height: 16px; background: #3b82f6; border: 3px solid #fff;
      border-radius: 50%; box-shadow: 0 0 0 rgba(59,130,246,0.4);
      animation: pulse 2s infinite;
    }
    @keyframes pulse {
      0% { box-shadow: 0 0 0 0 rgba(59,130,246,0.4); }
      70% { box-shadow: 0 0 0 12px rgba(59,130,246,0); }
      100% { box-shadow: 0 0 0 0 rgba(59,130,246,0); }
    }
  </style>
</head>
<body>
  <div id="header">
    <h1 id="title">Loading...</h1>
    <p id="subtitle"></p>
  </div>
  <div id="map"></div>
  <div id="banner">
    <h2 id="banner-title"></h2>
    <p id="banner-subtitle"></p>
  </div>
  <script>
    const SESSION_ID = '${sessionId}';
    let map, walkerMarker, walkerEl;

    async function init() {
      const resp = await fetch('/watch/' + SESSION_ID + '/data', {
        cache: 'no-store',
        credentials: 'omit',
      });
      if (!resp.ok) { document.getElementById('title').textContent = 'Session expired'; return; }
      const data = await resp.json();

      document.getElementById('title').textContent = 'Walking to ' + data.destinationName;
      mapboxgl.accessToken = data.mapboxToken;

      const coords = data.routeGeoJSON.features?.[0]?.geometry?.coordinates || [];
      const center = data.lastLocation
        ? [data.lastLocation.lon, data.lastLocation.lat]
        : (coords[0] || [-71.06, 42.36]);

      map = new mapboxgl.Map({
        container: 'map',
        style: 'mapbox://styles/mapbox/standard',
        center: center,
        zoom: 14,
      });

      map.on('load', function() {
        // Draw route line
        map.addSource('route', { type: 'geojson', data: data.routeGeoJSON });
        map.addLayer({
          id: 'route-line', type: 'line', source: 'route',
          paint: { 'line-color': '#3b82f6', 'line-width': 5, 'line-opacity': 0.8 },
          layout: { 'line-cap': 'round', 'line-join': 'round' },
        });

        // Walker dot
        walkerEl = document.createElement('div');
        walkerEl.className = 'pulse-dot';
        walkerMarker = new mapboxgl.Marker({ element: walkerEl })
          .setLngLat(center)
          .addTo(map);

        // Fit to route bounds
        if (coords.length > 1) {
          const bounds = coords.reduce(function(b, c) {
            return b.extend(c);
          }, new mapboxgl.LngLatBounds(coords[0], coords[0]));
          map.fitBounds(bounds, { padding: { top: 80, bottom: 40, left: 40, right: 40 } });
        }

        // Start SSE
        startEventStream();
      });
    }

    function startEventStream() {
      const source = new EventSource('/watch/' + SESSION_ID + '/events');

      source.onmessage = function(e) {
        const data = JSON.parse(e.data);

        if (data.type === 'ended') {
          source.close();
          walkerEl.style.animation = 'none';
          var title = data.reason === 'arrived' ? 'Arrived' : 'Walk ended';
          document.getElementById('banner-title').textContent = title;
          document.getElementById('banner-subtitle').textContent =
            data.reason === 'arrived' ? 'The walker has reached their destination.' : 'The walker ended navigation.';
          document.getElementById('banner').style.display = 'block';
          document.getElementById('subtitle').textContent = title;
          return;
        }

        if (Number.isFinite(data.lat) && Number.isFinite(data.lon)) {
          var lngLat = [data.lon, data.lat];
          walkerMarker.setLngLat(lngLat);
          map.panTo(lngLat, { duration: 1000 });
        }
      };

      source.onerror = function() {
        document.getElementById('subtitle').textContent = 'Connection lost. Reconnecting...';
      };
    }

    init();
  </script>
</body>
</html>`;
}
