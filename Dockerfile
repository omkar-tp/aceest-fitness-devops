# ---- Build a lightweight, production-ready image for ACEest Fitness & Gym ----
FROM python:3.12-slim

# Prevents Python from writing .pyc files and buffers, keeping logs responsive.
ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1

WORKDIR /app

# Run as a non-root user for better security.
RUN useradd --create-home appuser && chown appuser:appuser /app

# Install dependencies first to leverage Docker layer caching.
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# Copy application source.
COPY --chown=appuser:appuser . .

# Release metadata baked into the image (override with --build-arg).
ARG APP_VERSION=1.1.0
ENV APP_VERSION=${APP_VERSION} \
    DEPLOY_COLOR=default

USER appuser

EXPOSE 5000

HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
    CMD python -c "import urllib.request,sys; sys.exit(0 if urllib.request.urlopen('http://127.0.0.1:5000/health').status == 200 else 1)"

# Serve the app with gunicorn in production.
CMD ["gunicorn", "--bind", "0.0.0.0:5000", "app:app"]
