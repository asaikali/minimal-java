# syntax=docker/dockerfile:1

# ===========================================================================
# Base image: ubuntu — chiseled Ubuntu (base-files + libc6) only.
# ===========================================================================
# This is the bottom of the stack: a from-scratch rootfs holding nothing but
# the Ubuntu base-files and libc6, cut with Canonical's `chisel`. It owns its
# own lifecycle — built and published independently (ghcr.io/<owner>/
# minimal-java/ubuntu), then consumed by the jre base image (images/jre).
#
# Build configuration — override with `--build-arg NAME=value`. These feed the
# FROM tag (ubuntu:${UBUNTU_VERSION}), the chisel-releases branch
# (ubuntu-${UBUNTU_VERSION}), and the chisel download. Renovate auto-updates
# CHISEL_VERSION via the `# renovate:` annotation below (a custom manager in
# renovate.json edits its ARG line directly). The ubuntu tag is ${ARG}-composed,
# which Renovate can detect but not rewrite in place — so it's configured to
# only flag a new MAJOR on the Dependency Dashboard; bump UBUNTU_VERSION by hand
# to keep the tag clean. See docs/renovate.md.
ARG UBUNTU_VERSION=26.04
# renovate: datasource=github-releases depName=canonical/chisel versioning=semver
ARG CHISEL_VERSION=v1.4.1

# ---------------------------------------------------------------------------
# chisel: cut the Ubuntu package slices into a minimal rootfs.
# New to chisel? 7-min lightboard intro: https://www.youtube.com/watch?v=o8NILnbjhQ4
# Two deeper talks + a suggested watch order are in the README Resources section.
# ---------------------------------------------------------------------------
FROM ubuntu:${UBUNTU_VERSION} AS chisel

# TARGETARCH is auto-provided by buildx (amd64/arm64) to pick the chisel binary.
# UBUNTU_VERSION and CHISEL_VERSION are imported from the globals above — a
# pre-FROM ARG isn't visible inside a stage unless re-declared here.
ARG TARGETARCH
ARG UBUNTU_VERSION
ARG CHISEL_VERSION

# ca-certificates is required so chisel can verify TLS when fetching slice
# definitions from the chisel-releases repo; the base ubuntu image omits it.
RUN apt-get update && \
    apt-get install -y --no-install-recommends ca-certificates && \
    rm -rf /var/lib/apt/lists/*

ADD https://github.com/canonical/chisel/releases/download/${CHISEL_VERSION}/chisel_${CHISEL_VERSION}_linux_${TARGETARCH}.tar.gz /tmp/chisel.tar.gz
RUN tar -xf /tmp/chisel.tar.gz -C /usr/bin/

# Cut only the requested slices into /rootfs.
RUN mkdir -p /rootfs && \
    chisel cut --release "ubuntu-${UBUNTU_VERSION}" --root /rootfs \
        base-files_base \
        base-files_release-info \
        libc6_libs

# ---------------------------------------------------------------------------
# Final image: the chiseled rootfs on scratch — no shell, no apt, no package
# manager. libc6 (here) is the only runtime dependency the JRE base adds.
# ---------------------------------------------------------------------------
FROM scratch
COPY --from=chisel /rootfs /
