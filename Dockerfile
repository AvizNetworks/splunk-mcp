ARG PYTHON_BASE=avizdock/ncp-python-base-312-alpine:latest
FROM ${PYTHON_BASE}

# Set working directory
WORKDIR /app

# curl for healthcheck; uv for installing from the lockfile
RUN apk add --no-cache curl \
    && pip install --no-cache-dir uv

# Copy project files
COPY pyproject.toml uv.lock ./
COPY splunk_mcp.py ./
COPY README.md ./
COPY .env.example ./

# Install dependencies from the lockfile (reproducible, non-editable)
RUN --mount=type=cache,target=/root/.cache/uv \
    uv sync --locked --no-dev

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
    CMD curl -f http://localhost:${FASTMCP_PORT}/health || exit 1

USER app

# Default to SSE mode
CMD ["python", "splunk_mcp.py", "sse"]
