# syntax=docker/dockerfile:1
#
# Tutorial: docs/2-size.md (Part 2 — a smaller, better-layered image).

# ===========================================================================
# Base image: ubuntu — chiseled Ubuntu (base-files + libc6) only.
# ===========================================================================
# This is the bottom of the stack: a from-scratch rootfs holding nothing but
# the Ubuntu base-files and libc6, cut with Canonical's `chisel`. It owns its
# own lifecycle — built and published independently (ghcr.io/<owner>/
# minimal-java/golden-ubuntu), then consumed by the golden-jre base image (images/2-size/golden-jre).
#
# Build configuration — override with `--build-arg NAME=value`. UBUNTU_VERSION feeds
# both the FROM tag and the chisel-releases branch (ubuntu-${UBUNTU_VERSION}).
#
# This is a GOLDEN base image, so its upstream root is PINNED BY DIGEST: the FROM
# below is `ubuntu:${UBUNTU_VERSION}@sha256:...`, so the same commit always builds on
# the exact same bytes (reproducibility). Renovate keeps the digest current
# automatically (the Docker manager updates a literal @sha256 in place even though the
# tag is ${ARG}-composed; `digest` updates are left enabled in renovate.json). The
# tag itself is ${ARG}-composed, which Renovate can detect but not rewrite, so a new
# MAJOR ubuntu still surfaces on the Dependency Dashboard — bump UBUNTU_VERSION (and
# the digest follows) by hand. CHISEL_VERSION is tracked by a custom regex manager.
# See docs/renovate.md. (The naive `fat` image, by contrast, stays on a floating tag.)
ARG UBUNTU_VERSION=26.04
# renovate: datasource=github-releases depName=canonical/chisel versioning=semver
ARG CHISEL_VERSION=v1.4.1

# ---------------------------------------------------------------------------
# chisel: cut the Ubuntu package slices into a minimal rootfs.
# New to chisel? 7-min lightboard intro: https://www.youtube.com/watch?v=o8NILnbjhQ4
# Two deeper talks + a suggested watch order are in the README Resources section.
# ---------------------------------------------------------------------------
FROM ubuntu:${UBUNTU_VERSION}@sha256:f3d28607ddd78734bb7f71f117f3c6706c666b8b76cbff7c9ff6e5718d46ff64 AS chisel

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
