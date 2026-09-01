# Imagen base "slim" y con versión fijada: menos superficie de ataque y builds reproducibles.
FROM python:3.11-slim

# - PYTHONDONTWRITEBYTECODE: no generar archivos .pyc dentro del contenedor.
# - PYTHONUNBUFFERED: enviar logs a stdout/stderr sin buffer (se ven en tiempo real).
# - PIP_*: instalaciones más limpias y silenciosas.
ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PIP_NO_CACHE_DIR=1 \
    PIP_DISABLE_PIP_VERSION_CHECK=1

WORKDIR /app

# Instalar dependencias ANTES de copiar el código: si el código cambia pero
# requirements.txt no, Docker reutiliza esta capa y el build es casi instantáneo.
COPY requirements.txt .
# pip/setuptools/wheel solo hacen falta para INSTALAR los paquetes, no para que
# gunicorn los corra en runtime. Se desinstalan en la misma capa: reduce
# superficie de ataque y elimina CVEs de esas herramientas de build en la
# imagen final (encontrado escaneando con Trivy — ver security/README.md).
RUN pip install --no-cache-dir -r requirements.txt \
    && pip uninstall -y pip setuptools wheel \
    && rm -rf /usr/local/lib/python3.11/ensurepip

# Recién ahora copiamos el código de la aplicación.
COPY app.py .

# Ejecutar como usuario sin privilegios (no root) para reducir el impacto de un
# eventual compromiso del contenedor. Se le da un HOME propio porque gunicorn
# necesita un directorio escribible para su socket de control interno.
RUN useradd --create-home --uid 10001 appuser
USER appuser
ENV HOME=/home/appuser

# Puerto en el que escucha gunicorn dentro del contenedor.
EXPOSE 5000

# Healthcheck a nivel de imagen (útil también fuera de compose, p. ej. en ECS).
# La imagen slim no trae curl, pero sí Python: consultamos /health con urllib.
HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
    CMD python -c "import urllib.request,sys; sys.exit(0 if urllib.request.urlopen('http://localhost:5000/health').status == 200 else 1)"

# Servidor WSGI de producción. El servidor de desarrollo de Flask (python app.py)
# no está pensado para producción (single-thread, sin robustez ante carga).
CMD ["gunicorn", "--bind", "0.0.0.0:5000", "--workers", "2", "--access-logfile", "-", "app:app"]
