# Correção da tela USB WAVLINK / SM768 no Ubuntu 24.04

![License](https://img.shields.io/badge/license-GPLv3-blue.svg)
![Platform](https://img.shields.io/badge/platform-Ubuntu%2024.04-orange)
![Session](https://img.shields.io/badge/session-Wayland%20%7C%20X11-informational)

[English](README.md) · **Português**

Faz os adaptadores de tela USB WAVLINK / Silicon Motion **SM768** (USB `090c:0768`)
funcionarem no **Ubuntu 24.04** com **GNOME/Wayland**, o cenário em que o driver
oficial da Silicon Motion deixa a máquina com **tela cinza no boot** e um monitor
USB que **acende e apaga** (fica preto) ao ser plugado.

A correção fica inteiramente na camada aberta (GPL) do EVDI. Ela **não** altera o
daemon fechado da Silicon Motion nem o firmware.

---

## Sintomas que isto resolve

- O **instalador oficial aborta** no kernel do Ubuntu 24.04 (6.8+): termina com
  `Failed to install evdi ... to the kernel` / `bad exit status: 2`, se reverte
  sozinho e o driver nunca é instalado (`/opt/siliconmotion` não é criado).
- Depois de instalar o driver, a área de trabalho abre em **cinza congelado**; só
  dá pra entrar pelo modo de recuperação.
- Ao plugar a tela USB, ela pisca ("universal graphic") e depois **apaga**, a
  área de trabalho nunca aparece nela.

## Causa raiz

São **três** problemas, todos na camada aberta do EVDI, nenhum no firmware. O
primeiro ocorre na instalação; os outros dois na área de trabalho, depois de
instalar.

0. **Instalador aborta em kernels novos (falha de build).** O `.run` do fabricante
   embute o **EVDI 1.14.7** (nov/2024). O build via DKMS não compila no kernel
   **6.8+** (a API interna de DRM do kernel mudou), então falha com
   `bad exit status: 2`, o instalador se reverte e nada é instalado. Corrigido
   trocando o EVDI embutido pela versão **1.15.0** (jul/2026), que compila nos
   kernels atuais; veja o [Passo 0](#passo-0-fazer-o-driver-oficial-instalar).

1. **Crash do daemon ao plugar (`SIGSEGV`).** Ao plugar o monitor, o
   `SMIUSBDisplayManager` chama a função *deprecada* `evdi_open_attached_to(NULL)`
   para obter um device EVDI genérico. Na libevdi **1.15** esse wrapper executa
   `strlen(NULL)` antes de o `evdi_open_attached_to_fixed()`, que trata o `NULL`
   corretamente, sequer receber o ponteiro. O resultado é um null-pointer
   dereference que mata o daemon toda vez que uma tela é conectada.

2. **Tela cinza no boot (seleção de GPU).** O instalador oficial cria
   `/etc/modules-load.d/evdi.conf`, que **força o módulo `evdi` a carregar em todo
   boot** com quatro telas virtuais. Essas placas virtuais entram na corrida de
   inicialização bem quando a `amdgpu` está subindo, e o `mutter` (Wayland) às
   vezes escolhe o framebuffer de boot EFI (`simpledrm`) como GPU primária, falha
   ao renderizar (`gbm_surface_lock_front_buffer failed`) e mostra a tela cinza.

A correção é um guard de `NULL` de uma linha em `library/evdi_lib.c` (recompilado
na libevdi) mais impedir o `evdi` de carregar no boot. Ele passa a subir sob
demanda ao plugar a tela, já com o display manager no ar.

## Pré-requisitos

- Ubuntu 24.04 (também deve funcionar em 23.04 / 22.04 / 20.04).
- O **driver oficial da Silicon Motion instalado** em `/opt/siliconmotion` (este
  repositório corrige o driver, não o substitui). No kernel **6.8+** o instalador
  do fabricante não conclui sozinho, então faça o [Passo 0](#passo-0-fazer-o-driver-oficial-instalar)
  antes. Baixe o driver no centro de downloads da WAVLINK e escolha o seu modelo
  com chip SM768 (ex.: WL-UG7601HC / WL-UG7602HC):
  <https://www.wavlink.com/en_us/drivers.html>
- Ferramentas de build: `build-essential pkg-config patch libdrm-dev`.

```bash
sudo apt install build-essential pkg-config patch libdrm-dev
```

## Ambiente em que testamos

| Componente | Versão |
| --- | --- |
| Distribuição | Ubuntu 24.04.4 LTS (Noble Numbat) |
| Kernel | 6.17.0-35-generic |
| Ambiente gráfico | GNOME Shell 46.0 |
| Servidor gráfico / interface | **Wayland** (também funciona no X11) |
| Gerenciador de login | GDM3 |
| Driver de GPU | AMD `amdgpu` (APU Lucienne) |
| EVDI / libevdi | 1.15.0 |
| Adaptador USB | WAVLINK WL-UG7602HC (Silicon Motion SM768), `090c:0768` |
| Tela externa | 1920x1080 @ 60 Hz |

## Passo 0: fazer o driver oficial instalar

Faça isto só se o instalador oficial falhou (kernel 6.8+). Ele não mexe no pacote
do fabricante: escreve uma cópia corrigida ao lado, com o EVDI 1.14.7 embutido
substituído pelo 1.15.0, para o build via DKMS passar.

```bash
# aponte para o instalador do fabricante (download WAVLINK, SMIUSBDisplay-driver.*.run)
./scripts/prepare-vendor-driver.sh --run "SMIUSBDisplay-driver.2.22.1.0.run"

# ou para uma pasta do fabricante já extraída:
./scripts/prepare-vendor-driver.sh --dir "SMIUSBDisplay"
```

Ele imprime o caminho da pasta corrigida; instale o driver do fabricante a partir
dela:

```bash
cd <pasta-que-ele-imprimiu>      # ex.: SMIUSBDisplay-patched-evdi1.15.0
sudo ./install.sh                # agora o build do EVDI passa → Installation complete!
```

Ele roda **totalmente offline**: o source do EVDI 1.15.0 vem embutido neste repo
(`third_party/evdi-1.15.0.tar.gz`), então nada é baixado. O único arquivo que você
busca é o driver do fabricante, que é fechado e não pode ser redistribuído aqui.

Opções: `--evdi-src <dir|tarball>` para apontar outro source local do EVDI,
`--evdi-tag <tag>` para clonar outra release do GitHub em vez do embutido,
`--dry-run` para pré-visualizar, `--help` para todas as opções.

**Secure Boot:** sem passo extra. O DKMS assina o módulo EVDI com a chave MOK já
matriculada na máquina (`/var/lib/shim-signed/mok/MOK.der`), a mesma que o Ubuntu
usa para o VirtualBox e outros módulos DKMS. Você não cria nem matricula uma chave
nova. Confira com `mokutil --sb-state`.

Com o driver do fabricante instalado, siga para a correção da área de trabalho abaixo.

## Início rápido

```bash
git clone https://github.com/IMNascimento/wavlink_driver_ubuntu.git
cd wavlink_driver_ubuntu

# 0. só se o instalador oficial falhou no kernel 6.8+ (veja o Passo 0 acima):
./scripts/prepare-vendor-driver.sh --run "SMIUSBDisplay-driver.2.22.1.0.run"

./scripts/diagnose.sh     # 1. checagem read-only, não altera nada
sudo ./install.sh         # 2. aplica a correção da área de trabalho
# 3. pluge a tela USB, deve acender sozinha
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
| `scripts/prepare-vendor-driver.sh` | Passo 0: reempacota o `evdi.tar.gz` do fabricante com o EVDI 1.15.0 para o instalador oficial compilar no kernel 6.8+. |
| `third_party/evdi-1.15.0.tar.gz` | Source do EVDI 1.15.0 embutido para o Passo 0 rodar offline. |
| `patches/evdi-open-attached-to-null-guard.patch` | O guard de `NULL` de uma linha para `evdi_open_attached_to()`. |
| `scripts/diagnose.sh` | Checagem read-only do sistema. |
| `install.sh` | Compila a libevdi corrigida a partir do `evdi.tar.gz` do fabricante, faz backup da original, instala, desativa o force-load no boot e habilita o start sob demanda. |
| `uninstall.sh` | Reverte tudo ao estado padrão do fabricante. |

## Solução de problemas

- **Instalador oficial termina com `Failed to install evdi` / `bad exit status: 2`**:
  o EVDI 1.14.7 embutido não compila no kernel 6.8+. Rode o
  [Passo 0](#passo-0-fazer-o-driver-oficial-instalar)
  (`./scripts/prepare-vendor-driver.sh`) e instale a partir da cópia corrigida.
- **`$SMI_DIR not found`**: o driver oficial da Silicon Motion ainda não está
  instalado; os arquivos do fabricante devem estar em `/opt/siliconmotion`. Se o
  instalador dele abortar, veja o item acima.
- **`patch failed to apply`**: sua versão da libevdi difere da 1.15; o guard mira
  nessa versão.
- **Ainda cinza no boot**: confirme que `/etc/modules-load.d/evdi.conf` sumiu
  (o `./scripts/diagnose.sh` reporta isso) e, em último caso, mascare o serviço.

## Créditos e licença

O patch modifica a **libevdi**, licenciada sob **GPL** pela DisplayLink (UK) Ltd.
Este repositório é distribuído sob a **GPLv3** (veja [LICENSE](LICENSE)). Os
binários e o firmware da Silicon Motion **não** são redistribuídos aqui; você
precisa do driver oficial instalado (veja o link de download da WAVLINK em
[Pré-requisitos](#pré-requisitos)).

Veja [Ambiente em que testamos](#ambiente-em-que-testamos) para as versões exatas.

## Autor

Desenvolvido e mantido por [@IMNascimento](https://github.com/IMNascimento), dev principal.
