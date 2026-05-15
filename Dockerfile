FROM python:3.11-slim

WORKDIR /app

RUN apt-get update && apt-get install -y --no-install-recommends \
    libxml2-dev libxslt-dev && \
    rm -rf /var/lib/apt/lists/*

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY server.py .
COPY index.html .
# logo.png 如果存在就复制（用 shell 判断，不存在也不报错）
RUN mkdir -p /app
COPY . .

EXPOSE 7860
CMD ["python", "server.py"]
