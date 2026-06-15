# Part 3 — A faster app

> **minimal-java tutorial** · [← Part 1](1-pipeline.md) · [← Part 2](2-size.md) · **Part 3** · [↑ Overview](../README.md)

[Part 2](2-size.md) made the image small and CVE-free, but it still starts in
~1.6 s. This part answers **"can it start faster?"** with two **stacking** ahead-of-time
techniques — a JVM feature and a Spring feature — that together take startup to ~0.4 s,
**about 4.8× faster than the `fat` baseline**. As before, the app doesn't change.

## jvm-aot — the JDK 25 AOT cache

[`images/3-speed/jvm-aot/Dockerfile`](../images/3-speed/jvm-aot) is the `app` layout plus a **JDK AOT
cache** (Project Leyden, JEP 514). A build-time **training run** boots the app, lets
Spring refresh the context, then exits — recording class loading + linking into
`app.aot`; the runtime replays it instead of redoing the work every boot:

```dockerfile
RUN ["java", "-XX:AOTCacheOutput=app.aot", "-Dspring.context.exit=onRefresh", "-jar", "application.jar"]
USER 10001:10001
ENTRYPOINT ["java", "-XX:AOTCache=app.aot", "-jar", "application.jar"]
```

It's framework-agnostic and **freezes nothing** about your app. One wrinkle for the
pipeline: unlike the jar, the AOT cache is **architecture-specific**, so this training
run executes on the target arch (a native arm64 runner, or QEMU emulation) — the only
place in the series where packaging runs Java per-arch. Cost: ~26 MB larger than `app`,
to buy the startup win.

## spring-aot — add Spring AOT on top

