# Architecture — OpenClaw sur Azure

> Document pédagogique — état au 25 mars 2026
> Infrastructure : `terraform-azurerm-openclaw` · VM Azure westeurope

---

## Vue d'ensemble

OpenClaw est une interface web pour agents AI. Elle est déployée sur une VM Azure Ubuntu 24.04, accessible depuis Internet via HTTPS, et utilise Azure OpenAI comme moteur LLM via un proxy (LiteLLM).

---

## Schéma d'architecture

```
┌─────────────────────────────────────────────────────────────┐
│  INTERNET                                                    │
│                                                             │
│  Utilisateur → https://openclaw.example.com        │
└────────────────────────┬────────────────────────────────────┘
                         │
                         ▼
┌────────────────── AWS Route53 ──────────────────────────────┐
│  A record : openclaw.example.com → &lt;VM_IP&gt;  │
└────────────────────────┬────────────────────────────────────┘
                         │
                         ▼
┌────────────── Azure NSG (Network Security Group) ───────────┐
│  Filtre réseau Azure — AVANT d'atteindre la VM              │
│                                                             │
│  ✅ ALLOW  :22   TCP  — SSH (IP restreinte uniquement)      │
│  ✅ ALLOW  :80   TCP  — HTTP  (tout Internet)               │
│  ✅ ALLOW  :443  TCP  — HTTPS (tout Internet)               │
│  ❌ DENY   tout le reste (règle DenyAllInbound, prio 4096)  │
└────────────────────────┬────────────────────────────────────┘
                         │
                         ▼
┌────────────── VM Ubuntu 24.04  (&lt;VM_IP&gt;) ────────────┐
│                                                             │
│  UFW (pare-feu OS)                                          │
│  ✅ ALLOW  :22   TCP  — SSH                                 │
│  ✅ ALLOW  :80   TCP  — HTTP                                │
│  ✅ ALLOW  :443  TCP  — HTTPS                               │
│  ❌ DENY   tout le reste par défaut                         │
│                                                             │
│  ┌──────────────── Docker Compose ───────────────────────┐ │
│  │  Réseau interne : openclaw_default (bridge)           │ │
│  │                                                       │ │
│  │  ┌─────────────────────────────────────────────────┐  │ │
│  │  │  Traefik v3.3  (reverse proxy + TLS)            │  │ │
│  │  │                                                 │  │ │
│  │  │  Ports publics :                                │  │ │
│  │  │    0.0.0.0:80  → redirect HTTPS                 │  │ │
│  │  │    0.0.0.0:443 → HTTPS (Let's Encrypt)          │  │ │
│  │  │                                                 │  │ │
│  │  │  Port interne (loopback uniquement) :           │  │ │
│  │  │    127.0.0.1:8080 → dashboard Traefik           │  │ │
│  │  │                                                 │  │ │
│  │  │  Routing par Host header :                      │  │ │
│  │  │    openclaw.example.com                │  │ │
│  │  │      → openclaw-gateway:18789                   │  │ │
│  │  └────────────────────┬────────────────────────────┘  │ │
│  │                       │ HTTP interne                   │ │
│  │                       ▼                                │ │
│  │  ┌─────────────────────────────────────────────────┐  │ │
│  │  │  OpenClaw Gateway (node.js)                     │  │ │
│  │  │                                                 │  │ │
│  │  │  Interface web AI — conversations, agents       │  │ │
│  │  │  Auth : token OPENCLAW_GATEWAY_TOKEN            │  │ │
│  │  │  Pairing : approbation des appareils clients    │  │ │
│  │  │                                                 │  │ │
│  │  │  Port interne (loopback uniquement) :           │  │ │
│  │  │    127.0.0.1:18789 → SSH tunnel                 │  │ │
│  │  │    127.0.0.1:18790 → bridge SSH tunnel          │  │ │
│  │  │                                                 │  │ │
│  │  │  Hardening :                                    │  │ │
│  │  │    cap_drop: ALL, no-new-privileges             │  │ │
│  │  │    read_only filesystem, tmpfs /tmp             │  │ │
│  │  └────────────────────┬────────────────────────────┘  │ │
│  │                       │ HTTP interne (réseau Docker)   │ │
│  │                       │ ANTHROPIC_BASE_URL=            │ │
│  │                       │   http://litellm:4000          │ │
│  │                       ▼                                │ │
│  │  ┌─────────────────────────────────────────────────┐  │ │
│  │  │  LiteLLM (proxy LLM)                            │  │ │
│  │  │                                                 │  │ │
│  │  │  Traduit les appels Anthropic → Azure OpenAI    │  │ │
│  │  │  Master key : openclaw-litellm                  │  │ │
│  │  │  drop_params: true (ignore params inconnus)     │  │ │
│  │  │                                                 │  │ │
│  │  │  Port interne (loopback uniquement) :           │  │ │
│  │  │    127.0.0.1:4000                               │  │ │
│  │  │                                                 │  │ │
│  │  │  Hardening :                                    │  │ │
│  │  │    cap_drop: ALL, no-new-privileges             │  │ │
│  │  └────────────────────┬────────────────────────────┘  │ │
│  │                       │ HTTPS                          │ │
│  └───────────────────────┼────────────────────────────────┘ │
│                          │                                   │
│  Key Vault (Azure)       │                                   │
│  ┌───────────────────┐   │                                   │
│  │ azure-openai-     │   │                                   │
│  │ api-key (secret)  │   │                                   │
│  │                   │   │                                   │
│  │ Managed Identity  │   │                                   │
│  │ → fetchée au boot │   │                                   │
│  │ via IMDS          │   │                                   │
│  └───────────────────┘   │                                   │
└──────────────────────────┼──────────────────────────────────┘
                           │ HTTPS
                           ▼
┌──────────────── Azure OpenAI ───────────────────────────────┐
│  YOUR_RESOURCE.openai.azure.com                │
│  Déploiement : my-gpt4-deployment (gpt-4.1-mini)            │
└─────────────────────────────────────────────────────────────┘
```

