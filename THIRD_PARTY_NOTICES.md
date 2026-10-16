# Sources and third-party notices

MoonC3D implementation is MIT licensed; see LICENSE.

- [C3D.org](https://www.c3d.org/) and [C3D Technical User Guide](https://www.c3d.org/docs/C3D_User_Guide.pdf): wire-format reference. The guide is not bundled, copied into implementation or relicensed.
- [moonbitlang/core](https://github.com/moonbitlang/core) / [moonbitlang/moon](https://github.com/moonbitlang/moon): Apache-2.0 for those open-source repositories. Installed through MoonBit, not vendored. Compiler licensing follows its distribution terms.
- [py-c3d 0.6.0](https://github.com/EmbodiedCognition/py-c3d): MIT, independently installed test encoder/decoder. No upstream implementation source copied into MoonC3D.
- [NumPy 2.2.6](https://github.com/numpy/numpy): BSD-3-Clause and bundled third-party notices; numerical test dependency, not vendored.

Synthetic fixtures are generated for this project. The compatibility harness downloads official C3D.org Sample01 and Sample02 archives into ignored .tools/compatibility, verifies pinned SHA-256 hashes, and retains supplied readme files locally for provenance. Third-party trial files are not committed, bundled, or relicensed under MIT. Source: https://www.c3d.org/sampledata.html . Identity records, credentials and proprietary trials are not included.
