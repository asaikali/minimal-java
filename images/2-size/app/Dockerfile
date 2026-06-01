# syntax=docker/dockerfile:1
#
# Tutorial: docs/2-size.md (Part 2 — a smaller, better-layered image).

# ===========================================================================
# Runtime image: app — the chiseled golden-jre base + the Spring Boot app, exploded
# into Spring Boot layers. No AOT (see jvm-aot/spring-aot for the faster-startup
# variants); app, jvm-aot, and spring-aot are sibling packagings of the app.
# ===========================================================================
# Inputs (both pinned by digest in CI):
#   - application.jar — the pre-built plain jar, in the build context (oras pull
#     by the containerize pipeline, or staged locally by build-images.sh).
#   - JRE_BASE — the chiseled runtime base from images/2-size/golden-jre. Defaults to the local
#     tag for offline builds; CI overrides with the digest-pinned ghcr reference
#     (--build-arg JRE_BASE=ghcr.io/<owner>/minimal-java/golden-jre@sha256:...).
ARG JAVA_VERSION=25
ARG JRE_BASE=minimal-java/golden-jre:local

# ---------------------------------------------------------------------------
# extract: explode the layered jar into per-layer directories. Pinned to
# $BUILDPLATFORM (the builder's native arch): the jar and its layers are
# architecture-independent, so this runs ONCE on the native arch and each
# per-arch final image below COPYs --from this single extract — no emulation.
# ---------------------------------------------------------------------------
FROM --platform=$BUILDPLATFORM eclipse-temurin:${JAVA_VERSION}-jre AS extract
WORKDIR /build
COPY application.jar application.jar
RUN java -Djarmode=tools -jar application.jar extract --layers --destination extracted

# ---------------------------------------------------------------------------
# Final image: jre + the exploded app, one COPY per layer. Ordered slowest-
# changing first (dependencies) to fastest (application) so a code change only
# busts the small final layer and reuses the cached dependency layers.
# ---------------------------------------------------------------------------
FROM ${JRE_BASE}
WORKDIR /app
COPY --from=extract /build/extracted/dependencies/ ./
COPY --from=extract /build/extracted/spring-boot-loader/ ./
COPY --from=extract /build/extracted/snapshot-dependencies/ ./
COPY --from=extract /build/extracted/application/ ./
EXPOSE 8080
# Numeric non-root UID:GID — no /etc/passwd needed, and Kubernetes runAsNonRoot
# can verify it.
USER 10001:10001
ENTRYPOINT ["java", "-jar", "application.jar"]
