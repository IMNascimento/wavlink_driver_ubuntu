# Contribuindo para o WAVLINK SM768 USB Display Fix

Obrigado pelo interesse em contribuir! Estas são as diretrizes para começar.

## Processo de Contribuição

1. Faça um fork do repositório.
2. Crie sua branch de recurso (`git checkout -b feature/nome-da-sua-branch`).
3. Faça commits claros seguindo o padrão [Conventional Commits](https://www.conventionalcommits.org/)
   (`fix:`, `feat:`, `docs:`, ...).
4. Envie para a branch (`git push origin feature/nome-da-sua-branch`).
5. Abra um Pull Request na branch `main`.

## Padrões de Código

- Scripts em `bash` com `set -euo pipefail`.
- Nomeie variáveis e funções de forma descritiva.
- Adicione comentários apenas onde o "porquê" não é óbvio.
- Mantenha os scripts idempotentes e reversíveis.

## Testando suas mudanças

Este projeto não altera arquivos do sistema fora dos modos de instalação. Antes de
enviar, valide com os modos que não modificam nada:

```bash
./scripts/diagnose.sh          # checagem read-only
./install.sh --build-only      # compila a libevdi corrigida num diretório temporário
./install.sh --dry-run         # imprime cada ação sem executar
./uninstall.sh --dry-run       # pré-visualiza a reversão
```

Se for testar a instalação real, use uma máquina/VM com o driver oficial da Silicon
Motion instalado e descreva o ambiente (distro, kernel, sessão, GPU) no PR.

## Issues

Abra uma issue para reportar um bug ou sugerir melhoria. Inclua o máximo de detalhes
possível — o `ISSUE_TEMPLATE.md` lista os dados de ambiente úteis (a saída de
`./scripts/diagnose.sh` ajuda bastante).
