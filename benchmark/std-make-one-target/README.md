# Native `std/make` one-target benchmark

This fixture measures Gerbil itself. It does not import Homebrew formula code or
a downstream build framework.

The workflow runs two controls against the exact SHA resolved from
`mighty-gerbils/gerbil@v0.19-staging`:

- `build.ss` compiles one module importing the precompiled `:std/interface` and
  then repeats the unchanged build three times.
- `run-scale.sh` generates eight independent Gerbil packages. Each package owns
  sixteen modules exporting hygienic `defrules` macros and one public interface.
  A separate application package imports all eight interfaces and expands all
  128 macros, while its measured build spec contains exactly one target.

The scale lane first seeds the package dependencies, invalidates only the final
aggregate, records its cold build, and then records three unchanged warm builds.
A valid warm receipt has zero compile jobs. The receipt classifies the warm p50
as below 13 seconds, within the previously observed 13–19 second band, or above
the configured budget. Runner identity, upstream ref and immutable SHA are
included so results from different Gerbil revisions are not conflated.
