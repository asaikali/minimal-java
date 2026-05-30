# syntax=docker/dockerfile:1

# Ubuntu version used for both the builder base image and the matching
# chisel-releases slice branch. Declared before FROM so it can drive the tag.
ARG UBUNTU_VERSION=26.04

# ---------------------------------------------------------------------------
# Stage 1: cut the Ubuntu package slices into a minimal rootfs using chisel.
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
# Stage 2: assemble the final image from the chiseled rootfs only.
# ---------------------------------------------------------------------------
FROM scratch
COPY --from=chisel /rootfs /
