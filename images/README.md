# images/

The Dockerfiles, grouped by the tutorial theme they belong to. Each group is one
step of the journey; read them in order (the number prefixes keep them sorted):

| Group | Images | What it shows | Tutorial |
| ----- | ------ | ------------- | -------- |
| [`1-naive/`](1-naive) | `fat` | the Spring Boot fat jar on the full Temurin JRE — the baseline | [Part 1](../docs/1-pipeline.md) |
| [`2-size/`](2-size) | `ubuntu`, `jre`, `app` | chiseled base, trimmed JRE, layered jar — make it **smaller** | [Part 2](../docs/2-size.md) |
| [`3-speed/`](3-speed) | `jvm-aot`, `spring-aot` | JDK AOT cache + Spring AOT — make it **faster** | [Part 3](../docs/3-speed.md) |

Each image lives at `images/<group>/<name>/Dockerfile`. The **group only sets the
folder path** — the image keeps its bare `<name>`, so it's tagged
`minimal-java/<name>:local` locally and published to `ghcr.io/<owner>/<repo>/<name>`.

The base images (`ubuntu`, `jre`) are built by the
[base-images pipeline](../.github/workflows/base-images.yml); the runtime images
(`fat`, `app`, `jvm-aot`, `spring-aot`) by the
[containerize pipeline](../.github/workflows/containerize.yml). See
[`.github/workflows/`](../.github/workflows) for how the pipelines fit together.