---

## Rôle de chaque composant

### Traefik — Reverse proxy

Traefik est la **seule porte d'entrée publique** de l'infrastructure. Il s'occupe de :

- **TLS/HTTPS automatique** : obtient et renouvelle les certificats Let's Encrypt sans intervention manuelle
- **Redirection HTTP → HTTPS** : port 80 redirige automatiquement vers 443
- **Routing** : regarde le `Host` header de chaque requête et l'envoie au bon service Docker interne
- **Dashboard** : interface d'administration accessible uniquement en local (SSH tunnel)

### OpenClaw Gateway — Interface AI

C'est l'application principale. Elle fournit :

- Une interface web pour créer et gérer des agents AI
- Un système d'authentification par token (pairing des appareils)
- Le support de plusieurs canaux (web, Telegram, Teams…)
- Une API WebSocket pour les clients

OpenClaw est configuré pour appeler l'API Anthropic, mais `ANTHROPIC_BASE_URL` la redirige vers LiteLLM au lieu de l'API officielle Anthropic.

### LiteLLM — Proxy LLM

LiteLLM est un **traducteur de protocole**. Il reçoit des requêtes au format Anthropic et les retransmet au format Azure OpenAI.

```
OpenClaw → "POST /v1/messages" (format Anthropic)
                  ↓
            LiteLLM traduit
                  ↓
Azure OpenAI → "POST /chat/completions" (format OpenAI)
```

Sans LiteLLM, il faudrait modifier OpenClaw ou payer Anthropic directement. LiteLLM permet de **réutiliser le compte Azure OpenAI déjà disponible**.

### Azure Key Vault — Coffre-fort secrets

La clé API Azure OpenAI n'est jamais stockée en clair dans les fichiers. Au démarrage de la VM :

1. Le service systemd `openclaw-fetch-secrets` s'exécute
2. Il contacte l'**IMDS** (Instance Metadata Service, `169.254.169.254`) — un endpoint Azure local à la VM
3. L'IMDS retourne un token d'authentification basé sur la **Managed Identity** de la VM
4. Ce token est utilisé pour récupérer le secret depuis Key Vault
5. La clé est injectée dans `~/openclaw/.env`

---

## Sécurité — audit complet

### Couche 1 — Réseau Azure (NSG)

Le NSG est le **premier filtre**, au niveau réseau Azure, avant même d'atteindre la VM.

| Port | Protocole | Accès | Raison |
|------|-----------|-------|--------|
| 22 | TCP | IP restreinte uniquement | SSH admin |
| 80 | TCP | Internet | Let's Encrypt + redirect HTTPS |
| 443 | TCP | Internet | Interface OpenClaw |
| Tout le reste | * | DENY (prio 4096) | Catch-all explicite |

### Couche 2 — Pare-feu OS (UFW)

UFW fonctionne en complément du NSG. Même règles, mais au niveau OS :

```
Status: active
Default: deny (incoming), allow (outgoing)

✅ 22/tcp   ALLOW — SSH
✅ 80/tcp   ALLOW — HTTP
✅ 443/tcp  ALLOW — HTTPS
```

