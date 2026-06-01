# .github/workflows/

CI/CD. One fast test gate, the three decoupled image pipelines, and Renovate. The
three pipelines hand off through ghcr, every input pinned by digest.

| Workflow | Triggers | What it does |
| -------- | -------- | ------------ |
| **`build.yml`** | push / PR | The fast gate: `./mvnw -B verify` (compile + test + package the jar). No images. |
| **`base-images.yml`** | changes under `images/2-size/{golden-ubuntu,golden-jre}/**` | Build + publish the base layer: `golden-ubuntu`, then `golden-jre` `FROM` the ubuntu **digest**. |
| **`artifact.yml`** | changes under `src/**`, `pom.xml`, … | Build the jar(s) and `oras push` them to `ghcr.io/<owner>/<repo>/jar` (plain + Spring-AOT). |
| **`containerize.yml`** | after base-images / artifact finish on `main` (`workflow_run`) | One matrix job per runtime image (`fat`, `app`, `jvm-aot`, `spring-aot`): `oras pull` the jar, build `FROM` the published `golden-jre` digest, push. |
| **`renovate.yml`** | daily / dispatch | Self-hosted Renovate (GitHub App auth). See [`docs/renovate.md`](../../docs/renovate.md). |

```
  base-images.yml  ─┐
                    ├─(workflow_run on main)─▶  containerize.yml  ─▶  ghcr.io/…/<name>
  artifact.yml     ─┘
```

The same three pipelines run locally, wired together, via
[`scripts/build-images.sh`](../../scripts/build-images.sh). The Dockerfiles they build
live under [`images/`](../../images), grouped by tutorial theme.
