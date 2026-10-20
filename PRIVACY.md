# Privacy policy

Last updated: 2026-10-20

AquaRecover processes selected photos and videos on the device. The app does not
create an account and does not send media, edit settings, identifiers, usage
events, or diagnostics to an AquaRecover server.

## Media access

The app receives only media the user selects through Files or the operating
system's photo-library interface. On iOS, importing uses the system picker and
saving requests add-only Photos access. If a selected item is stored in iCloud,
Apple may download it before providing a local copy to the app.

## Storage

Exports and `.aquarecover.json` edit sidecars are stored in the app's documents
directory. An export can also be added to Photos when the user asks for it. The
files remain under the user's control and can be removed through the operating
system or by deleting the application container.

## Dive logbook

The dive logbook is stored only on the device and links photos and videos
without copying them. When the user asks it to find photos taken during a
dive, it requests photo-library access and reads capture times on the device.
Its map loads map tiles from OpenStreetMap, so the map
provider sees the viewed map area and the device's IP address. Logbook exports
(GPX, UDDF, GeoJSON) are saved only where the user chooses.

## Collection and sharing

AquaRecover does not include advertising, analytics, tracking, login, or cloud
processing. It does not sell or share personal data. The open-source packages
used by the app are listed in `THIRD_PARTY_NOTICES.md`; the shipped workflow
does not use them to collect data.

## Changes and contact

Material changes to this policy will be published with a new effective date in
the source repository and release notes. For a privacy question, contact the
maintainer through the address on the GitHub profile. Do not include private
media in a public issue.
