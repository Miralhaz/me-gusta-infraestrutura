-- =============================================================================
# MeGusta Seed Data
# Dados iniciais para desenvolvimento/teste
# =============================================================================

USE megusta;

-- Desabilitar checagem de FK temporariamente
SET FOREIGN_KEY_CHECKS = 0;
SET AUTOCOMMIT = 0;
START TRANSACTION;

-- =============================================================================
# 1. UNIDADE DE MEDIDA
-- =============================================================================
INSERT IGNORE INTO unidade_medida (unidade) VALUES
('Saco'), ('Fardo'), ('Unidade'), ('Caixa');

-- =============================================================================
# 2. TIPO STATUS
-- =============================================================================
INSERT IGNORE INTO tipo_status (nome) VALUES
('OK'), ('ATENÇÃO'), ('CRÍTICO');

-- =============================================================================
# 3. MOTIVO
-- =============================================================================
INSERT IGNORE INTO motivo (nome) VALUES
('Vencimento'), ('Quebra de estoque'), ('Avaria / Perda'),
('Produção fogazza'), ('Ajuste de inventário'), ('Devolução'), ('Uso interno');

-- =============================================================================
# 4. CATEGORIA INSUMO
-- =============================================================================
INSERT IGNORE INTO categoria_insumo (nome) VALUES
('Farinha e derivados'), ('Laticínios'), ('Carnes e embutidos'),
('Vegetais e hortifruti'), ('Temperos e condimentos'), ('Embalagens'),
('Bebidas'), ('Limpeza e higiene');

-- =============================================================================
# 5. CATEGORIA FOGAZZA
-- =============================================================================
INSERT IGNORE INTO categoria_fogazza (nome) VALUES
('Fogazza Tradicional'), ('Fogazza Doce'), ('Fogazza Salgada Premium'),
('Fogazza Vegana'), ('Fogazza Especial');

-- =============================================================================
# 6. FORNECEDORES
-- =============================================================================
INSERT IGNORE INTO fornecedor (nome, cnpj, telefone, ativo) VALUES
('Tio João Alimentos LTDA', '33099456000157', '1134567800', TRUE),
('Camil Alimentos S/A', '64904286000115', '1133334400', TRUE),
('Italac - Indústria de Laticínios Ltda', '02581005000144', '1933321100', TRUE),
('Nestlé Brasil LTDA', '61065199000166', '1131485600', TRUE),
('Sadia S/A', '20730099000195', '1138222000', TRUE),
('Seara Alimentos S/A', '03878217000110', '1137777700', TRUE),
('Friboi - JBS S/A', '02916265000166', '1131441500', TRUE),
('Bunge Alimentos S/A', '84046068000119', '1133221100', TRUE),
('Vigor Alimentos S/A', '50388701000190', '1122334400', TRUE),
('Ypióca / Casa Dias (Bebidas)', '12345678000195', '8533336600', TRUE),
('Bombril S/A', '50543903000117', '1122211999', TRUE),
('Araújo Distribuidora', '11222333000144', '3140028922', TRUE),
('Atacadão S/A', '75315333000109', '1121444000', TRUE);

-- =============================================================================
# 7. FOGAZZA (Produtos do cardápio)
-- =============================================================================
INSERT IGNORE INTO fogazza (nome, preco, fk_categoria_fogazza) VALUES
('Fogazza Mussarela', 12.50, 1),
('Fogazza Calabresa', 13.00, 1),
('Fogazza Frango c/ Catupiry', 15.50, 1),
('Fogazza Portuguesa', 16.00, 1),
('Fogazza Margherita', 14.50, 1),
('Fogazza Quatro Queijos', 17.00, 3),
('Fogazza Brigadeiro', 12.00, 2),
('Fogazza Doce de Leite', 12.00, 2),
('Fogazza Banana c/ Canela', 11.50, 2),
('Fogazza Romeu e Julieta', 13.50, 2),
('Fogazza Cogumelos (Vegana)', 16.50, 4),
('Fogazza Palmito (Vegana)', 15.00, 4),
('Fogazza Camarão', 22.00, 5),
('Fogazza Filé Mignon c/ Cheddar', 24.50, 5),
('Fogazza Pepperoni', 18.50, 3);

