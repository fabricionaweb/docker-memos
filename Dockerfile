# syntax=docker/dockerfile:1-labs
FROM public.ecr.aws/docker/library/alpine:3.19 AS base
ENV TZ=UTC
WORKDIR /src

# source stage =================================================================
FROM base AS source

# get and extract source from git
ARG BRANCH
ARG VERSION
ADD https://github.com/usememos/memos.git#${BRANCH:-v$VERSION} ./

# frontend stage ===============================================================
FROM base AS build-frontend

# build dependencies
RUN apk add --no-cache nodejs-current && corepack enable

# node_modules
COPY --from=source /src/web/package.json /src/web/pnpm-lock.yaml /src/web/tsconfig.json ./web/
COPY --from=source /src/proto ./proto
RUN pnpm --dir web install --frozen-lockfile

# frontend source and build
COPY --from=source /src/web ./web
RUN pnpm --dir web build

# build stage ==================================================================
FROM base AS build-backend
ENV CGO_ENABLED=0

# dependencies
RUN apk add --no-cache git && \
    apk add --no-cache go --repository=http://dl-cdn.alpinelinux.org/alpine/edge/community

# build dependencies
COPY --from=source /src/go.mod /src/go.sum ./
RUN go mod download

# build app
COPY --from=source /src/bin ./bin
COPY --from=source /src/api ./api
COPY --from=source /src/internal ./internal
COPY --from=source /src/plugin ./plugin
COPY --from=source /src/server ./server
COPY --from=source /src/store ./store
COPY --from=source /src/proto ./proto
ARG VERSION
ARG COMMIT=$VERSION
RUN mkdir /build && \
    go build -trimpath -ldflags "-s -w" \
        -o /build/ ./bin/...

# runtime stage ================================================================
FROM base

ENV S6_VERBOSITY=0 S6_BEHAVIOUR_IF_STAGE2_FAILS=2 PUID=65534 PGID=65534
ENV MEMOS_MODE=prod MEMOS_DATA=/config
WORKDIR /config
VOLUME /config
EXPOSE 8081

# copy files
COPY --from=build-backend /build /app
COPY --from=build-frontend /src/web/dist /app/dist
COPY ./rootfs/. /

# runtime dependencies
RUN apk add --no-cache tzdata s6-overlay curl

# run using s6-overlay
ENTRYPOINT ["/init"]
