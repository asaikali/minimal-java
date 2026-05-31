# syntax=docker/dockerfile:1

# ===========================================================================
# Base image: jre — the chiseled ubuntu base + a trimmed Eclipse Temurin JRE.
# ===========================================================================
# The platform-team runtime base every application image builds FROM. It owns
# its own lifecycle: published to ghcr.io/<owner>/minimal-java/jre, then
# consumed by the app/jvm-aot/spring-aot containerize pipelines.
#
# UBUNTU_BASE is the chiseled base from images/ubuntu. It defaults to the local
# tag scripts/build-images.sh produces, so an offline `docker build` just works;
# CI overrides it with the digest-pinned ghcr reference
# (--build-arg UBUNTU_BASE=ghcr.io/<owner>/minimal-java/ubuntu@sha256:...) so the
# published jre records exactly which base it was built on.
ARG JAVA_VERSION=25
ARG UBUNTU_BASE=minimal-java/ubuntu:local

# ---------------------------------------------------------------------------
# jre-dist: take the official Temurin JRE and drop the standalone launchers a
# running app never invokes, leaving only bin/java. Done here (the JRE image
# has a shell) since the final image is chiseled and shell-less.
# ---------------------------------------------------------------------------
FROM eclipse-temurin:${JAVA_VERSION}-jre AS jre-dist
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
