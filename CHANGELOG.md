# Changelog

## 0.2.2

- Preserve each numbered ANALOG GAIN/RANGE parameter's own description and lock flag after channel selection; retain selected numeric payloads and their processor encoding.
- Add a regression covering unchanged selection, cross-segment reordering and reduced channel lists, including file round trips.

## Final review reproducibility (0.2.1 baseline)

- Preserve fractional-rate and exact-time independent verification as a runnable script with 48 separately counted cases.
- Verify the public API from a separate MoonBit module using tracked fixtures and a generated source workspace.
- Run both checks in CI and the local verification entry point, and archive their reports with a locally checked source package.
- Generate the source archive after listing files; reject empty archives, missing reproduction files and excluded local state, and verify CRC and package metadata.
- Add an official-requirements and evidence map for final review; distinguish engineering evidence from pending registry publication and submission instructions.

## 0.2.1

- Correct decimal time crops and timestamp-to-frame lookup using the same frame-time grid, including high trial frame numbers.
- Accept fractional point/analog rates within exact REAL*4 rounding cells while rejecting incompatible sampling metadata.
- Honor caller limits through construction, JSON import and editing; enforce UTF-8 text budgets and JSON input byte limits.
- Add focused regressions for the reviewed failures, precision endpoints and expanded caller limits.
- Fix first-clone official fixture download instructions and describe GitHub source consumption through a local workspace.

## 0.2.0

- Intel, DEC/VAX and SGI/MIPS headers, parameters, events and frame read/write; explicit CLI encoding conversion.
- VAX low-exponent precision, target-format calibration and controlled conversion errors.
- Segmented point and analog metadata beyond255 channels, including numeric calibration and auxiliary channel selection.
- Historical127-entry text segments, spare metadata capacity and inactive zero-channel metadata.
- Standalone parameter files; merged legacy2/4-character and modern events with explicit timeline normalization.
- Preservation of opaque header bytes, parameter annotations and lock flags during supported edits.
- Independent official fixtures and511-point/511-analog compatibility harness with explicit malformed-fixture provenance.
- Public Header, Layout and Parameter records now include processor metadata; JSON defaults missing processor to Intel.

## 0.1.0

- Intel/IEEE headers, parameter records and typed arrays.
- Integer/floating frames, residual/camera masks and calibrated analog samples.
- Sequential, random and batched reads with limits.
- Full-file writing, EVENT metadata and raw extension preservation.
- Synchronized crop, channel selection, renaming and storage conversion.
- Bounded JSON exchange, CSV export, validation and online statistics.
- CLI, MoonBit example and independent Python interoperability checks.

See README for the exact support boundary.
