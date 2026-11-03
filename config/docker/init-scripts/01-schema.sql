CREATE DATABASE IF NOT EXISTS megusta;
USE megusta;

CREATE TABLE IF NOT EXISTS categoria_insumo (
	id INT PRIMARY KEY AUTO_INCREMENT,
	nome VARCHAR(100)
);

CREATE TABLE IF NOT EXISTS categoria_fogazza (
	id INT PRIMARY KEY AUTO_INCREMENT,
	nome VARCHAR(100)
);

CREATE TABLE IF NOT EXISTS unidade_medida (
	id INT PRIMARY KEY AUTO_INCREMENT,
	unidade VARCHAR(50)
);

CREATE TABLE IF NOT EXISTS tipo_status (
	id INT PRIMARY KEY AUTO_INCREMENT,
	nome VARCHAR(30)
);

CREATE TABLE IF NOT EXISTS motivo(
	id INT PRIMARY KEY AUTO_INCREMENT,
    nome VARCHAR(70)
);

CREATE TABLE IF NOT EXISTS fornecedor (
	id INT PRIMARY KEY AUTO_INCREMENT,
	nome VARCHAR(150),
    cnpj VARCHAR(20),
    telefone VARCHAR(20),
    ativo BOOLEAN
);

CREATE TABLE IF NOT EXISTS usuario (
	id INT PRIMARY KEY AUTO_INCREMENT,
	nome VARCHAR(70),
    senha VARCHAR(255),
    email VARCHAR(255),
    telefone VARCHAR(70)
);

CREATE TABLE IF NOT EXISTS fogazza (
	id INT PRIMARY KEY AUTO_INCREMENT,
	nome VARCHAR(70),
    preco DECIMAL(19,4),
    fk_categoria_fogazza INT,
    FOREIGN KEY (fk_categoria_fogazza) REFERENCES categoria_fogazza(id)
);

CREATE TABLE IF NOT EXISTS insumo (
	id INT PRIMARY KEY AUTO_INCREMENT, 
    fk_categoria_insumo INT, 
    fk_unidade_medida INT, 
    fk_status INT, 
    nome VARCHAR(70), 
    codigo_insumo VARCHAR(15), 
    estoque_minimo DECIMAL(10,2), 
    qtd_atual DECIMAL(10,2), 
    ativo BOOLEAN, 
    dt_cadastro DATETIME,
    FOREIGN KEY (fk_categoria_insumo) REFERENCES categoria_insumo(id),
    FOREIGN KEY (fk_unidade_medida) REFERENCES unidade_medida(id),
    FOREIGN KEY (fk_status) REFERENCES tipo_status(id)
);

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
);

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
);

CREATE TABLE fogazza_insumo (
	fk_fogazza INT, 
    fk_insumo INT, 
    quantidade_insumo DECIMAL(10,2),
    PRIMARY KEY (fk_fogazza, fk_insumo),
    FOREIGN KEY (fk_fogazza) REFERENCES fogazza(id),
    FOREIGN KEY (fk_insumo) REFERENCES insumo(id)
);

CREATE USER 'megusta_admin'@'%' IDENTIFIED BY 'sptech';
GRANT ALL PRIVILEGES ON megusta.* TO 'megusta_admin'@'%';
FLUSH PRIVILEGES;