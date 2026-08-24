#!/usr/bin/env bash
set -euo pipefail

readonly image="plantuml/plantuml@sha256:47870c1f76cfb3747bc7090bfe83013a4e3105b5a0bb1515e2baf5d3e2b3ee9d"
readonly script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
readonly output_dir="${script_dir}/generated"

mkdir -p "$output_dir"

docker run --rm \
  --network none \
  --read-only \
  --security-opt no-new-privileges \
  --cap-drop ALL \
  --user "$(id -u):$(id -g)" \
  --mount "type=bind,src=${script_dir},dst=/work,readonly" \
  --mount "type=bind,src=${output_dir},dst=/output" \
  --mount type=tmpfs,dst=/tmp \
  "$image" -failfast2 -tsvg -o /output /work/*.puml

docker run --rm \
  --network none \
  --read-only \
  --security-opt no-new-privileges \
  --cap-drop ALL \
  --user "$(id -u):$(id -g)" \
  --mount "type=bind,src=${script_dir},dst=/work,readonly" \
  --mount "type=bind,src=${output_dir},dst=/output" \
  --mount type=tmpfs,dst=/tmp \
  "$image" -failfast2 -tpng -o /output /work/*.puml
