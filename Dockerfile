ARG PY_BASE=avizdock/ncp-python-base-312:v1.7.0
# Use Python 3.12 slim image as base
FROM ${PY_BASE}

# Set working directory
WORKDIR /app

# Install build dependencies, curl for healthcheck, and uv
RUN pip install --no-cache-dir uv

# Copy project files
COPY pyproject.toml poetry.lock ./
COPY splunk_mcp.py ./
COPY README.md ./
COPY .env.example ./

# Install dependencies using uv (only main group by default)
RUN uv pip install --system poetry && \
    uv pip install --system .

# Create directory for environment file
RUN mkdir -p /app/config

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

# Default to SSE mode
CMD ["python", "splunk_mcp.py", "sse"] 