# ==============================================================================
# Base stage - shared dependencies for all targets
# ==============================================================================
FROM ghcr.io/astral-sh/uv:python3.12-bookworm-slim AS base

WORKDIR /app

# Enable bytecode compilation
ENV UV_COMPILE_BYTECODE=1

# Copy from the cache instead of linking since it's a mounted volume
ENV UV_LINK_MODE=copy

# Omit development dependencies
ENV UV_NO_DEV=1

# Ensure installed tools can be executed out of the box
ENV UV_TOOL_BIN_DIR=/usr/local/bin

# Copy the lockfile and settings
COPY ./pyproject.toml ./uv.lock ./.python-version /app/

# Install the project's dependencies using the lockfile and settings
RUN uv sync --locked --no-install-project

# Place executables in the environment at the front of the path
ENV PATH="/app/.venv/bin:$PATH"

# ==============================================================================
# API-only stage - FastAPI service
# ==============================================================================
FROM base AS api

# Copy only API-related code
COPY model_service/ ./model_service/
COPY conf/ ./conf/
COPY utils/ ./utils/

# Install project
RUN uv sync --locked

# Expose FastAPI port
EXPOSE 8000

# Health check
HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
  CMD python -c "import requests; requests.get('http://localhost:8000/health', timeout=2)"

# Run FastAPI
CMD ["uvicorn", "model_service.main:app", "--host", "0.0.0.0", "--port", "8000"]

# ==============================================================================
# Streamlit-only stage - Dashboard UI
# ==============================================================================
FROM base AS streamlit

# Copy Streamlit app code
COPY carbon_dash.py ./carbon_dash.py
COPY pages/ ./pages/
COPY utils/ ./utils/
COPY conf/ ./conf/
COPY data/ ./data/
COPY .streamlit/ ./.streamlit/

# Install project
RUN uv sync --locked

# Expose Streamlit port
EXPOSE 8501

# Health check
HEALTHCHECK --interval=30s --timeout=3s --start-period=10s --retries=3 \
  CMD python -c "import requests; requests.get('http://localhost:8501/healthz', timeout=2)"

# Run Streamlit (without baseUrlPath for standalone deployment)
CMD ["streamlit", "run", "carbon_dash.py", "--server.port=8501", "--server.address=0.0.0.0"]

# ==============================================================================
# Combined stage (default) - Both services with nginx reverse proxy
# ==============================================================================
FROM base AS combined

# Install nginx
RUN apt-get update && apt-get install -y nginx && rm -rf /var/lib/apt/lists/*

# Copy all application code
COPY model_service/ ./model_service/
COPY conf/ ./conf/
COPY utils/ ./utils/
COPY carbon_dash.py ./carbon_dash.py
COPY pages/ ./pages/
COPY data/ ./data/
COPY .streamlit/ ./.streamlit/
COPY nginx.conf /etc/nginx/nginx.conf

# Install project
RUN uv sync --locked

# Expose combined port
EXPOSE 8080

# Health check via nginx
HEALTHCHECK --interval=30s --timeout=3s --start-period=15s --retries=3 \
  CMD python -c "import requests; requests.get('http://localhost:8080/health', timeout=2)"

# Create startup script
RUN echo '#!/bin/bash\n\
set -e\n\
\n\
# Start FastAPI in background\n\
echo "Starting FastAPI..."\n\
uvicorn model_service.main:app --host 127.0.0.1 --port 8000 &\n\
FASTAPI_PID=$!\n\
\n\
# Start Streamlit in background\n\
echo "Starting Streamlit..."\n\
streamlit run carbon_dash.py --server.port 8501 --server.address 127.0.0.1 &\n\
STREAMLIT_PID=$!\n\
\n\
# Start nginx in foreground\n\
echo "Starting nginx..."\n\
nginx -g "daemon off;" &\n\
NGINX_PID=$!\n\
\n\
# Wait for any process to exit\n\
wait -n\n\
\n\
# Exit with status of process that exited first\n\
exit $?\n\
' > /app/start.sh && chmod +x /app/start.sh

# Command to run the application
CMD ["/app/start.sh"]
