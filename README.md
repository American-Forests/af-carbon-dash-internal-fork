# 🚀 Getting Started

## 1. Clone the repo

SSH: 
```
git clone git@github.com:sig-gis/af-carbon-dash.git
```

HTTPS:
```
git clone https://github.com/sig-gis/af-carbon-dash.git
```

## 2. Install `uv`
   
This app uses uv for dependency managment. 
[Read more about uv in the docs.](https://docs.astral.sh/uv/getting-started/) 

Install `uv`:

macOS/Linux
```
curl -LsSf https://astral.sh/uv/install.sh | sh
```

See the [uv installation docs for Windows installation instructions](https://docs.astral.sh/uv/getting-started/installation/#__tabbed_1_2)


### 2b. (Optional) Manually activate the `uv` environment

You can skip this if you prefer to use uv run in Step 3.

If you prefer a manually activated environment:

```
uv sync
source .venv/bin/activate
```

This creates and activates the .venv, syncing dependencies from pyproject.toml and uv.lock.

## 3. Prep data

The Makefile downloads the [FVS Variants shapefile](https://www.fs.usda.gov/fmsc/ftp/fvs/docs/overviews/FVSVariantMap20210525.zip) and simplifies it into a GeoJSON for efficiency. 

The Variants are automatically filtered to the line-separated list of supported FVS Variants in `conf/base/supported_variants.txt`

Simply run the Makefile to prep the data:

```
make
```

## 4. Run the API

With uvicorn locally:

```bash
uv run uvicorn model_servce.main:app --host 127.0.0.1 --port 8000 --reload
```

## 5. Run the streamlit app

### ✅ Option A (Recommended): Without Manual Activation

This is the simplest method. It will:

- Create .venv if needed
- Sync dependencies
- Run the app

```
export CARBON_API_BASE_URL=http://localhost:8000
uv run streamlit run carbon_dash.py
```

### Option B: With Activated Environment 

If you’ve activated the environment manually (see 2b):

```
streamlit run carbon_dash.py
```

## Docker Container

The project supports building three different container configurations using multi-stage builds:

### 1. Combined Container (Default)
Both API and Streamlit app bundled together with nginx reverse proxy:
- **Streamlit** served at root (`/`) - main dashboard UI
- **FastAPI** served at specific endpoints (`/docs`, `/redoc`, `/health`, `/carbon/*`, `/proforma/*`, etc.)

Under this setup, both apps are served from the root using some careful routing.  This allows them to be hosted together or separate without a change in URL path.  Just make sure, if you add a new endpoint for the FastAPI service, add it to nginx.conf also for routing to work properly in container.

How to build and run locally:
```bash
# Build combined container (default target)
docker build -t af-carbon .
# or explicitly:
docker build --target combined -t af-carbon .

# Run combined container
docker run -p 8080:8080 af-carbon

# Access services:
# - Streamlit UI: http://localhost:8080/
# - FastAPI Docs: http://localhost:8080/docs
# - Health Check: http://localhost:8080/health
```

### 2. API-Only Container
FastAPI service only (for separate deployments):

```bash
# Build API-only container
docker build --target api -t af-carbon-api .

# Run API container
docker run -p 8000:8000 af-carbon-api

# Access:
# - API: http://localhost:8000
# - Docs: http://localhost:8000/docs
# - Health: http://localhost:8000/health
```

### 3. Streamlit-Only Container
Dashboard UI only (for separate deployments):

```bash
# Build Streamlit-only container
docker build --target streamlit -t af-carbon-app .

# Run Streamlit container (requires API endpoint)
docker run -p 8501:8501 -e CARBON_API_BASE_URL=http://api-host:8000 af-carbon-app

# Access:
# - Dashboard: http://localhost:8501
# - Health: http://localhost:8501/healthz
```

### Multi-Container Deployment Example

When deploying API and Streamlit separately:

```bash
# Start API container
docker run -d --name carbon-api -p 8000:8000 af-carbon-api

# Start Streamlit container pointing to API
docker run -d --name carbon-app -p 8501:8501 \
  -e CARBON_API_BASE_URL=http://carbon-api:8000 \
  af-carbon-app
```

AWS and GCP both support multi-stage Dockerfiles, allowing you to choose which target to build and run as well.
