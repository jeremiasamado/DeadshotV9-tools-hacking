# Deadshot Tools

An optimized, refactored, and highly stable hub for essential cybersecurity tools on Kali Linux. From phishing and OSINT data gathering to mass testing frameworks, I organized everything securely in a single command-line interface.

## Why I created Deadshot Tools
This project is an evolution of standard hacking tool installers. I took the base concept of the ALHacking script and decided to rewrite the engine to fix critical structural flaws, adding features the original creator didn't think to implement:

- **Zero Directory Pollution:** I created a safe sandboxing system that ensures tools only clone inside an isolated `Tools/` folder, never polluting your main directory.

- **Improved Performance:** I added intelligent caching checks that prevent re-downloading existing repositories, saving massive time and internet bandwidth.

- **Refactored Engine:** I abandoned the old, fragile `if/elif` spaghetti loops in favor of a clean, crash-resistant core `case` structure.

## System Requirements
I rigorously tailored and tested the environment for:
* Linux (Debian Based Systems, specifically **Kali Linux**)
* Unix
* Termux (For Android mobile pentesting)

## How to Install and Run
Getting started is simple. Open your terminal and run:

1. `cd NE0SYNC`
2. Make the core script executable (first time only): 
   `chmod +x deadshot.sh`
3. Launch the dashboard: 
   `./deadshot.sh`

## Professional Configuration (DEADSHOT_CONFIG_FILE)
Deadshot supports an external config path via environment variable:

- Example (system-wide config):
  - `sudo DEADSHOT_CONFIG_FILE=/etc/deadshot/deadshot.conf ./deadshot.sh`
- Default behavior:
  - If `DEADSHOT_CONFIG_FILE` is not set, the core uses its local `deadshot.conf`.

## Deployment Notes (Public Repo)
- The public repo export is bytecode-first for hardening (Python `.pyc` inside `core/`).
- Iron Shield Build (UTC): 2026-04-26T16:09:30Z
- Verify integrity after cloning:
  - `sha256sum -c SHA256SUMS`

## Advanced Security Features
- Adaptive scheduling: optional jittered runtime interval to avoid synchronized polling bursts across fleets.
- Admin kill switch: local config/file-based disable toggle for maintenance windows and incident response.
- Sustained upload anomaly: runtime monitor can flag persistent high upload rates (reduces short spike false positives).

---

# Deadshot Tools (Versão Português - PT)

Este projeto é um hub otimizado e altamente estável que criei para agrupar as ferramentas reais de cibersegurança no Kali Linux. Desde phishing e recolha de inteligência (OSINT) a frameworks de ataque, organizei tudo de forma segura numa única interface de linha de comandos.

## Porque criei o Deadshot Tools
Peguei no conceito base de scripts de instalação passados (como o ALHacking) e decidi reescrever o motor para corrigir falhas estruturais críticas, melhorando imensas coisas em que o criador original não pensou:

- **Zero Poluição de Diretórios:** Criei um sistema de isolamento que garante que as ferramentas são clonadas apenas dentro de uma pasta `Tools/`, sem nunca sujar o teu diretório de raiz.

- **Performance Melhorada:** Implementei verificações inteligentes de cache que impedem o script de descarregar novamente repositórios que já existam na máquina, o que poupa tempo massivo e largura de banda.

- **Motor Refatorado:** Eliminei os ciclos antigos e frágeis de `if/elif` em favor de uma estrutura core limpa baseada em `case`, totalmente resistente a quebras.

## Requisitos do Sistema
O ambiente foi rigorosamente testado e talhado para:
* Linux (Sistemas baseados em Debian, especialmente **Kali Linux**)
* Unix
* Termux (Para pentesting em Android)

## Como Instalar e Executar
É simples começar. Abre o teu terminal e executa os seguintes comandos:

1. `cd NE0SYNC`
2. Atribui permissão de execução ao script (apenas na primeira vez): 
   `chmod +x deadshot.sh`
3. Lança o painel de controlo: 
   `./deadshot.sh`

## Configuração Profissional (DEADSHOT_CONFIG_FILE)
O Deadshot suporta override do ficheiro de configuração via variável de ambiente:

- Exemplo (config do sistema):
  - `sudo DEADSHOT_CONFIG_FILE=/etc/deadshot/deadshot.conf ./deadshot.sh`
- Comportamento padrão:
  - Se `DEADSHOT_CONFIG_FILE` não estiver definido, o core usa o `deadshot.conf` local.

## Notas de Deploy (Repo Público)
- O repo público é exportado em modo bytecode-first (Python `.pyc` dentro de `core/`).
- Iron Shield Build (UTC): 2026-04-26T16:09:30Z
- Verifica a integridade depois de clonar:
  - `sha256sum -c SHA256SUMS`

## Advanced Security Features
- Agendamento adaptativo: jitter opcional no intervalo do runtime para evitar bursts sincronizados em frotas.
- Kill switch de admin: toggle local (config/ficheiro) para desativação em janelas de manutenção/incidente.
- Anomalia de upload sustentado: monitor de runtime foca em fluxos constantes (menos falsos positivos de picos curtos).
