FROM python:3.12-slim AS base
ENV PYTHONDONTWRITEBYTECODE=1 PYTHONUNBUFFERED=1
WORKDIR /app
COPY requirements.txt .
RUN pip install --no-cache-dir --no-input -r requirements.txt
COPY . .
RUN chmod -R a+rX /app
USER nobody

FROM base AS test
CMD ["python", "-m", "unittest", "-v"]

FROM base AS final
CMD ["python", "main.py"]
