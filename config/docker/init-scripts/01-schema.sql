-- =============================================================================
# MeGusta Database Schema - v06
# Auto-executado na inicialização do container MySQL
# =============================================================================

CREATE DATABASE IF NOT EXISTS megusta CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
USE megusta;

-- =============================================================================
# TABELAS DE REFERÊNCIA
-- =============================================================================

CREATE TABLE IF NOT EXISTS categoria_insumo (
    id INT PRIMARY KEY AUTO_INCREMENT,
    nome VARCHAR(100) NOT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS categoria_fogazza (
    id INT PRIMARY KEY AUTO_INCREMENT,
    nome VARCHAR(100) NOT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS unidade_medida (
    id INT PRIMARY KEY AUTO_INCREMENT,
    unidade VARCHAR(50) NOT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS tipo_status (
    id INT PRIMARY KEY AUTO_INCREMENT,
    nome VARCHAR(30) NOT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS motivo (
    id INT PRIMARY KEY AUTO_INCREMENT,
    nome VARCHAR(70) NOT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- =============================================================================
# TABELAS PRINCIPAIS
-- =============================================================================

CREATE TABLE IF NOT EXISTS fornecedor (
    id INT PRIMARY KEY AUTO_INCREMENT,
    nome VARCHAR(150) NOT NULL,
    cnpj VARCHAR(20),
    telefone VARCHAR(20),
    ativo BOOLEAN DEFAULT TRUE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS usuario (
    id INT PRIMARY KEY AUTO_INCREMENT,
    nome VARCHAR(70) NOT NULL,
    senha VARCHAR(255) NOT NULL,
    email VARCHAR(255),
    telefone VARCHAR(70)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS fogazza (
    id INT PRIMARY KEY AUTO_INCREMENT,
    nome VARCHAR(70) NOT NULL,
    preco DECIMAL(19,4) NOT NULL,
    fk_categoria_fogazza INT,
    FOREIGN KEY (fk_categoria_fogazza) REFERENCES categoria_fogazza(id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS insumo (
    id INT PRIMARY KEY AUTO_INCREMENT,
    fk_categoria_insumo INT,
    fk_unidade_medida INT,
    fk_status INT,
    nome VARCHAR(70) NOT NULL,
    codigo_insumo VARCHAR(15),
    estoque_minimo DECIMAL(10,2) DEFAULT 0,
    qtd_atual DECIMAL(10,2) DEFAULT 0,
    ativo BOOLEAN DEFAULT TRUE,
    dt_cadastro DATETIME DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (fk_categoria_insumo) REFERENCES categoria_insumo(id),
    FOREIGN KEY (fk_unidade_medida) REFERENCES unidade_medida(id),
    FOREIGN KEY (fk_status) REFERENCES tipo_status(id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS entrada_estoque (
    id INT PRIMARY KEY AUTO_INCREMENT,
    fk_insumo INT,
    fk_usuario INT,
    fk_fornecedor INT,
    fk_tipo_status INT,
    fk_unidade_medida INT,
    quantidade_relativa DECIMAL(10,2),
    dt_entrada DATETIME,
    lote VARCHAR(50),
    dt_validade DATE,
    dt_pedido DATE,
    vl_total DECIMAL(19,4),
    quantidade_absoluta DECIMAL(10,2),
    FOREIGN KEY (fk_insumo) REFERENCES insumo(id),
    FOREIGN KEY (fk_usuario) REFERENCES usuario(id),
    FOREIGN KEY (fk_fornecedor) REFERENCES fornecedor(id),
    FOREIGN KEY (fk_tipo_status) REFERENCES tipo_status(id),
    FOREIGN KEY (fk_unidade_medida) REFERENCES unidade_medida(id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS saida_estoque (
    id INT PRIMARY KEY AUTO_INCREMENT,
    fk_insumo INT,
    fk_usuario INT,
    quantidade DECIMAL(10,2),
    dt_saida DATETIME,
    fk_motivo INT,
    FOREIGN KEY (fk_insumo) REFERENCES insumo(id),
    FOREIGN KEY (fk_usuario) REFERENCES usuario(id),
    FOREIGN KEY (fk_motivo) REFERENCES motivo(id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS fogazza_insumo (
    fk_fogazza INT,
    fk_insumo INT,
    quantidade_insumo DECIMAL(10,2),
    PRIMARY KEY (fk_fogazza, fk_insumo),
    FOREIGN KEY (fk_fogazza) REFERENCES fogazza(id),
    FOREIGN KEY (fk_insumo) REFERENCES insumo(id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- =============================================================================
# USUÁRIO DA APLICAÇÃO
-- =============================================================================

CREATE USER IF NOT EXISTS 'megusta_admin'@'%' IDENTIFIED BY 'sptech';
GRANT ALL PRIVILEGES ON megusta.* TO 'megusta_admin'@'%';
FLUSH PRIVILEGES;