[`images/3-speed/spring-aot/Dockerfile`](../images/3-speed/spring-aot) stacks **Spring AOT** on the JDK
AOT cache. Spring AOT runs at the Maven build (`-Pspringaot`), generating bean-wiring
code — which is why [Part 1's artifact pipeline](1-pipeline.md#stage-2--publish-the-jar-as-an-oci-artifact)
publishes a **second** jar. This image consumes that Spring-AOT jar and adds
`-Dspring.aot.enabled=true` to both the training run and the runtime, so both
techniques compound. It's the fastest image in the series.

## Measure it — startup

```bash
./scripts/startup-times.sh
```

```
=== startup ===
fat: ... Started Application in 1.952 seconds (process running for 2.228)
app: ... Started Application in 1.627 seconds (process running for 1.79)
jvm-aot: ... Started Application in 0.535 seconds (process running for 0.687)
spring-aot: ... Started Application in 0.408 seconds (process running for 0.556)
```

Three techniques, three jumps:

- **`fat → app`** — exploding the fat jar into layers drops the nested-jar classloader
  overhead (the AOT cache *requires* this — see the Resources note below).
- **`app → jvm-aot`** — the JDK 25 AOT cache replays recorded class loading/linking,
  taking startup from **~1.6 s to ~0.5 s**.
- **`jvm-aot → spring-aot`** — Spring AOT replaces reflective bean wiring with generated
  code, shaving it to **~0.4 s — about 4.8× faster than `fat`**. On a larger bean graph
  the gap is wider.

## JVM AOT vs Spring AOT

The `jvm-aot` and `spring-aot` images both cut startup, but with two **different**
techniques that stack — and Spring AOT carries a trade-off worth understanding
before you reach for it.

- **JVM AOT** (`jvm-aot`) is a **JVM** feature: the Project Leyden **AOT cache**
  (JEP 514). A build-time *training run* records class loading + linking (and, on
  JDK 25, method profiling), and the runtime replays it instead of redoing the work
  on every boot. It's framework-agnostic and leaves your application code and bean
  graph exactly as they are — **nothing about your app is frozen.**
- **Spring AOT** (`spring-aot`) is a **Spring** feature: at build time it generates
  Java code for the bean wiring (replacing reflection-based context setup) and
  **freezes the bean arrangement** — *which beans exist and how they're wired is
  decided at build time and cannot change at runtime.*

`spring-aot` uses **both**, applied in this order — which is why it's the fastest
image:

1. **Spring AOT runs first**, at the Maven build (`-Pspringaot` → `process-aot`),
   baking the generated bean-wiring code into the jar.
2. **Then the JVM AOT cache training run** boots that *already-Spring-AOT-processed*
   app (`-Dspring.aot.enabled=true -Dspring.context.exit=onRefresh`) and records its
   class loading/linking into `app.aot`.
3. **At runtime** the JVM replays `app.aot` *and* Spring uses the generated wiring.

Because the training run observes the Spring-AOT-optimized startup, the Leyden cache
captures *that* leaner path — so the two compound rather than just coexist. (The
`jvm-aot` image is the same minus step 1: no Spring AOT, so its training run records
the ordinary reflection-based startup.)

But that frozen bean arrangement is the catch. The line to keep in mind:

| Decided at **build time** — frozen by Spring AOT | Still resolved at **runtime** |
| --- | --- |
| *Which beans exist / how they're wired* — `@Profile`, `@ConditionalOnProperty`, autoconfiguration conditions | *Config values* — `application.yml`, `application-{profile}.yml`, env vars, `@Value`, `@ConfigurationProperties` |

### A concrete example

Say a `SignupService` sends email, wired differently per environment — a stub in
dev/test so you never send real mail, the real client in prod:

```java
@Profile("!prod")   // dev, test, CI
@Bean EmailSender loggingEmailSender() { return new LoggingEmailSender(); }   // just logs

@Profile("prod")
@Bean EmailSender sesEmailSender()     { return new SesEmailSender(...); }    // real AWS SES
```

**With `jvm-aot` (or no AOT):** you ship one image and pick the bean at startup with
`--spring.profiles.active=prod`. The Leyden cache never touches this — profiles stay
fully dynamic.

**With `spring-aot`:** `process-aot` evaluates `@Profile` at **build time**. If the
build ran with the default profile, the generated context contains *only*
`loggingEmailSender`; `sesEmailSender` was never generated. Run that image in prod
and either it fails at startup (no prod `EmailSender`) or — worse — **the logging
stub silently "sends" production email to a log file.** Activating `prod` at runtime
can't fix it: the bean simply doesn't exist. The same goes for any conditional bean —
a prod-only Redis cache or metrics exporter, or anything behind
`@ConditionalOnProperty(...enabled)` — the decision is made once, at build time.

Note what *still* works: because property values aren't frozen, changing
`spring.datasource.url` to point `jvm-aot`/`spring-aot` at Postgres vs MySQL is fine
under AOT — the `DataSource` bean exists either way and reads the URL at runtime.
It's bean *selection* by profile/condition that's frozen, not configuration values.

### Living with it

- **Bake in the right profile:** tell AOT which profiles to evaluate at build time —
  `<profiles>prod</profiles>` on the `process-aot` execution (see [`pom.xml`](../pom.xml)) —
  or build a separate artifact per profile.
- **Design AOT-friendly:** prefer one bean whose *behavior* varies by a runtime
  **property** over two beans gated by `@Profile`; property values aren't frozen.
- **Or just use `jvm-aot`:** most of the startup win, none of the build-time freezing
  — the safe choice when the bean graph needs to stay dynamic.

This repo's app has no profiles or conditional beans, so `spring-aot` is a clean win
here; the trade-off only shows up once an app wires beans by profile or condition.

## Deploy the result to Kubernetes

[`k8s/deployment.yaml`](../k8s/deployment.yaml) runs `minimal-java/spring-aot:local` on
Docker Desktop's Kubernetes, carrying the same hardening as [Part 2](2-size.md#run-it--now-hardened)
(non-root, read-only root filesystem, all capabilities dropped) plus `httpGet` probes —
there's no shell in the image to run an exec health check. It uses the image you built
locally (`imagePullPolicy: IfNotPresent`, no registry needed):

```bash
kubectl apply -f k8s/deployment.yaml
curl localhost:30080                  # -> a random quote
kubectl delete -f k8s/deployment.yaml
```

That's the whole journey: a Spring Boot app taken from a naive 165 MB / ~2 s container
to a ~139 MB, zero-OS-CVE, hardened, ~0.4 s one — each step built and published through
a real, digest-pinned pipeline.

## Clean up

Remove everything the tutorial created locally (images, containers, staged jars):

```bash
./scripts/clean.sh
```

## Resources — Project Leyden & AOT

<details>
<summary>Background talk + a summary of how the JVM AOT cache and Spring AOT work</summary>

- **[Supercharge your JVM performance with Project Leyden and Spring Boot](https://www.youtube.com/watch?v=UqaSWiE076w)**
  — by **Moritz Halbritter** (Spring Boot engineering team). This recording is the
  Devoxx CERN delivery (2026-02-10), a newer run than the earlier Devoxx Belgium one,
  uploaded a few weeks after the talk.

  A practical walkthrough of how to cut JVM startup ~4x today using only stock
  **JDK 25 + Spring Boot 4** — no preview flags, no GraalVM, no custom JDK. This is
  the technique our `jvm-aot` image implements. Summary:

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
    trade-off is the bean arrangement is frozen at build time. This is what the
    **`spring-aot`** image adds on top of `jvm-aot` (the `-Pspringaot` Maven profile runs
    `process-aot` at build time, and the image runs with `-Dspring.aot.enabled=true`).
  - **For warm-up (peak throughput), not just startup,** you need a *real* training run
    that exercises hot paths with production-like load — harder to set up than the poor
    man's run. **What's next** in the Leyden prototype: ahead-of-time *code* compilation
    (store compiled machine code in the cache → ~0.45s startup / ~5x, with
    portability/instruction-set trade-offs), AOT for user-defined classloaders (may
    remove the extract step), AOT object caching with any GC (JDK 26), and modular
    Spring AOT.

</details>

---

> That's the end of the tutorial. [↑ Back to the overview](../README.md) · [← Part 1](1-pipeline.md) · [← Part 2](2-size.md)
