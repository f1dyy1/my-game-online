FROM debian:bookworm-slim

ARG GODOT_VERSION=4.7.2

RUN apt-get update && apt-get install -y --no-install-recommends \
    wget unzip ca-certificates libfontconfig1 \
    && rm -rf /var/lib/apt/lists/*

RUN wget -q https://github.com/godotengine/godot-builds/releases/download/${GODOT_VERSION}-stable/Godot_v${GODOT_VERSION}-stable_linux.x86_64.zip -O /tmp/godot.zip \
    && unzip /tmp/godot.zip -d /tmp \
    && mv /tmp/Godot_v${GODOT_VERSION}-stable_linux.x86_64 /usr/local/bin/godot \
    && chmod +x /usr/local/bin/godot \
    && rm /tmp/godot.zip

WORKDIR /app
COPY . /app

RUN godot --headless --path /app --import || true

CMD ["godot", "--headless", "--path", "/app"]
