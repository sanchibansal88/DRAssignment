FROM python:3.11-slim

ENV PIP_NO_CACHE_DIR=off \
    PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 
    
WORKDIR /app
COPY requirements.txt ./
RUN pip install --no-cache-dir -r requirements.txt
COPY . .

EXPOSE 8080
CMD ["gunicorn", "--bind", "0.0.0.0:8080", "app:app"]

# docker run -d --name pg \
#   --network my-app-net \
#   -e POSTGRES_USER=sanchibansal \
#   -e POSTGRES_PASSWORD=sanchi123 \
#   -e POSTGRES_DB=postgres \
#   postgres:15

# docker start pg

# docker run --rm --network my-app-net -p 8080:8080 \
#   -e DATABASE_URL=postgresql://sanchibansal:sanchi123@pg:5432/postgres \
#   app