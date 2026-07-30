# Data sources, services, and generated artifacts

SafeWalk-authored source code and documentation and the project raster assets I
contributed and identify below are MIT licensed. Input data, derived databases,
transit feeds, SDKs, services, map content, and Apple-supplied platform assets
are not relicensed by that grant. This ledger was checked against the linked
provider pages on 2026-07-30; terms can change and must be rechecked before any
artifact release.

The public source repository intentionally excludes raw incident records,
GraphML, Parquet, pickle/joblib files, GTFS archives, OSM extracts,
OpenTripPlanner graphs, and other generated data. Public access or a documented
download URL does not by itself establish redistribution rights.

## OpenStreetMap

The city generators and `fetch_boundaries.py` query OpenStreetMap through
OSMnx. The OpenTripPlanner scripts download OSM extracts through BBBike and
Geofabrik.

OpenStreetMap data is licensed under the Open Data Commons Open Database
License (ODbL). Public use or distribution requires OpenStreetMap contributor
attribution and notice of the ODbL; distribution of a covered derived database
can also trigger share-alike and database-access duties.

- Copyright, license, and attribution: https://www.openstreetmap.org/copyright
- ODbL 1.0: https://opendatacommons.org/licenses/odbl/1-0/
- OSMnx documentation: https://osmnx.readthedocs.io/
- BBBike extracts: https://download.bbbike.org/osm/bbbike/
- Geofabrik extracts: https://download.geofabrik.de/north-america/us/

Generated graphs can combine OSM-derived structure with incident or transit
data carrying different terms. Do not label a combined graph, pickle, or image
as MIT without an artifact-specific review.

## Incident datasets

| City | Exact generator source | Current terms and release boundary |
| --- | --- | --- |
| Atlanta | Atlanta Police Department Crime Statistics manual export: https://www.atlantapd.org/community/crime-statistics | The page provides downloads and permits users to create reports, but repository evidence does not establish an express dataset redistribution license. Record the exact input file and terms used. Atlanta-derived artifacts are not cleared for redistribution by this source release. |
| Boston | Analyze Boston, “Crime Incident Reports (August 2015 - To Date),” resource `b973d8cb-eeb2-4e7e-99da-c92938efc9c0` (“2023 to Present”): https://data.boston.gov/dataset/crime-incident-reports-august-2015-to-date-source-new-system | CKAN metadata identifies the Open Data Commons Public Domain Dedication and License (PDDL): https://opendatacommons.org/licenses/pddl/1-0/ . Preserve the exact resource ID and retrieval metadata. |
| Chicago | “Crimes - 2001 to Present,” dataset `ijzp-q8t2`: https://data.cityofchicago.org/d/ijzp-q8t2 | Metadata directs users to the City terms, describes records as preliminary and locations as approximate/block-level, and prohibits attempts to derive specific addresses. See https://www.chicago.gov/city/en/narr/foia/data_disclaimer.html . Preserve the source and disclaimer with any permitted derivative. |
| New York | NYPD Complaint Data Historic `qgea-i56i`: https://data.cityofnewyork.us/d/qgea-i56i and Current/YTD `5uac-w243`: https://data.cityofnewyork.us/d/5uac-w243 | NYC Open Data policy generally provides public datasets without a license requirement or use restriction, subject to portal and agency terms: https://opendata.cityofnewyork.us/overview/ . Do not describe the records as public domain; identify both dataset versions and any modifications. |
| Philadelphia | OpenDataPhilly “Crime Incidents,” Carto table `incidents_part1_part2`: https://opendataphilly.org/datasets/crime-incidents/ | The catalog identifies a City of Philadelphia license and City-specific terms/disclaimers rather than an unqualified open redistribution grant. Repository evidence does not clear Philadelphia-derived artifacts for redistribution. |
| Seattle | “SPD Crime Data: 2008-Present,” dataset `tazs-3rd5`: https://data.seattle.gov/d/tazs-3rd5 | Portal metadata identifies the dataset as Public Domain. The source also says only finalized reports are released, classifications can change, and locations are blurred to block level. See the portal terms: https://data.seattle.gov/stories/s/Terms-of-Use/6ukr-wvup/ . |

The scripts query mutable live endpoints and do not archive incident snapshots.
For an archival reproduction, retain the exact input snapshot where its terms
permit, retrieval timestamp, request/source URL, checksum, cutoff date, seed,
dependency lock, and a description of transformations. If a source's
redistribution rights are absent or unclear, retain only the metadata and keep
the input and derived artifact private pending review.

## Transit feeds

`backend/otp/scripts/download-gtfs.sh` uses these mutable feeds:

| Provider | URL used by the script | Terms boundary |
| --- | --- | --- |
| MBTA | `https://cdn.mbta.com/MBTA_GTFS.zip` | Official feed; review MBTA/MassDOT terms for the artifact being distributed. |
| CTA | Mobility Database mirror ID 389: `https://storage.googleapis.com/storage/v1/b/mdb-latest/o/us-illinois-chicago-transit-authority-cta-gtfs-389.zip?alt=media` | The mirror does not replace CTA's revocable, purpose-limited developer license, which restricts stand-alone data transfer: https://www.transitchicago.com/downloads/sch_data/developers_license_agreement.htm |
| MTA Subway | `https://rrgtfsfeeds.s3.amazonaws.com/gtfs_subway.zip` | Official MTA feed; review current MTA developer terms. |
| MTA LIRR | `https://rrgtfsfeeds.s3.amazonaws.com/gtfslirr.zip` | Same MTA terms boundary. |
| MTA Metro-North | `https://rrgtfsfeeds.s3.amazonaws.com/gtfsmnr.zip` | Same MTA terms boundary. |
| MTA Bronx bus | `https://rrgtfsfeeds.s3.amazonaws.com/gtfs_bx.zip` | Same MTA terms boundary. |
| MTA Brooklyn bus | `https://rrgtfsfeeds.s3.amazonaws.com/gtfs_b.zip` | Same MTA terms boundary. |
| MTA Manhattan bus | `https://rrgtfsfeeds.s3.amazonaws.com/gtfs_m.zip` | Same MTA terms boundary. |
| MTA Queens bus | `https://rrgtfsfeeds.s3.amazonaws.com/gtfs_q.zip` | Same MTA terms boundary. |
| MTA Staten Island bus | `https://rrgtfsfeeds.s3.amazonaws.com/gtfs_si.zip` | Same MTA terms boundary. |
| MARTA | `https://itsmarta.com/google_transit_feed/google_transit.zip` | Repository and linked provider evidence do not establish an express redistribution license. |
| SEPTA | Latest `gtfs_public.zip` resolved from `https://api.github.com/repos/septadev/GTFS/releases/latest` | The GitHub feed repository does not publish a repository license. Record the resolved release URL/version and review SEPTA terms. |
| King County Metro | Mobility Database mirror ID 1330: `https://storage.googleapis.com/storage/v1/b/mdb-latest/o/us-washington-king-county-metro-gtfs-1330.zip?alt=media` | King County publishes reuse conditions and a required attribution legend: https://kingcounty.gov/en/dept/metro/rider-tools/mobile-and-web-apps |
| Sound Transit | Mobility Database mirror ID 268: `https://storage.googleapis.com/storage/v1/b/mdb-latest/o/us-washington-sound-transit-gtfs-268.zip?alt=media` | Provider terms bind downstream recipients and impose use/redistribution conditions: https://www.soundtransit.org/help-contacts/business-information/open-transit-data-otd/transit-data-terms-use |

MobilityData licenses its catalog metadata as CC0, not the individual transit
feeds. See https://github.com/MobilityData/mobility-database-catalogs#license .
A GTFS format or public download is not itself a license.

The built OpenTripPlanner graph and any image containing it are not cleared for
redistribution by this source release. Before an artifact release, record every
resolved feed URL/version, retrieval timestamp, checksum, provider terms, and
required attribution; review the combined OSM/GTFS obligations.

## Hosted services and SDKs

- Mapbox Maps, Navigation, and APIs require a Mapbox account and compliance
  with Mapbox terms. The pinned SDK licenses state that the SDKs send limited
  de-identified location and usage data. They and their delivered map/style
  content are not MIT licensed by SafeWalk. See `THIRD_PARTY_NOTICES.md` and
  `PRIVACY.md`.
- Apple App Attest requires an Apple Developer team and matching application
  identifiers. Apple platform services retain their own terms.

## Bundled raster assets

The source tree contains:

- `frontend/SafeWalk/Assets.xcassets/AppIcon.appiconset/AppIcon (1) 1.png`
- `frontend/SafeWalk/Assets.xcassets/sourcePin.imageset/sourcePin.png`
- `frontend/SafeWalk/Assets.xcassets/destinationPin.imageset/destinationPin.png`

I confirm that I hold sufficient rights to redistribute and license these three
project assets, and I intentionally license them under the root MIT license.

Symbols referenced through Apple's `Image(systemName:)` APIs are supplied by
Apple's platforms and are not bundled or relicensed by SafeWalk.

## Release boundary

Do not commit or publish service credentials, `.netrc`, `.env`, private
`.xcconfig` files, generated download tokens, cloud-provider credentials, raw
source records, or generated routing artifacts.

Publishing this source tree is not clearance to publish an iOS binary,
backend/OpenTripPlanner container, generated dataset, graph, pickle, or
data-bearing image. Those artifacts require their own SBOM, provenance,
license/terms, attribution, and privacy review.
