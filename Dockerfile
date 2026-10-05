FROM python:3.12-slim-bookworm

WORKDIR /app

COPY requirements.txt .

RUN pip install \
    --no-cache-dir \
    -r requirements.txt

COPY app ./app

RUN useradd \
    --create-home \
    appuser

USER appuser

EXPOSE 8080

CMD ["python", "app/app.py"]