-- =============================================================================
# 8. INSUMO (qtd_atual = 0 por regra de negócio)
-- =============================================================================
INSERT IGNORE INTO insumo (fk_categoria_insumo, fk_unidade_medida, fk_status, nome, codigo_insumo, estoque_minimo, qtd_atual, ativo, dt_cadastro) VALUES
-- Farinha e derivados
(1, 1, 1, 'Farinha de Trigo Tipo 1', 'FAR-001', 10.00, 0, TRUE, NOW()),
(1, 2, 1, 'Açúcar Refinado', 'ACU-001', 5.00, 0, TRUE, NOW()),
(1, 2, 2, 'Sal Refinado', 'SAL-001', 3.00, 0, TRUE, NOW()),
(1, 2, 1, 'Fermento Biológico Fresco', 'FER-001', 2.00, 0, TRUE, NOW()),
(1, 1, 1, 'Farinha de Milho', 'FAR-002', 4.00, 0, TRUE, NOW()),
-- Laticínios
(2, 3, 1, 'Queijo Mussarela', 'QUE-001', 8.00, 0, TRUE, NOW()),
(2, 3, 2, 'Queijo Parmesão Ralado', 'QUE-002', 2.00, 0, TRUE, NOW()),
(2, 3, 1, 'Queijo Catupiry', 'QUE-003', 4.00, 0, TRUE, NOW()),
(2, 3, 2, 'Queijo Provolone', 'QUE-004', 3.00, 0, TRUE, NOW()),
(2, 4, 1, 'Leite Integral', 'LEI-001', 15.00, 0, TRUE, NOW()),
(2, 3, 1, 'Manteiga sem Sal', 'MAN-001', 5.00, 0, TRUE, NOW()),
(2, 2, 2, 'Creme de Leite', 'CRE-001', 6.00, 0, TRUE, NOW()),
-- Carnes e embutidos
(3, 4, 2, 'Linguiça Calabresa', 'LIN-001', 5.00, 0, TRUE, NOW()),
(3, 4, 1, 'Frango Desfiado', 'FRA-001', 6.00, 0, TRUE, NOW()),
(3, 4, 2, 'Peperoni Fatiado', 'PEP-001', 3.00, 0, TRUE, NOW()),
(3, 4, 3, 'Filé Mignon', 'FIL-001', 4.00, 0, TRUE, NOW()),
(3, 4, 2, 'Camarão Limpo', 'CAM-001', 3.00, 0, TRUE, NOW()),
(3, 4, 1, 'Presunto', 'PRE-001', 4.00, 0, TRUE, NOW()),
-- Vegetais
(4, 3, 2, 'Tomate', 'TOM-001', 10.00, 0, TRUE, NOW()),
(4, 3, 1, 'Cebola', 'CEB-001', 8.00, 0, TRUE, NOW()),
(4, 3, 3, 'Manjericão Fresco', 'MAN-002', 1.50, 0, TRUE, NOW()),
(4, 3, 1, 'Alho', 'ALH-001', 3.00, 0, TRUE, NOW()),
(4, 4, 2, 'Palmito', 'PAL-001', 4.00, 0, TRUE, NOW()),
(4, 4, 1, 'Cogumelo Champignon', 'COG-001', 3.00, 0, TRUE, NOW()),
(4, 3, 3, 'Ovo de Galinha', 'OVO-001', 12.00, 0, TRUE, NOW()),
-- Temperos
(5, 2, 1, 'Orégano', 'ORE-001', 0.50, 0, TRUE, NOW()),
(5, 3, 2, 'Pimenta Calabresa', 'PIM-001', 0.30, 0, TRUE, NOW()),
(5, 2, 1, 'Canela em Pó', 'CAN-001', 0.40, 0, TRUE, NOW()),
(5, 2, 1, 'Azeite de Oliva Extra Virgem', 'AZE-001', 3.00, 0, TRUE, NOW()),
(5, 2, 1, 'Vinagre', 'VIN-001', 2.00, 0, TRUE, NOW()),
-- Embalagens
(6, 4, 1, 'Caixa de Papelão P', 'EMB-001', 20.00, 0, TRUE, NOW()),
(6, 4, 1, 'Caixa de Papelão M', 'EMB-002', 20.00, 0, TRUE, NOW()),
(6, 4, 1, 'Caixa de Papelão G', 'EMB-003', 15.00, 0, TRUE, NOW()),
(6, 2, 2, 'Saco Plástico PP', 'EMB-004', 30.00, 0, TRUE, NOW()),
-- Bebidas
(7, 4, 1, 'Refrigerante Cola 2L', 'BEB-001', 6.00, 0, TRUE, NOW()),
(7, 4, 1, 'Água Mineral 500ml', 'BEB-002', 24.00, 0, TRUE, NOW()),
(7, 3, 2, 'Suco de Laranja Natural', 'BEB-003', 10.00, 0, TRUE, NOW()),
-- Limpeza
(8, 3, 1, 'Detergente Líquido', 'LIM-001', 5.00, 0, TRUE, NOW()),
(8, 2, 1, 'Sabão em Pó', 'LIM-002', 4.00, 0, TRUE, NOW()),
(8, 3, 1, 'Álcool 70%', 'LIM-003', 3.00, 0, TRUE, NOW()),
(8, 3, 2, 'Desinfetante', 'LIM-004', 3.00, 0, TRUE, NOW());

