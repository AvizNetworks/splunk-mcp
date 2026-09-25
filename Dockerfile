ARG PYTHON_BASE=avizdock/ncp-python-base-312-alpine:latest
# Runtime stage: plain upstream python:3.12-alpine -- the same Alpine release and
# CPython the shared base is built FROM, but without its build toolchain, so the
# image does not carry ~450 MB of gcc/binutils/git layers underneath. Override
# with a lean shared runtime base once deploy-ones provides one.
ARG PYTHON_RUNTIME_BASE=python:3.12-alpine

# --- builder: resolve the locked venv (uv only lives here) ---
FROM ${PYTHON_BASE} AS builder

WORKDIR /app

RUN pip install --no-cache-dir uv

# Copy project files
COPY pyproject.toml uv.lock ./
COPY splunk_mcp.py ./
COPY README.md ./
COPY .env.example ./

# Install dependencies from the lockfile (reproducible, non-editable)
RUN --mount=type=cache,target=/root/.cache/uv \
    uv sync --locked --no-dev

# --- runtime: lean upstream alpine (PYTHON_RUNTIME_BASE), no toolchain or pip ---
FROM ${PYTHON_RUNTIME_BASE}

WORKDIR /app

# Build toolchain, packaging tools: if PYTHON_RUNTIME_BASE is the shared alpine base it
# carries build-base/git/curl/*-dev, and every base carries pip/setuptools/wheel
# for building; none are needed at runtime (the app runs from /app/.venv and the
# healthcheck uses python), and they are the bulk of the image's HIGH findings
# (binutils, pip's vendored msgpack/setuptools).
RUN pkgs="$(apk info -e build-base libffi-dev openssl-dev git curl || true)" \
    && if [ -n "$pkgs" ]; then apk del --no-cache $pkgs; fi \
    && apk upgrade --no-cache \
    && (python -m pip uninstall -y setuptools wheel pip || true) \
    && (id app >/dev/null 2>&1 || (addgroup -g 10001 app && adduser -D -u 10001 -G app app))

COPY --from=builder /app /app

# Create directory for environment file; app writes its own log file to /app,
# so the whole tree needs to be owned by the non-root runtime user.
RUN mkdir -p /app/config && chown -R app:app /app

ENV PATH="/app/.venv/bin:$PATH"

# Set environment variables
ENV PYTHONUNBUFFERED=1
ENV SPLUNK_HOST=https://10.4.4.33:8089
ENV SPLUNK_PORT=8089
ENV SPLUNK_USERNAME=admin
ENV SPLUNK_PASSWORD=password
ENV SPLUNK_TOKEN=
ENV SPLUNK_SCHEME=https
ENV FASTMCP_LOG_LEVEL=INFO
ENV FASTMCP_PORT=10020
ENV DEBUG=false
ENV MODE=sse
ENV VERIFY_SSL=false

# Expose the FastAPI port
EXPOSE 10020

# Add healthcheck
HEALTHCHECK --interval=30s --timeout=10s --start-period=5s --retries=3 \
    CMD python -c "import os,urllib.request; urllib.request.urlopen('http://localhost:%s/health' % os.environ.get('FASTMCP_PORT','10020'), timeout=5)" || exit 1

USER app

# Default to SSE mode
CMD ["python", "splunk_mcp.py", "sse"]
