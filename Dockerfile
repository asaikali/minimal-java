# syntax=docker/dockerfile:1

# Ubuntu version used for both the builder base image and the matching
# chisel-releases slice branch. Declared before FROM so it can drive the tag.
ARG UBUNTU_VERSION=26.04

# Temurin JRE image we copy the runtime from. Declared before any FROM (global
# scope) so it can be referenced in the jre-dist stage's FROM line.
ARG JRE_IMAGE=eclipse-temurin:25-jre

# Temurin JDK image used to compile the app and extract its layered jar.
# Declared globally so the build stage's FROM can reference it.
ARG JDK_IMAGE=eclipse-temurin:25-jdk

# ---------------------------------------------------------------------------
# Stage 1: cut the Ubuntu package slices into a minimal rootfs using chisel.
# New to chisel? 7-min lightboard intro: https://www.youtube.com/watch?v=o8NILnbjhQ4
# Two deeper talks + a suggested watch order are in the README Resources section.
# ---------------------------------------------------------------------------
FROM ubuntu:${UBUNTU_VERSION} AS chisel

# Architecture of the build target (provided automatically by buildkit:
# amd64, arm64, ...). Used to download the matching chisel binary.
ARG TARGETARCH

# Re-declare in this stage's scope; derive the chisel-releases branch from it.
ARG UBUNTU_VERSION
ARG UBUNTU_RELEASE=ubuntu-${UBUNTU_VERSION}

# Pin the chisel version for reproducibility.
ARG CHISEL_VERSION=v1.4.1

# ca-certificates is required so chisel can verify TLS when fetching slice
# definitions from the chisel-releases repo; the base ubuntu image omits it.
RUN apt-get update && \
    apt-get install -y --no-install-recommends ca-certificates && \
    rm -rf /var/lib/apt/lists/*

ADD https://github.com/canonical/chisel/releases/download/${CHISEL_VERSION}/chisel_${CHISEL_VERSION}_linux_${TARGETARCH}.tar.gz /tmp/chisel.tar.gz
RUN tar -xf /tmp/chisel.tar.gz -C /usr/bin/

# Cut only the requested slices into /rootfs.
RUN mkdir -p /rootfs && \
    chisel cut --release "${UBUNTU_RELEASE}" --root /rootfs \
        base-files_base \
        base-files_release-info \
        libc6_libs

# ---------------------------------------------------------------------------
# Image: ubuntu — chiseled Ubuntu (base-files + libc6) only.
# ---------------------------------------------------------------------------
FROM scratch AS ubuntu
COPY --from=chisel /rootfs /

# ---------------------------------------------------------------------------
# jre-dist: take the official Temurin JRE and drop the standalone launchers a
# running app never invokes, leaving only bin/java. Done here (the JRE image
# has a shell) since the final image is scratch-based and shell-less.
# JRE_IMAGE is declared globally at the top of this file.
# ---------------------------------------------------------------------------
FROM ${JRE_IMAGE} AS jre-dist
RUN cd /opt/java/openjdk/bin && \
    rm -f jfr jrunscript jwebserver keytool rmiregistry

# ---------------------------------------------------------------------------
# Image: jre — chiseled ubuntu + the trimmed Temurin JRE; libc6 (in the ubuntu
# stage) is the only runtime dependency, so no extra chisel slices are needed.
# "FROM ubuntu" below refers to the chiseled stage above, NOT
# docker.io/library/ubuntu (that would need a tag, e.g. ubuntu:26.04).
# ---------------------------------------------------------------------------
FROM ubuntu AS jre
COPY --from=jre-dist /opt/java/openjdk /opt/java/openjdk
ENV JAVA_HOME=/opt/java/openjdk
ENV PATH=/opt/java/openjdk/bin:$PATH
ENTRYPOINT ["java"]
CMD ["-version"]

# ---------------------------------------------------------------------------
# build: compile the app and explode its Spring Boot layered jar.
# Pinned to $BUILDPLATFORM (the builder's native arch). Without this pin buildx
# would instantiate this stage once per --platform target (amd64 AND an
# emulated arm64), compiling the same bytecode twice. The jar is architecture-
# independent, so we build it ONCE on the native arch and the per-arch app
# images below each COPY --from this single build.
# ---------------------------------------------------------------------------
FROM --platform=$BUILDPLATFORM ${JDK_IMAGE} AS build
WORKDIR /build
COPY . .
# Cache ~/.m2 across builds so dependencies aren't re-downloaded every time.
# Build the layered jar, then use the Spring Boot "tools" jarmode to extract
# it into per-layer directories (dependencies, spring-boot-loader,
# snapshot-dependencies, application).
RUN --mount=type=cache,target=/root/.m2 \
    ./mvnw -B -DskipTests package && \
    cp target/*.jar application.jar && \
    java -Djarmode=tools -jar application.jar extract --layers --destination extracted

# ---------------------------------------------------------------------------
# Image: app — jre + the exploded app, one COPY per layer. Ordered slowest-
# changing first (dependencies) to fastest (application) so a code change only
# busts the small final layer and reuses the cached dependency layers.
# app and aot are siblings on jre: two packagings of the same app (see aot for
# the faster-startup variant).
# ---------------------------------------------------------------------------
FROM jre AS app
WORKDIR /app
COPY --from=build /build/extracted/dependencies/ ./
COPY --from=build /build/extracted/spring-boot-loader/ ./
COPY --from=build /build/extracted/snapshot-dependencies/ ./
COPY --from=build /build/extracted/application/ ./
EXPOSE 8080
# Numeric non-root UID:GID — no /etc/passwd needed, and Kubernetes runAsNonRoot
# can verify it. Defining ENTRYPOINT also resets jre's inherited "-version" CMD.
USER 10001:10001
ENTRYPOINT ["java", "-jar", "application.jar"]

# ---------------------------------------------------------------------------
# Image: aot — a sibling of app on jre: the same exploded app PLUS a JDK 25 AOT
# cache, trading a larger image for faster startup. A build-time "training run"
# starts the app, lets Spring refresh the context, then exits
# (-Dspring.context.exit=onRefresh), recording loaded classes into app.aot
# (JEP 514 one-step -XX:AOTCacheOutput); the runtime loads it via -XX:AOTCache.
# The training RUN runs as the default root user so it can write app.aot into
# /app; USER then drops to non-root for runtime. RUN uses exec form (the chiseled
# image has no shell).
#
# Background talk (explains AOT / Project Leyden by a member of the Spring Boot
# team): "Supercharge your JVM performance with Project Leyden and Spring Boot"
# by Moritz Halbritter, 2026-02-10 — https://www.youtube.com/watch?v=UqaSWiE076w
# ---------------------------------------------------------------------------
FROM jre AS aot
WORKDIR /app
COPY --from=build /build/extracted/dependencies/ ./
COPY --from=build /build/extracted/spring-boot-loader/ ./
COPY --from=build /build/extracted/snapshot-dependencies/ ./
COPY --from=build /build/extracted/application/ ./
EXPOSE 8080
RUN ["java", "-XX:AOTCacheOutput=app.aot", "-Dspring.context.exit=onRefresh", "-jar", "application.jar"]
USER 10001:10001
ENTRYPOINT ["java", "-XX:AOTCache=app.aot", "-jar", "application.jar"]
