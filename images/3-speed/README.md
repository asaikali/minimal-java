# 3-speed — make it faster

Two stacking ahead-of-time techniques that take startup from ~1.6 s to ~0.4 s,
without changing the app:

- **`jvm-aot/`** — the `app` layout plus a **JDK 25 AOT cache** (Project Leyden,
  JEP 514): a build-time training run records class loading/linking, replayed at
  runtime. Framework-agnostic; freezes nothing.
- **`spring-aot/`** — stacks **Spring AOT** (generated bean wiring) on top, consuming
  the Spring-AOT jar variant. The fastest image — but Spring AOT freezes the bean
  graph at build time (a trade-off the doc explains).

Both run a `java` training run at build time, so (unlike the other images) their
packaging executes per-arch.

→ Explained in **[Part 3 — A faster app](../../docs/3-speed.md)**.