-- =============================================================================
# 9. FOGAZZA_INSUMO (Receitas)
-- =============================================================================
INSERT IGNORE INTO fogazza_insumo (fk_fogazza, fk_insumo, quantidade_insumo) VALUES
-- Fogazza Mussarela (1)
(1, 1, 0.250), (1, 6, 0.200), (1, 28, 0.005), (1, 31, 0.010), (1, 33, 1.000),
-- Fogazza Calabresa (2)
(2, 1, 0.250), (2, 13, 0.200), (2, 31, 0.010), (2, 33, 1.000),
-- Fogazza Frango c/ Catupiry (3)
(3, 1, 0.250), (3, 8, 0.150), (3, 14, 0.250), (3, 33, 1.000),
-- Fogazza Portuguesa (4)
(4, 1, 0.250), (4, 6, 0.150), (4, 13, 0.100), (4, 17, 0.100), (4, 18, 0.050), (4, 20, 0.050), (4, 26, 0.500), (4, 33, 1.000),
-- Fogazza Margherita (5)
(5, 1, 0.250), (5, 6, 0.200), (5, 18, 0.080), (5, 22, 0.020), (5, 31, 0.015), (5, 33, 1.000),
-- Fogazza Quatro Queijos (6)
(6, 1, 0.250), (6, 6, 0.100), (6, 7, 0.080), (6, 9, 0.080), (6, 8, 0.080), (6, 33, 1.000),
-- Fogazza Brigadeiro (7)
(7, 1, 0.200), (7, 2, 0.080), (7, 31, 0.040), (7, 12, 0.030), (7, 33, 1.000),
-- Fogazza Doce de Leite (8)
(8, 1, 0.200), (8, 2, 0.050), (8, 12, 0.080), (8, 33, 1.000),
-- Fogazza Banana c/ Canela (9)
(9, 1, 0.200), (9, 2, 0.050), (9, 28, 0.010), (9, 33, 1.000),
-- Fogazza Romeu e Julieta (10)
(10, 1, 0.250), (10, 6, 0.200), (10, 31, 0.050), (10, 33, 1.000),
-- Fogazza Cogumelos (Vegana) (11)
(11, 1, 0.250), (11, 24, 0.150), (11, 23, 0.050), (11, 31, 0.020), (11, 33, 1.000),
-- Fogazza Palmito (Vegana) (12)
(12, 1, 0.250), (12, 23, 0.200), (12, 31, 0.020), (12, 33, 1.000),
-- Fogazza Camarão (13)
(13, 1, 0.250), (13, 16, 0.300), (13, 31, 0.020), (13, 33, 1.000),
-- Fogazza Filé Mignon (14)
(14, 1, 0.250), (14, 17, 0.250), (14, 8, 0.120), (14, 31, 0.020), (14, 33, 1.000),
-- Fogazza Pepperoni (15)
(15, 1, 0.250), (15, 15, 0.150), (15, 6, 0.150), (15, 33, 1.000);

COMMIT;
SET FOREIGN_KEY_CHECKS = 1;
SET AUTOCOMMIT = 1;