FROM python:3.12-slim
ENV PYTHONUNBUFFERED=1
RUN apt-get update && apt-get upgrade -y && rm -rf /var/lib/apt/lists/*
WORKDIR /app
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt
COPY app.py .
RUN useradd -m appuser
USER appuser
CMD ["gunicorn", "-b", "0.0.0.0:5000", "app:app"]
