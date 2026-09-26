# Python 3.12 slim — Render / Fly / any container host
FROM python:3.12-slim

WORKDIR /app

ENV PYTHONDONTWRITEBYTECODE=1
ENV PYTHONUNBUFFERED=1

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY . .

# Render sets $PORT; default 8081 for local docker runs
ENV PORT=8081
EXPOSE 8081

CMD uvicorn main:app --host 0.0.0.0 --port ${PORT}
