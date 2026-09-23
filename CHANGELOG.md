# Changelog

All notable changes to unifi_client are recorded here, in the shape of
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/). This project
follows [semantic versioning](https://semver.org/spec/v2.0.0.html);
before 1.0.0 the minor number carries what the major will later.

## [0.2.0] — 2026-09-23

The release that made the library a Protect client, not only a Network
one. Everything below landed after 0.1.2, which was cut before any of it.

### Added

- **Protect, the application.** The client core became application-aware,
  so a call is addressed to `:network` or `:protect` and the session is
  shared between them (#6). `spec.md` describes the library as both (#5).
- **Cameras.** `UnifiClient.Protect.Cameras` — the bootstrap and NVR
  documents, the camera list, and `snapshot/3` for a camera's current
  frame (#8).
- **Events.** `UnifiClient.Protect.Events` — listing, thumbnails and
  heatmaps (#9).
- **Video export.** `UnifiClient.Protect.Video.export/6`, with a timeout
  derived from the length of the clip being asked for rather than a fixed
  one (#10), then `export_many/6`: the same window from several cameras
  at once, in tasks **linked to the caller** so killing the caller kills
  the exports, with `channel` and `fps` options (#15).
- **The event stream.** `UnifiClient.Protect.Frame`, the binary packet
  decoder, and `UnifiClient.Protect.WebSocket`, which pairs each action
  packet with its data packet and resumes from `lastUpdateId` (#11, #12).

### Changed

- **A 401 renews the session instead of failing.** The API verbs and
  `download/4` re-authenticate once and retry when the console says the
  session has expired (#16) — and concurrent callers renew **once**
  between them rather than each starting their own login (#18).
- **The CSRF token is derived from the cookies** the console sets, rather
  than read from a header that is not always there (#19).

### Fixed

- The examples run again, and a GitLab CI gate keeps the suite honest
  (#20).

## [0.1.2] — 2025-12-05

The starting point of this changelog: a UniFi Network client with
sessions, the API verbs, and the documentation generated from them.

[0.2.0]: https://gitlab.conet.yarina.org/dco-tek/unifi_client/-/releases/v0.2.0
[0.1.2]: https://gitlab.conet.yarina.org/dco-tek/unifi_client/-/releases/v0.1.2
