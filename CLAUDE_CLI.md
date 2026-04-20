# CLAUDE_CLI.md — OpenClaw + Claude Code: Guia de Replicação

Este documento explica como funciona a integração do OpenClaw com o Claude Code CLI como provider de modelo, e como replicar o setup do zero em outro servidor.

---

## Visão geral

O **OpenClaw** é um gateway de agentes de IA com suporte a canais como Telegram. Ele pode usar diferentes providers de modelo. Nesta configuração, usamos o **Claude Code CLI** (`claude-cli`) como provider — ou seja, o OpenClaw chama o `claude` CLI internamente para processar as mensagens.

Isso tem uma vantagem importante: você usa a **autenticação OAuth do Claude Code** (conta claude.ai), sem precisar de API key da Anthropic separada.

---

## Estrutura do projeto

```
openclaw_base/
├── Dockerfile              # Imagem com OpenClaw + Claude Code instalados
├── docker-compose.yml      # Orquestra o container e volumes
├── entrypoint.sh           # Script de inicialização do container
├── .env                    # Variáveis de ambiente (pode ficar vazio)
├── openclaw/
│   └── openclaw.json       # Seed de configuração do OpenClaw (copiado na 1ª vez)
├── config/                 # Seeds opcionais para fabric/sharepoint
└── workspace/              # Pasta de trabalho montada no container
```

---

## Pré-requisitos no host

### 1. Claude Code autenticado

O Claude Code deve estar instalado e autenticado no host antes de subir o container:

```bash
npm install -g @anthropic-ai/claude-code
claude   # faz login via OAuth na primeira execução
```

Isso gera dois arquivos que o container vai usar via bind mount:
- `~/.claude/` — diretório com credenciais, histórico e settings
- `~/.claude.json` — arquivo de configuração principal do Claude Code

> **Por que isso importa?** O container monta esses arquivos diretamente do host. Ao fazer redeploy, a autenticação é preservada automaticamente.

### 2. Bot do Telegram

