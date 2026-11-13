# atieclxx-fix (guia rápido em português)

O `atieclxx.exe` (AMD External Events Utility), que vem com o driver AMD Radeon, tem um bug: a cada segundo ele copia o próprio arquivo (677 KB) para o disco do sistema, o que dá **40–55 GB por dia**, mesmo com o PC parado. Esta correção bloqueia só essa cópia. O serviço da AMD continua rodando, então FreeSync e atalhos continuam funcionando.

Explicação completa (em inglês): [README](../README.md)

## Ainda preciso disso?

A AMD corrigiu o bug no **Adrenalin 26.11.1** (12 de novembro de 2026) para RX 7000 e mais novas. Placas Polaris e Vega ainda não foram corrigidas.

| Sua placa | O que fazer |
|---|---|
| **RX 7000, RX 9000** | Atualize para o Adrenalin 26.11.1. Se você aplicou esta correção, rode de novo e aperte **F**: ela remove o bloqueio quando o driver novo não precisa mais dele. |
| **RX 5000, RX 6000** | Não aparecem nas notas da AMD, e uma RX 6950 XT ainda tem o bug no 26.11.1. Aperte **C**. Se aparecer AFFECTED, aperte **F**. |
| **Série RX 400/500 (como a RX 580), Vega** | **A AMD ainda não corrigiu. Use esta correção (passos abaixo).** |

## Como usar

1. Baixe o **[atieclxx-fix.zip](https://github.com/candygoogy/atieclxx-fix/releases/latest/download/atieclxx-fix.zip)** e extraia (botão direito → **Extrair Tudo**). Rodar de dentro do zip não funciona.
2. Dê dois cliques em **`Fix-SSD-Writes.cmd`** e aceite o pedido de administrador.
3. Aperte **F**.

O script mede as gravações, aplica a correção e mede de novo, para você ver o número cair para zero. Se o seu PC não tiver o problema, ele não muda nada.

- **C**: só verifica, sem mudar nada. `AFFECTED` quer dizer afetado; `OK` quer dizer que está tudo certo.
- **U**: desfaz a correção.
- Se o Windows mostrar "O Windows protegeu o computador", clique em **Mais informações → Executar assim mesmo**. O Windows mostra isso para qualquer script baixado da internet. A correção inteira é um único arquivo PowerShell que dá para ler.
- Depois de atualizar o driver da AMD, rode de novo e aperte **F**.

Dúvidas ou resultados? Abra uma [issue](https://github.com/candygoogy/atieclxx-fix/issues) (pode ser em português) com a saída do **C**.
