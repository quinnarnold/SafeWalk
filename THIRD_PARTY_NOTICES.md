# Third-party notices

The root MIT license covers SafeWalk-authored source code and documentation
and the three project raster assets I contributed and identified in
`DATA_SOURCES.md`. I confirm that I have authority to redistribute and license
those project assets. The MIT grant does not relicense third-party packages,
services, public data, transit feeds, OpenStreetMap data, map content,
generated data-bearing artifacts, or Apple-supplied platform assets.

This source repository contains lockfiles and build instructions that refer to
third-party packages. It does not contain the downloaded Mapbox binary
packages, the OpenTripPlanner JAR, installed Python/JavaScript dependencies, or
generated routing data. Anyone distributing an application, container, or
other built artifact must inventory the exact artifact and satisfy every
applicable license, notice, source-code, relinking, account, and service-term
obligation.

Material runtime components include:

| Component | Version in this repository | License or terms |
| --- | --- | --- |
| igraph / python-igraph | 1.0.0 | GNU General Public License version 2; [upstream license](https://github.com/igraph/python-igraph/blob/1.0.0/LICENSE) |
| OpenTripPlanner | 2.6.0 | GNU Lesser General Public License version 3 or later, plus incorporated third-party notices; [upstream license](https://github.com/opentripplanner/OpenTripPlanner/blob/v2.6.0/LICENSE) |
| Mapbox Maps SDK for iOS | 11.20.0 | Mapbox Terms of Service and bundled third-party notices; [pinned license](https://github.com/mapbox/mapbox-maps-ios/blob/v11.20.0/LICENSE.md) |
| Mapbox Navigation SDK for iOS | 3.20.0 | Mapbox Terms of Service and bundled third-party notices; [pinned license](https://github.com/mapbox/mapbox-navigation-ios/blob/v3.20.0/LICENSE.md) |
| Swift Argument Parser | 1.7.0 | Apache License 2.0; [upstream license](https://github.com/apple/swift-argument-parser/blob/1.7.0/LICENSE.txt) |
| Turf for Swift | 4.0.0 | ISC License; [upstream license](https://github.com/mapbox/turf-swift/blob/v4.0.0/LICENSE.md) |

The committed Bun, Python, uv, and SwiftPM lockfiles are the source of truth for
the complete resolved dependency graph. Dependency names in this notice are
the material non-MIT or directly linked runtime components identified for the
source release; this file is not a substitute for an artifact-specific SBOM or
legal review.

OpenStreetMap, incident records, GTFS feeds, and generated data have separate
terms and release boundaries documented in `DATA_SOURCES.md`.