> **Note Docker/UFW** : Docker modifie iptables directement et peut contourner UFW. C'est pourquoi les ports sensibles (4000, 8080, 18789) sont bindés sur `127.0.0.1` et non `0.0.0.0` — même si Docker bypassait UFW, ils resteraient inaccessibles depuis l'extérieur.

### Couche 3 — Ports Docker (bindings)

Résultat de `ss -tlnp` sur la VM :

| Port | Binding | Accessible depuis |
|------|---------|-------------------|
| 80 | `0.0.0.0` | Internet (via NSG) |
| 443 | `0.0.0.0` | Internet (via NSG) |
| 22 | `0.0.0.0` | IP restreinte (via NSG) |
| 4000 | `127.0.0.1` | VM uniquement |
| 8080 | `127.0.0.1` | VM uniquement |
| 18789 | `127.0.0.1` | VM uniquement (SSH tunnel) |
| 18790 | `127.0.0.1` | VM uniquement (SSH tunnel) |

### Couche 4 — Hardening containers Docker

| Container | cap_drop | no-new-privileges | read_only |
|-----------|----------|-------------------|-----------|
| traefik | — | — | — |
| openclaw-gateway | ALL | ✅ | ✅ |
| openclaw-cli | NET_RAW, NET_ADMIN | ✅ | — |
| litellm | ALL | ✅ | — |

### Couche 5 — SSH

| Paramètre | Valeur | Effet |
|-----------|--------|-------|
| `PasswordAuthentication` | `no` | Connexion par clé uniquement |
| `PermitRootLogin` | `no` | Impossible de se connecter en root |
| `MaxAuthTries` | `3` | Bloque après 3 tentatives |
| fail2ban | actif | Ban automatique après 5 échecs SSH |

### Couche 6 — Secrets

| Secret | Stockage | Mécanisme |
|--------|----------|-----------|
| `AZURE_OPENAI_API_KEY` | Azure Key Vault | Managed Identity IMDS, fetchée au boot |
| `OPENCLAW_GATEWAY_TOKEN` | `~/.env` (chmod 600) | Généré aléatoirement à l'install |
| `TELEGRAM_BOT_TOKEN` | `~/.env` (chmod 600) | Manuel |
| Clé SSH admin | `~/.ssh/openclaw.pem` (chmod 600) | Terraform output ou clé fournie |

---

## Flux d'une requête utilisateur

```
1. Utilisateur ouvre https://openclaw.example.com

2. DNS : Route53 résout → &lt;VM_IP&gt;

3. Azure NSG : port 443 → ALLOW

4. Traefik reçoit la requête HTTPS
   → vérifie le certificat Let's Encrypt
   → lit le Host header "openclaw.example.com"
   → route vers openclaw-gateway:18789 (HTTP interne)

5. OpenClaw Gateway traite la requête
   → authentifie l'appareil (token de pairing)
   → l'utilisateur envoie un message à l'agent AI

6. OpenClaw appelle "l'API Anthropic"
   → ANTHROPIC_BASE_URL pointe vers http://litellm:4000

7. LiteLLM traduit l'appel Anthropic → Azure OpenAI
   → récupère AZURE_OPENAI_API_KEY depuis l'environnement
   → appelle YOUR_RESOURCE.openai.azure.com

8. Azure OpenAI répond
   → LiteLLM retransmet → OpenClaw → Traefik → Utilisateur
```

---

## Accès SSH tunnel (développeur)

Pour accéder aux interfaces internes sans les exposer :

```bash
# Tunnel HTTPS + dashboard Traefik
make tunnel-https
# Ouvre :
#   https://openclaw.local:8443  → interface OpenClaw
#   http://localhost:8080         → dashboard Traefik

# Tunnel gateway direct (debug)
make tunnel
# Ouvre :
#   http://localhost:18789 → gateway sans TLS
```

---

## Infrastructure Terraform

| Ressource Azure | Nom | Description |
|-----------------|-----|-------------|
| Resource Group | `rg-openclaw` | Conteneur de toutes les ressources |
| Virtual Network | `vnet-openclaw` | Réseau privé 10.0.0.0/16 |
| Subnet | `snet-openclaw` | Sous-réseau 10.0.1.0/24 |
| NSG | `nsg-openclaw` | Règles firewall réseau |
| Public IP | `pip-openclaw` | IP statique Standard SKU |
| VM | Ubuntu 24.04 LTS | Standard_B2ms (2 vCPU / 8 GB) |
| Key Vault | `openclaw-kv-xxx` | Secrets, soft-delete + purge protection |
| Managed Identity | système | Accès Key Vault sans credentials |
