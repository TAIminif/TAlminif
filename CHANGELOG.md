# Changelog

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
