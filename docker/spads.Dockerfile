# badosu/spads ships pr-downloader 0.7-611, hardcoded to repos.springrts.com,
# which can't resolve byar:test (it lives on the BAR CDN) and ignores
# PRD_RAPID_REPO_MASTER. Overlay a current Recoil engine whose pr-downloader
# honors that env so the entrypoint can fetch the game. The fetch runs in a
# throwaway ubuntu:devel stage because the spads base (ubuntu 21.10) is EOL.

FROM ubuntu:devel AS engine
RUN apt-get update \
    && apt-get install -y --no-install-recommends curl jq ca-certificates p7zip-full \
    && rm -rf /var/lib/apt/lists/*
RUN url="$(curl -fsSL https://launcher-config.beyondallreason.dev/config.json \
      | jq -r '.setups[]|select(.package.id=="manual-linux-test-engine")|.downloads.resources[]|select(.destination|contains("engine")).url')" \
    && curl -fsSL "$url" -o /tmp/engine.7z \
    && mkdir -p /engine && 7z x /tmp/engine.7z -o/engine

FROM badosu/spads:latest
COPY --from=engine /engine /opt/bar-engine
