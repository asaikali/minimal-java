# syntax=docker/dockerfile:1
#
# Tutorial: docs/3-speed.md (Part 3 — a faster app).

# ===========================================================================
# Runtime image: spring-aot — the next rung past jvm-aot: the same JDK AOT cache
# PLUS Spring AOT, for the fastest startup of the series.
# ===========================================================================
# It consumes the Spring-AOT-processed jar (built with the -Pspringaot Maven
# profile, published as a SEPARATE artifact) and adds -Dspring.aot.enabled=true
# to BOTH the training run and the runtime, so the two techniques stack: Spring
# AOT replaces reflective bean wiring with generated code (the bean arrangement
# is frozen at build time), and the JDK AOT cache replays class loading/linking.
# The training run uses -Dspring.context.exit=onRefresh + -XX:AOTCacheOutput;
# runtime loads it via -XX:AOTCache. Like jvm-aot, the training RUN runs as root
# to write app.aot (arch-specific), then USER drops to non-root.
#
# Inputs (both pinned by digest in CI): the spring-aot application.jar in the
# build context (the -Pspringaot variant), and JRE_BASE (defaults to the local
# tag; CI overrides with the ghcr digest).
#
# See the README "Project Leyden & AOT" section for how Spring AOT differs from
# the JVM's AOT cache.
ARG JAVA_VERSION=25
ARG JRE_BASE=minimal-java/jre:local

# extract: explode the layered (Spring-AOT-processed) jar; architecture-
# independent, so pinned to $BUILDPLATFORM (see images/app).
FROM --platform=$BUILDPLATFORM eclipse-temurin:${JAVA_VERSION}-jre AS extract
WORKDIR /build
COPY application.jar application.jar
RUN java -Djarmode=tools -jar application.jar extract --layers --destination extracted

# Final image: jre + exploded Spring-AOT app + the JDK AOT cache.
FROM ${JRE_BASE}
WORKDIR /app
COPY --from=extract /build/extracted/dependencies/ ./
COPY --from=extract /build/extracted/spring-boot-loader/ ./
COPY --from=extract /build/extracted/snapshot-dependencies/ ./
COPY --from=extract /build/extracted/application/ ./
EXPOSE 8080
RUN ["java", "-XX:AOTCacheOutput=app.aot", "-Dspring.aot.enabled=true", "-Dspring.context.exit=onRefresh", "-jar", "application.jar"]
USER 10001:10001
ENTRYPOINT ["java", "-XX:AOTCache=app.aot", "-Dspring.aot.enabled=true", "-jar", "application.jar"]
