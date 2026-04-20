FROM debian:stable-slim

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y --no-install-recommends \
        git curl wget vim nano \
        ca-certificates gnupg \
        procps \
        python3 python3-pip \
        poppler-utils \
        tesseract-ocr tesseract-ocr-por \
        unzip jq \
    && rm -rf /var/lib/apt/lists/*

RUN pip3 install --break-system-packages \
    requests pymupdf openpyxl docx2txt

RUN curl -fsSL https://deb.nodesource.com/setup_22.x | bash - \
    && apt-get install -y nodejs \
    && rm -rf /var/lib/apt/lists/*

RUN curl -fsSL https://openclaw.ai/install.sh | bash -s -- --no-onboard

RUN npm install -g @anthropic-ai/claude-code

# Usuário não-root com UID 1000 — necessário para o claude CLI (bloqueia root)
RUN apt-get update && apt-get install -y --no-install-recommends sudo && rm -rf /var/lib/apt/lists/*

RUN useradd -m -u 1000 -s /bin/bash openclaw && \
    echo "openclaw ALL=(ALL) NOPASSWD:ALL" >> /etc/sudoers && \
    mkdir -p /home/openclaw/.openclaw \
             /home/openclaw/.openclaw-seed \
             /home/openclaw/.config/fabric \
             /home/openclaw/.config/sharepoint \
             /home/openclaw/.config-seed/fabric \
             /home/openclaw/.config-seed/sharepoint \
             /home/openclaw/workspace && \
    chown -R openclaw:openclaw /home/openclaw

COPY --chown=openclaw:openclaw entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

COPY --chown=openclaw:openclaw openclaw/ /home/openclaw/.openclaw-seed/
COPY --chown=openclaw:openclaw config/   /home/openclaw/.config-seed/

USER openclaw
WORKDIR /home/openclaw/workspace

ENTRYPOINT ["/entrypoint.sh"]
CMD ["gateway"]
