# 1-naive — the baseline

The simplest possible image, and the start of the tutorial.

- **`fat/`** — the Spring Boot fat jar on the **full** Eclipse Temurin JRE. No
  chisel, no layering, no AOT; it runs the nested-jar fat jar as root. This is what
  most people write by hand.

It exists to (a) teach the whole build → publish → containerize pipeline with the
least possible noise, and (b) be the baseline that Parts 2 and 3 measure against.

→ Explained in **[Part 1 — The pipeline & the naive fat jar](../../docs/1-pipeline.md)**.
