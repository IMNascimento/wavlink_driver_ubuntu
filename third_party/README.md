# Third-party sources

## `evdi-1.15.0.tar.gz`

The **EVDI 1.15.0** source, bundled so `scripts/prepare-vendor-driver.sh` works
**offline** — no download needed to make the official Silicon Motion installer
build on kernel 6.8+.

- **Project:** EVDI (Extensible Virtual Display Interface) by DisplayLink (UK) Ltd.
- **Upstream:** <https://github.com/DisplayLink/evdi> (tag `v1.15.0`)
- **Version:** 1.15.0 (`module/dkms.conf` → `PACKAGE_VERSION=1.15.0`)
- **License:** open source and redistributable — the kernel module is **GPL-2.0**,
  the userspace library is **MIT** (see the `LICENSE` file inside the archive).

Only EVDI is redistributed here because it is open source. The closed-source
Silicon Motion daemon, firmware, and the vendor `.run` installer are **not**
included — download those from WAVLINK (see the main README).

To refresh this to a newer EVDI without using the bundle, pass the tag directly:

```bash
./scripts/prepare-vendor-driver.sh --run <installer.run> --evdi-tag v1.16.0
```
