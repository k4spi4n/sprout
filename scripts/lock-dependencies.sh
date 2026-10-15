#!/bin/sh
# Requires uv 0.13.1. Universal resolution keeps Windows and Linux development usable.
set -eu
uv pip compile backend/requirements.in --universal --python-version 3.12 --generate-hashes --output-file backend/requirements.txt > /dev/null
uv pip compile backend/requirements-dev.in --constraint backend/requirements.txt --universal --python-version 3.12 --generate-hashes --output-file backend/requirements-dev.txt > /dev/null
uv pip compile e2e/requirements.in --universal --python-version 3.12 --generate-hashes --output-file e2e/requirements.txt > /dev/null
