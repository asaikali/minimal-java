# minimal-java
Experiments in building minimal, secure, and reproducible Java container runtimes.

## Resources

Background material on the topics this repo explores.

### Project Leyden & AOT (the `aot` image)

- **[Supercharge your JVM performance with Project Leyden and Spring Boot](https://www.youtube.com/watch?v=UqaSWiE076w)**
  — by **Moritz Halbritter** (Spring Boot engineering team). This recording is the
  Devoxx CERN delivery (2026-02-10), a newer run than the earlier Devoxx Belgium one,
  uploaded a few weeks after the talk.

  A practical walkthrough of how to cut JVM startup ~4x today using only stock
  **JDK 25 + Spring Boot 4** — no preview flags, no GraalVM, no custom JDK. This is
  the technique our `aot` image implements. Summary:

  - **Project Leyden** improves startup/warm-up by *shifting work earlier in time*
    (from runtime to build time) via a **training run** that observes the app, so
    class loading/linking (and, in JDK 25, JIT profiling) don't have to be redone on
    every boot. Leyden features ship in the mainline JDK — a Leyden-enabled JVM still
    behaves exactly like a normal JVM (reflection, serialization, etc. all work).
  - **AOT cache** (JEP 483, JDK 24; the successor to CDS) records class
    loading + linking during a training run and replays it at runtime. **JDK 25** adds
    *AOT method profiling* (warm-up improvement) and *command-line ergonomics*
    (JEP 514): a one-step `-XX:AOTCacheOutput=app.aot` to create the cache and
    `-XX:AOTCache=app.aot` to use it (the old separate `.aotconf` step is gone).
  - **Constraints:** the cache requires the *same JVM down to the point release* and
    same arch/OS; the classpath must be a **list of jars** (no directories, wildcards,
    or nested jars) and the deployment classpath must be a superset of the training
    one. If anything mismatches, the JVM simply **ignores the cache and starts
    normally** — it never crashes. (Jar timestamps must be preserved when copying.)
  - **Why Spring Boot needs the layered-jar extract:** Boot's fat jar uses nested jars
    via a custom classloader, which the AOT cache doesn't support — so you extract it
    with `-Djarmode=tools ... extract`. Extracting *alone* already shaves ~600ms by
    dropping the nested-jar classloader overhead.
  - **"Poor man's training run":** `-Dspring.context.exit=onRefresh` boots the context,
    instantiates singleton beans, then exits *before* the web server starts — enough to
    capture most class loading, and trivial to run at image-build time.
  - **Results (Pet Clinic, time-to-first-request):** fat jar ~3.0s → extracted ~2.4s →
    `+ AOT cache` ~0.96s (~3.1x) → `+ Spring AOT` ~0.75s (~4x). CPU time consumed during
    startup (what cloud providers bill) drops ~2.6x.
  - **Spring AOT** is separate from the JVM's AOT cache: it generates code for the bean
    arrangement (originally for GraalVM native image) and also speeds JVM startup; the
    trade-off is the bean arrangement is frozen at build time.
  - **For warm-up (peak throughput), not just startup,** you need a *real* training run
    that exercises hot paths with production-like load — harder to set up than the poor
    man's run. **What's next** in the Leyden prototype: ahead-of-time *code* compilation
    (store compiled machine code in the cache → ~0.45s startup / ~5x, with
    portability/instruction-set trade-offs), AOT for user-defined classloaders (may
    remove the extract step), AOT object caching with any GC (JDK 26), and modular
    Spring AOT.
