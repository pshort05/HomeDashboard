FROM python:3.12-slim

WORKDIR /app

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# Download Font Awesome 6 Free before copying app code so this layer is cached
# independently of code changes.
RUN apt-get update \
    && apt-get install -y --no-install-recommends curl unzip \
    && FA_VERSION=6.5.1 \
    && curl -fsSL "https://use.fontawesome.com/releases/v${FA_VERSION}/fontawesome-free-${FA_VERSION}-web.zip" \
       -o /tmp/fa.zip \
    && unzip -q /tmp/fa.zip -d /tmp/fa \
    && mkdir -p homedashboard/static/fontawesome/css \
    && cp "/tmp/fa/fontawesome-free-${FA_VERSION}-web/css/all.min.css" \
          homedashboard/static/fontawesome/css/ \
    && cp -r "/tmp/fa/fontawesome-free-${FA_VERSION}-web/webfonts" \
             homedashboard/static/fontawesome/ \
    && rm -rf /tmp/fa /tmp/fa.zip \
    && apt-get purge -y --auto-remove curl unzip \
    && rm -rf /var/lib/apt/lists/*

COPY . .

EXPOSE 8080

CMD ["python", "run.py"]
