# syntax=docker/dockerfile:1
#
# Tutorial: docs/3-speed.md (Part 3 — a faster app).

# ===========================================================================
# Runtime image: jvm-aot — a sibling of app on the jre base: the same exploded
# app PLUS a JDK AOT cache, trading a larger image for faster startup.
# ===========================================================================
# A build-time "training run" starts the app, lets Spring refresh the context,
# then exits (-Dspring.context.exit=onRefresh), recording loaded classes into
# app.aot (JEP 514 one-step -XX:AOTCacheOutput); the runtime loads it via
# -XX:AOTCache. The training RUN runs as the default root user so it can write
# app.aot into /app; USER then drops to non-root for runtime. RUN uses exec form
# (the chiseled image has no shell).
#
# Unlike the architecture-independent `extract` stage, the training run executes
# the app, so it produces an arch-specific app.aot — under multi-arch buildx the
# arm64 training run is emulated (or runs on a native arm64 runner).
#
# Inputs (both pinned by digest in CI): application.jar in the build context, and
# JRE_BASE (defaults to the local tag; CI overrides with the ghcr digest).
#
# Background talk (explains AOT / Project Leyden by a member of the Spring Boot
# team): "Supercharge your JVM performance with Project Leyden and Spring Boot"
# by Moritz Halbritter, 2026-02-10 — https://www.youtube.com/watch?v=UqaSWiE076w
ARG JAVA_VERSION=25
ARG JRE_BASE=minimal-java/jre:local

# extract: explode the layered jar (architecture-independent; see images/app).
FROM --platform=$BUILDPLATFORM eclipse-temurin:${JAVA_VERSION}-jre AS extract
WORKDIR /build
COPY application.jar application.jar
RUN java -Djarmode=tools -jar application.jar extract --layers --destination extracted

# Final image: jre + exploded app + the JDK AOT cache from the training run.
FROM ${JRE_BASE}
WORKDIR /app
COPY --from=extract /build/extracted/dependencies/ ./
COPY --from=extract /build/extracted/spring-boot-loader/ ./
COPY --from=extract /build/extracted/snapshot-dependencies/ ./
COPY --from=extract /build/extracted/application/ ./
EXPOSE 8080
RUN ["java", "-XX:AOTCacheOutput=app.aot", "-Dspring.context.exit=onRefresh", "-jar", "application.jar"]
USER 10001:10001
ENTRYPOINT ["java", "-XX:AOTCache=app.aot", "-jar", "application.jar"]
