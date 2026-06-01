# syntax=docker/dockerfile:1
#
# Tutorial: docs/2-size.md (Part 2 — a smaller, better-layered image).

# ===========================================================================
# Base image: golden-jre — the chiseled golden-ubuntu base + a trimmed Temurin JRE.
# ===========================================================================
# The platform-team runtime base every application image builds FROM. It owns
# its own lifecycle: published to ghcr.io/<owner>/minimal-java/golden-jre, then
# consumed by the app/jvm-aot/spring-aot containerize pipelines.
#
# As a GOLDEN base, its upstream Temurin root is PINNED BY DIGEST (the jre-dist
# FROM below is `eclipse-temurin:${JAVA_VERSION}-jre@sha256:...`) for reproducible
# builds; Renovate keeps the digest current (see docs/renovate.md).
#
# UBUNTU_BASE is the chiseled base from images/2-size/golden-ubuntu. It defaults to the local
# tag scripts/build-images.sh produces, so an offline `docker build` just works;
# CI overrides it with the digest-pinned ghcr reference
# (--build-arg UBUNTU_BASE=ghcr.io/<owner>/minimal-java/golden-ubuntu@sha256:...) so the
# published jre records exactly which base it was built on.
ARG JAVA_VERSION=25
ARG UBUNTU_BASE=minimal-java/golden-ubuntu:local

# ---------------------------------------------------------------------------
# jre-dist: take the official Temurin JRE and drop the standalone launchers a
# running app never invokes, leaving only bin/java. Done here (the JRE image
# has a shell) since the final image is chiseled and shell-less.
# ---------------------------------------------------------------------------
FROM eclipse-temurin:${JAVA_VERSION}-jre@sha256:04262e8782d6b034ee5d7c1c5d4e8938fcf2063a76b4bfcd84e5d994d09c27bc AS jre-dist
RUN cd /opt/java/openjdk/bin && \
    rm -f jfr jrunscript jwebserver keytool rmiregistry

# ---------------------------------------------------------------------------
# Final image: chiseled ubuntu + the trimmed Temurin JRE. libc6 (in the ubuntu
# base) is the only runtime dependency, so no extra chisel slices are needed.
# ---------------------------------------------------------------------------
FROM ${UBUNTU_BASE}
COPY --from=jre-dist /opt/java/openjdk /opt/java/openjdk
ENV JAVA_HOME=/opt/java/openjdk
ENV PATH=/opt/java/openjdk/bin:$PATH
ENTRYPOINT ["java"]
CMD ["-version"]
