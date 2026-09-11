# 📖 Guia de Uso e Configuração - Validador Fiscal CT-e vs NF-e

Este guia instrui como a regra de validação fiscal atua no processo de entrada de mercadorias no sistema ERP, quais configurações influenciam sua execução e como lidar com mensagens de bloqueio.

## 1. Como a Validação Funciona?
O script é engatilhado no exato momento em que um usuário tenta confirmar/integrar um pacote de notas (Ex: NF-e modelo 55 + CT-e modelo 57) no módulo fiscal. 
A rotina inspeciona em tempo real:
1. Se a nota fiscal de Conhecimento de Transporte (CT-e) compõe custo (Conta Contábil baseada na máscara `113%`).
2. Se a nota da mercadoria associada (NF-e) está parametrizada para movimentar estoque na tríade:
   - **Tipo do Documento**
   - **Cadastro do Item**
   - **CFOP da operação**

## 2. Cenários de Comportamento

| Condição Frete (CT-e) | Condição Produto (NF-e) | Resultado da Ação |
|-----------------------|-------------------------|-------------------|
| Gera Estoque (SIM) | Gera Estoque (SIM p/ Tipo, Item e CFOP) | ✅ Integração Permitida |
| Não Gera Estoque (NÃO) | Gera Estoque (SIM p/ Tipo, Item e CFOP) | ❌ Bloqueado |
| Gera Estoque (SIM) | Não Gera Estoque (Em qualquer variável) | ❌ Bloqueado |
| Não Gera Estoque (NÃO) | Não Gera Estoque | ✅ Integração Permitida |

## 3. Resolvendo Erros de Execução (Troubleshooting)

### Erro: `Divergência: NF e CT-e devem ser iguais no estoque (ambos movimentam ou nenhum movimenta). Revise!`
**Causa:** O usuário está tentando associar um frete que foi lançado em uma conta de despesa (não agrega ao estoque) com uma nota fiscal de entrada de mercadorias para revenda (que movimenta o estoque), ou vice-versa.
**Como Resolver:**
1. Verifique a aba de 'Referência' do documento.
2. Cheque o **CFOP** utilizado na nota da mercadoria. Ele está marcado para compor estoque?
3. Se a mercadoria é de Consumo (não gera estoque), certifique-se de que o CT-e correspondente também foi lançado em conta de despesa contábil (e não máscara 113...).
4. Corrija a operação divergente e tente integrar novamente.

## 4. Requisitos para Desenvolvedores (Manutenção)
Caso ocorra uma expansão de plano de contas na empresa, certifique-se de validar a condição abaixo no bloco SQL:
```sql
-- Caso o grupo contábil de estoque mude (atualmente 113%), atualizar esta cláusula:
UPPER(nit.codigo_item) LIKE '%FRETE%' AND ct.mascara_conta LIKE '113%'
```
