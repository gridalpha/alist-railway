# AList on Railway.
#
# One layer over the upstream published image. It exists for a single boot-time
# step the image cannot do: selecting Meilisearch as AList's search index, which
# lives in a database row rather than in a configuration file, so no environment
# variable can express it. Everything else about the deployment is env vars.
FROM xhofe/alist:latest

USER root

# The published `latest` variant carries neither curl nor jq (they arrive only
# with the aria2 build argument), and the boot step needs both.
RUN apk add --no-cache curl jq \
 && rm -rf /var/cache/apk/* \
 && command -v curl \
 && command -v jq

COPY --chmod=755 railway-entrypoint.sh /railway-entrypoint.sh
RUN bash -n /railway-entrypoint.sh

# The base image sets no ENTRYPOINT, so replacing CMD keeps its own
# /entrypoint.sh (umask, chown, privilege handling) as the last step.
CMD [ "/railway-entrypoint.sh" ]
