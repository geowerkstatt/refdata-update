# Changelog

All notable changes to this project are documented in this file. The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## [Unreleased]

### Added

- The image `ghcr.io/geowerkstatt/refdata-update` keeps the reference data of an INTERLIS validation current. It fetches the sources listed in `/config/sources.yaml` into `/refdata`, once on start and then on a cron schedule (`REFDATA_UPDATE_SCHEDULE`, daily at 01:00 by default, in the time zone `TZ`). A source is either a single file or an archive whose listed entries are unpacked, each archive downloaded once per run. A file is only replaced once the new one is complete and looks like an INTERLIS transfer, so a failed download keeps the last state. The container reports itself unhealthy once no run has succeeded for `REFDATA_UPDATE_MAX_AGE_HOURS` (36 by default).

### Changed

- A destination must be a path that the `ilidata.xml` in `/refdata` lists. Any other destination is not fetched and counts as a failure, because ilivalidator reads reference data only through the ids of that index; without a readable `ilidata.xml` in `/refdata` a run stops.
