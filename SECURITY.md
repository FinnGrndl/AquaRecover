# Security policy

## Supported versions

Security fixes are made on the current `main` branch and included in the next
release. Older source snapshots are not maintained separately.

## Reporting a vulnerability

Do not open a public issue for a vulnerability that could expose user media,
local files, credentials, or device resources. Use GitHub's private
vulnerability reporting for this repository. If that option is unavailable,
contact the maintainer through the address listed on the GitHub profile.

Include the affected commit or version, platform, reproduction steps, impact,
and any suggested mitigation. Do not attach private photos or videos; use a
small synthetic fixture when possible.

The maintainer will confirm receipt, assess the report, and coordinate a fix as
time permits. Please allow a reasonable period for a patch before publishing
technical details.

## Scope

Useful reports include unsafe file handling, path traversal, unintended network
traffic, permission misuse, denial of service through crafted media, native
decoder issues specific to AquaRecover, and leakage of media or metadata.
Vulnerabilities in Flutter, Apple frameworks, Android frameworks, or a package
should also be reported to that upstream project.
