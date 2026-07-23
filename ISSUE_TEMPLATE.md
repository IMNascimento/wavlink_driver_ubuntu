# Template de Issue — WAVLINK SM768 USB Display Fix

## Descrição do Problema

Descreva claramente o problema. Qual comportamento você esperava? O que aconteceu?

## Passos para Reproduzir

1. ...
2. ...
3. Veja o erro

## Ambiente

Cole a saída de `./scripts/diagnose.sh` ou preencha manualmente:

- Distribuição e versão: [ex.: Ubuntu 24.04.4 LTS]
- Kernel: [ex.: 6.17.0-35-generic]
- Ambiente gráfico: [ex.: GNOME Shell 46.0]
- Sessão: [Wayland ou X11]
- GPU / driver: [ex.: AMD amdgpu (Lucienne)]
- Versão do EVDI / libevdi: [ex.: 1.15.0]
- Adaptador USB (`lsusb`): [ex.: 090c:0768]

## Logs relevantes

Anexe, se possível, a saída de:

```bash
journalctl -b -t SMIUSBDisplayManager
```
