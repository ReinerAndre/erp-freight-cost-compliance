-- =====================================================================
-- SCRIPT: VALIDADOR DE INTEGRIDADE DE CUSTOS (CT-E VS NF-E)
-- OBJETIVO: Garantir que fretes e notas de origem tenham o mesmo 
--           comportamento de apropriação de custos no estoque.
-- =====================================================================

DECLARE
    v_validador_status NUMBER := 0;
    v_empresa_id       NUMBER;
    v_usuario_id       NUMBER;
    v_sequencia_doc    NUMBER;

BEGIN
    -- 1. IDENTIFICAÇÃO DOS FRETES (CT-e - Modelo 57)
    -- Seleciona os documentos de transporte associados ao processo de entrada
    -- e determina se o item de frete está configurado para compor o custo do estoque.
    FOR r_frete IN (
        SELECT 
            nf.id_empresa,
            nf.id_usuario,
            nf.id_tipo_documento,
            nf.numero_documento,
            nf.data_entrada,
            nf.sequencia,
            nf.chave_acesso_nfe,
            ref.chave_acesso_ref,
            nit.codigo_item,
            it.conta_contabil AS it_conta,
            -- Regra de negócio: Identifica se é uma conta de frete que deve gerar estoque
            CASE 
                WHEN UPPER(nit.codigo_item) LIKE '%FRETE%' AND ct.mascara_conta LIKE '113%' 
                THEN 'S' 
                ELSE 'N' 
            END AS flag_gera_estoque
        FROM erp_nota_fiscal_tmp nf
        INNER JOIN erp_item_nota_tmp nit
            ON  nit.id_empresa = nf.id_empresa
            AND nit.id_usuario = nf.id_usuario
            AND nit.sequencia_nota = nf.sequencia
        INNER JOIN erp_item_estoque it
            ON  it.id_empresa = nit.id_empresa
            AND it.codigo_item = nit.codigo_item
        LEFT JOIN erp_conta_contabil ct
            ON  ct.id_empresa = it.id_empresa
            AND ct.codigo_conta = it.conta_contabil 
        INNER JOIN erp_cfop_variacao cfo
            ON  cfo.codigo_cfop = nit.codigo_cfop
            AND cfo.variacao_cfop = nit.variacao_cfop
        INNER JOIN erp_nfe_referencia ref
            ON  ref.chave_acesso_nfe = nf.chave_acesso_nfe
        WHERE nf.id_empresa = v_empresa_id
          AND nf.id_usuario = v_usuario_id
          AND nf.sequencia = v_sequencia_doc
          AND nf.modelo_documento = '57' -- Filtro de Conhecimento de Transporte (CT-e)
          AND nf.id_tipo_documento NOT IN (10, 59, 60, 61, 62, 63, 65, 66, 67)
    )
    LOOP

        -- 2. VERIFICAÇÃO DA NOTA FISCAL REFERENCIADA (NF-e - Modelo 55)
        -- Busca a nota fiscal de origem ligada ao frete e avalia a matriz de 
        -- configurações (Tipo Doc, Item e CFOP) para garantir que ela gera estoque.
        FOR r_frete_ref IN (
            SELECT 
                nf.id_empresa,
                nf.chave_acesso_nfe,
                nit.codigo_item,
                tpdc.flag_integra_estoque AS tpdoc_estoque,
                it.flag_gera_estoque      AS it_estoque,
                cfo.flag_integra_estoque  AS cfo_estoque,
                -- Cria uma matriz de status validando todas as pontas da configuração
                tpdc.flag_integra_estoque || it.flag_gera_estoque || cfo.flag_integra_estoque AS matriz_estoque
            FROM erp_nota_fiscal_tmp nf
            INNER JOIN erp_item_nota_tmp nit
                ON  nit.id_empresa = nf.id_empresa
                AND nit.id_usuario = nf.id_usuario
                AND nit.sequencia_nota = nf.sequencia
            INNER JOIN erp_item_estoque it
                ON  it.id_empresa = nit.id_empresa
                AND it.codigo_item = nit.codigo_item
            LEFT JOIN erp_conta_contabil ct
                ON  ct.id_empresa = it.id_empresa
                AND ct.codigo_conta = it.conta_contabil 
            INNER JOIN erp_cfop_variacao cfo
                ON  cfo.codigo_cfop = nit.codigo_cfop
                AND cfo.variacao_cfop = nit.variacao_cfop
            INNER JOIN erp_tipo_documento tpdc
                ON  tpdc.codigo_tipo = nf.id_tipo_documento
            WHERE nf.id_empresa = v_empresa_id
              AND nf.id_tipo_documento NOT IN (17)
              AND nf.chave_acesso_nfe = r_frete.chave_acesso_ref
              AND nf.modelo_documento = 55 -- Filtro de Nota Fiscal de Produto (NF-e)
        )
        LOOP
            -- 3. MOTOR DE REGRAS COMPORTAMENTAIS
            -- Compara as diretrizes contábeis do Frete vs Nota Fiscal
            IF r_frete.flag_gera_estoque = 'S' AND r_frete_ref.matriz_estoque LIKE 'SSS' THEN
                v_validador_status := COALESCE(v_validador_status, 0) + 1;
            ELSIF r_frete.flag_gera_estoque = 'N' AND r_frete_ref.matriz_estoque LIKE 'SSS' THEN
                v_validador_status := COALESCE(v_validador_status, 0) + 0;
            ELSIF r_frete.flag_gera_estoque = 'S' AND r_frete_ref.matriz_estoque LIKE '%N%' THEN
                v_validador_status := COALESCE(v_validador_status, 0) + 0;
            ELSE 
                v_validador_status := 1;
            END IF;
        END LOOP;

        -- 4. APLICAÇÃO DO GOVERNANCE (BLOQUEIO INTEGRACIONAL)
        -- Impede o prosseguimento caso as configurações sejam divergentes
        IF v_validador_status = 0 THEN
            :p_retorno_cmd := 'ERR-Divergência Contábil: NF-e e CT-e possuem comportamentos opostos para o estoque. Ambos devem movimentar ou nenhum movimenta. Revise as configurações de CFOP/Item!';
            RAISE ex_validacao;
        END IF;
        
    END LOOP;

END;