Crie um bot via [@BotFather](https://t.me/botfather) e guarde o token. Ele vai em `openclaw/openclaw.json`.

---

## Por que o container roda como usuário não-root

O Claude Code bloqueia a flag `--dangerously-skip-permissions` quando executado como `root`:

```
--dangerously-skip-permissions cannot be used with root/sudo privileges for security reasons
```

O OpenClaw usa essa flag internamente ao chamar o `claude` CLI. Por isso, o container **obrigatoriamente precisa rodar como um usuário com UID ≠ 0**.

A solução foi criar um usuário `openclaw` com UID 1000 no Dockerfile. Como Docker named volumes são criados como `root` por padrão, os diretórios são pré-criados como `openclaw` ainda na fase de build — assim o volume herda as permissões corretas na primeira montagem.

---

## Dockerfile explicado

```dockerfile
FROM debian:stable-slim
```
Imagem base mínima.

```dockerfile
RUN apt-get install -y git curl wget vim nano ca-certificates gnupg \
    procps python3 python3-pip poppler-utils tesseract-ocr ...
```
Ferramentas base + OCR (para leitura de PDFs e imagens).

```dockerfile
RUN curl -fsSL https://deb.nodesource.com/setup_22.x | bash - && apt-get install -y nodejs
```
Node.js 22 via NodeSource (necessário para OpenClaw e Claude Code).

```dockerfile
RUN curl -fsSL https://openclaw.ai/install.sh | bash -s -- --no-onboard
```
Instala o OpenClaw sem iniciar o onboarding interativo.

```dockerfile
RUN npm install -g @anthropic-ai/claude-code
```
Instala o Claude Code CLI dentro do container. A autenticação não é feita aqui — ela vem do volume montado do host.

```dockerfile
RUN apt-get install -y sudo
RUN useradd -m -u 1000 -s /bin/bash openclaw && \
    echo "openclaw ALL=(ALL) NOPASSWD:ALL" >> /etc/sudoers && \
    mkdir -p /home/openclaw/.openclaw ... && \
    chown -R openclaw:openclaw /home/openclaw
```
Cria usuário `openclaw` (UID 1000) com sudo sem senha. Pré-cria os diretórios que serão montados como volumes — isso garante que os named volumes herdem o dono correto (UID 1000) ao serem criados pelo Docker.

```dockerfile
COPY --chown=openclaw:openclaw openclaw/ /home/openclaw/.openclaw-seed/
```
Copia o `openclaw.json` de seed para dentro da imagem. O entrypoint copia esse seed para o volume apenas se ele estiver vazio (primeira execução).

```dockerfile
USER openclaw
```
A partir daqui tudo roda como `openclaw`. Crítico para o Claude Code funcionar.

---

## docker-compose.yml explicado

```yaml
volumes:
  - ./workspace:/home/openclaw/workspace        # pasta de trabalho acessível no host
  - openclaw-config:/home/openclaw/.openclaw    # configuração persistente do OpenClaw
  - ~/.claude:/home/openclaw/.claude            # credenciais do Claude Code (bind mount do host)
  - ~/.claude.json:/home/openclaw/.claude.json  # settings do Claude Code (bind mount do host)
```

Os dois últimos são **bind mounts** do host — não são volumes Docker gerenciados. Eles fazem o container enxergar a autenticação do Claude Code que já existe no host, evitando reautenticação a cada redeploy.

```yaml
ports:
  - "18789:18789"   # gateway WebSocket do OpenClaw
  - "8090:8090"     # portas auxiliares
  - "8091:8091"
```

```yaml
security_opt:
  - no-new-privileges:true
```
Impede que processos dentro do container escalem privilégios.

---

## entrypoint.sh explicado

```bash
copy_seed "$HOME_DIR/.openclaw-seed" "$HOME_DIR/.openclaw"
```
Copia o `openclaw.json` do seed para o volume persistente **somente se o volume estiver vazio**. Nas execuções seguintes, o OpenClaw usa e modifica o arquivo no volume diretamente.

```bash
exec "$OPENCLAW_CMD" gateway \
  --bind "${OPENCLAW_GATEWAY_BIND:-lan}" \
  --port "${OPENCLAW_GATEWAY_PORT:-18789}" \
  --allow-unconfigured
```
`--allow-unconfigured` é essencial: sem ele, o gateway recusa iniciar se alguma configuração estiver incompleta ou ausente, causando loop de restart.

---

## openclaw/openclaw.json explicado

```json
"agents": {
  "defaults": {
    "model": { "primary": "claude-cli/claude-sonnet-4-6" }
  }
}
```
Define `claude-cli` como provider. O OpenClaw vai chamar o binário `claude` internamente.

```json
"auth": {
  "profiles": {
    "anthropic:claude-cli": { "provider": "claude-cli", "mode": "oauth" }
  }
}
```
Diz ao OpenClaw para usar autenticação OAuth via Claude Code CLI (as credenciais em `~/.claude`).

```json
"channels": {
  "telegram": {
    "enabled": true,
    "botToken": "SEU_TOKEN_AQUI"
  }
}
```
Habilita o canal Telegram. Substitua pelo token do seu bot.

```json
"gateway": { "mode": "local", "bind": "lan", "port": 18789 }
```
`mode: local` — não exige auth configurado para o gateway iniciar. `bind: lan` — escuta em todas as interfaces da rede local.

---

## Como subir do zero

```bash
# 1. Clone ou copie o diretório openclaw_base para o servidor

# 2. Certifique-se de que o Claude Code está autenticado no host
claude  # faz login se necessário

# 3. Edite o token do Telegram no seed
nano openclaw/openclaw.json  # substitua "botToken"

# 4. Crie o .env (pode ficar vazio)
touch .env

# 5. Build e start
docker compose up -d --build

# 6. Verifique os logs
docker logs openclaw_lab -f
```

Procure por estas linhas nos logs para confirmar que está tudo ok:
```
agent model: claude-cli/claude-sonnet-4-6
ready (... telegram ...)
```

---

## Acesso ao container

```bash
# Shell como usuário openclaw (padrão)
docker exec -it openclaw_lab bash

# Shell como root (para instalar pacotes, etc.)
docker exec -it -u root openclaw_lab bash

# Usar sudo dentro do container
docker exec -it openclaw_lab sudo apt-get install -y pacote
```

---

## Redeploy sem perder configuração

```bash
# Rebuild sem apagar volumes (configuração preservada)
docker compose down
docker compose up -d --build

# ATENÇÃO: nunca use "docker compose down -v" em produção
# O flag -v apaga os named volumes (openclaw-config, fabric-config, sharepoint-config)
# e você perde toda a configuração acumulada pelo OpenClaw
```

---

## Problemas conhecidos e soluções

| Erro | Causa | Solução |
|---|---|---|
| `--dangerously-skip-permissions cannot be used with root` | Container rodando como root | O Dockerfile usa `USER openclaw` (UID 1000). Se isso sumir, o bot para de responder. |
| `Permission denied` nos volumes | Named volume criado como root antes do fix | `docker compose down -v && docker compose up -d --build` |
| `Claude configuration file not found at ~/.claude.json` | Bind mount do `.claude.json` ausente | Verifique se `~/.claude.json` existe no host e está no docker-compose |
| Gateway em loop de restart | Falta `--allow-unconfigured` no entrypoint | Verifique o `entrypoint.sh` |
| Telegram não aparece nos plugins | `openclaw.json` sem a seção `channels.telegram` | Verifique o seed; se o volume já existir, edite direto em `/home/openclaw/.openclaw/openclaw.json` dentro do container |
