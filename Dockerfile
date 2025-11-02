# syntax=docker/dockerfile:1.6

########## Builder ##########
FROM golang:1.25 as builder
WORKDIR /src

# 1) Cache go mod download in its own layer
COPY go.mod go.sum ./
RUN --mount=type=cache,target=/go/pkg/mod \
    --mount=type=cache,target=/root/.cache/go-build \
    go mod download

# 2) Copy the rest and build
COPY . .
# Build a static binary for Linux
RUN --mount=type=cache,target=/go/pkg/mod \
    --mount=type=cache,target=/root/.cache/go-build \
    CGO_ENABLED=0 GOOS=linux GOARCH=amd64 \
    go build -trimpath -ldflags="-s -w" -o /out/podinfo ./cmd/podinfo

########## Runtime ##########
# Use distroless/static:nonroot for tiny, secure image
FROM gcr.io/distroless/static:nonroot
WORKDIR /app
COPY --from=builder /out/podinfo /app/podinfo
USER nonroot:nonroot
EXPOSE 9898
ENTRYPOINT ["/app/podinfo"]
