# Correção da tela USB WAVLINK / SM768 no Ubuntu 24.04

![License](https://img.shields.io/badge/license-GPLv3-blue.svg)
![Platform](https://img.shields.io/badge/platform-Ubuntu%2024.04-orange)
![Session](https://img.shields.io/badge/session-Wayland%20%7C%20X11-informational)

[English](README.md) · **Português**

Faz os adaptadores de tela USB WAVLINK / Silicon Motion **SM768** (USB `090c:0768`)
funcionarem no **Ubuntu 24.04** com **GNOME/Wayland** — o cenário em que o driver
oficial da Silicon Motion deixa a máquina com **tela cinza no boot** e um monitor
USB que **acende e apaga** (fica preto) ao ser plugado.

A correção fica inteiramente na camada aberta (GPL) do EVDI. Ela **não** altera o
daemon fechado da Silicon Motion nem o firmware.

---

## Sintomas que isto resolve

- Depois de instalar o driver oficial, a área de trabalho abre em **cinza
  congelado**; só dá pra entrar pelo modo de recuperação.
- Ao plugar a tela USB, ela pisca ("universal graphic") e depois **apaga** — a
  área de trabalho nunca aparece nela.

## Causa raiz

São **dois** bugs independentes, ambos na camada aberta do EVDI — não no firmware:

1. **Crash do daemon ao plugar (`SIGSEGV`).** Ao plugar o monitor, o
   `SMIUSBDisplayManager` chama a função *deprecada* `evdi_open_attached_to(NULL)`
   para obter um device EVDI genérico. Na libevdi **1.15** esse wrapper executa
   `strlen(NULL)` antes de o `evdi_open_attached_to_fixed()` — que trata o `NULL`
   corretamente — sequer receber o ponteiro. O resultado é um null-pointer
   dereference que mata o daemon toda vez que uma tela é conectada.

2. **Tela cinza no boot (seleção de GPU).** O instalador oficial cria
   `/etc/modules-load.d/evdi.conf`, que **força o módulo `evdi` a carregar em todo
   boot** com quatro telas virtuais. Essas placas virtuais entram na corrida de
   inicialização bem quando a `amdgpu` está subindo, e o `mutter` (Wayland) às
   vezes escolhe o framebuffer de boot EFI (`simpledrm`) como GPU primária, falha
   ao renderizar (`gbm_surface_lock_front_buffer failed`) e mostra a tela cinza.

A correção é um guard de `NULL` de uma linha em `library/evdi_lib.c` (recompilado
na libevdi) mais impedir o `evdi` de carregar no boot — ele passa a subir sob
demanda ao plugar a tela, já com o display manager no ar.

## Pré-requisitos

- Ubuntu 24.04 (também deve funcionar em 23.04 / 22.04 / 20.04).
- O **driver oficial da Silicon Motion já instalado** (este repositório corrige o
  driver, não o substitui). Os arquivos do fabricante devem estar em
  `/opt/siliconmotion`.
- Ferramentas de build: `build-essential pkg-config patch libdrm-dev`.

```bash
sudo apt install build-essential pkg-config patch libdrm-dev
```

## Início rápido

```bash
git clone https://github.com/IMNascimento/wavlink_driver_ubuntu.git
cd wavlink_driver_ubuntu

./scripts/diagnose.sh     # 1. checagem read-only — não altera nada
sudo ./install.sh         # 2. aplica a correção
# 3. pluge a tela USB — deve acender sozinha
```

## Teste antes de aplicar de fato

Três níveis de checagem segura, nenhum deles altera o sistema de forma permanente:

| Comando | O que faz | Root? |
| --- | --- | --- |
| `./scripts/diagnose.sh` | Reporta SO, GPU, adaptador, status da correção, deps. Read-only. | não |
| `./install.sh --build-only` | Compila a libevdi corrigida num diretório temporário e verifica. Não instala nada. | não |
| `./install.sh --dry-run` | Imprime cada ação que *faria*. Não altera nada. | não |

Rode os três e leia a saída antes de executar o `sudo ./install.sh` de verdade.

## Uso

Depois de instalada, a tela é totalmente automática:

- **Plugar** o adaptador USB → o serviço sobe sob demanda (via a regra udev do
  fabricante), o `evdi` carrega e a área de trabalho se estende no monitor externo.
- **Desplugar** → o serviço para. Nada roda no boot, então o boot fica sempre limpo.

Configure o monitor externo (espelhar / estender / resolução) em
**Configurações → Telas**, como de costume.

## Reverter

Reversão completa ao estado padrão do fabricante:

```bash
sudo ./uninstall.sh        # use --dry-run para pré-visualizar
```

Isso restaura a libevdi original e a configuração de boot. Observe que restaurar a
configuração de boot do fabricante pode trazer de volta a tela cinza original; se
isso acontecer, basta neutralizar o serviço:

```bash
sudo systemctl mask smiusbdisplay.service
```

## Como funciona

| Arquivo | Papel |
| --- | --- |
| `patches/evdi-open-attached-to-null-guard.patch` | O guard de `NULL` de uma linha para `evdi_open_attached_to()`. |
| `scripts/diagnose.sh` | Checagem read-only do sistema. |
| `install.sh` | Compila a libevdi corrigida a partir do `evdi.tar.gz` do fabricante, faz backup da original, instala, desativa o force-load no boot e habilita o start sob demanda. |
| `uninstall.sh` | Reverte tudo ao estado padrão do fabricante. |

## Solução de problemas

- **`$SMI_DIR not found`** — instale o driver oficial da Silicon Motion primeiro;
  os arquivos do fabricante devem estar em `/opt/siliconmotion`.
- **`patch failed to apply`** — sua versão da libevdi difere da 1.15; o guard mira
  nessa versão.
- **Ainda cinza no boot** — confirme que `/etc/modules-load.d/evdi.conf` sumiu
  (o `./scripts/diagnose.sh` reporta isso) e, em último caso, mascare o serviço.

## Créditos e licença

O patch modifica a **libevdi**, licenciada sob **GPL** pela DisplayLink (UK) Ltd.
Este repositório é distribuído sob a **GPLv3** (veja [LICENSE](LICENSE)). Os
binários e o firmware da Silicon Motion **não** são redistribuídos aqui — você
precisa do driver oficial instalado.

Testado em: Ubuntu 24.04.4, kernel 6.17, GNOME/Wayland, APU AMD (Lucienne),
EVDI 1.15.0, adaptador `090c:0768`, tela externa 1920x1080@60.
