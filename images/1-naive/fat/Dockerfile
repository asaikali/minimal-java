# syntax=docker/dockerfile:1
#
# Tutorial: docs/1-pipeline.md (Part 1 — the pipeline & the naive fat jar).

# ===========================================================================
# Runtime image: fat — the naive baseline and the tutorial's starting point.
# ===========================================================================
# The Spring Boot fat jar on the FULL official Temurin JRE, with none of the
# techniques the series applies (no chisel, no layered extract, no AOT, runs as
# root). This is the image most people write by hand; app/jvm-aot/spring-aot
# show how much smaller, safer, and faster the chiseled series gets from here.
# It runs the fat jar directly (nested-jar classloader), so its startup is the
# slowest of the set.
#
# The pre-built application.jar arrives in the build context, fetched from the
# artifact registry with `oras pull` by the containerize pipeline (or staged
# locally by build-images.sh) — this image only assembles, it never compiles.
ARG JAVA_VERSION=25

FROM eclipse-temurin:${JAVA_VERSION}-jre
WORKDIR /app
COPY application.jar application.jar
EXPOSE 8080
ENTRYPOINT ["java", "-jar", "application.jar"]
