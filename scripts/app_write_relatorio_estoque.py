#!/usr/bin/env python3
"""
Exemplo de como a aplicação (front/back) deve escrever relatórios operacionais diários
no bucket 'relatorios' durante o horário de funcionamento (07:00-20:00).

Este script NÃO roda no Glue - roda na aplicação (EC2/ECS/Lambda) ao longo do dia.
"""

import json
import boto3
from datetime import datetime, date
from decimal import Decimal
import uuid

# Configuração
RELATORIOS_BUCKET = "megusta-relatorios-us-east-1"
S3_PREFIX = "relatorios_diarios/estoque/"

s3 = boto3.client('s3', region_name='us-east-1')

class DecimalEncoder(json.JSONEncoder):
    def default(self, obj):
        if isinstance(obj, Decimal):
            return float(obj)
        if isinstance(obj, (date, datetime)):
            return obj.isoformat()
        return super().default(obj)

def gerar_relatorio_estoque_diario(data_relatorio: date, movimentos: list, estoque_atual: dict, alertas: list):
    """
    Gera o relatório consolidado do dia e salva no S3.
    
    Estrutura esperada pelo Crawler do Glue:
    s3://megusta-relatorios-us-east-1/relatorios_diarios/estoque/
        ano=2026/
            mes=01/
                dia=15/
                    relatorio_estoque_2026-01-15_14-30-00.json
                    relatorio_estoque_2026-01-15_18-45-00.json  (última versão do dia)
    """
    
    timestamp = datetime.now().strftime("%H-%M-%S")
    filename = f"relatorio_estoque_{data_relatorio.isoformat()}_{timestamp}.json"
    
    # Partição no estilo Hive (para o Crawler criar partições ano/mes/dia)
    key = f"{S3_PREFIX}ano={data_relatorio.year}/mes={data_relatorio.month:02d}/dia={data_relatorio.day:02d}/{filename}"
    
    relatorio = {
        "metadata": {
            "relatorio_id": str(uuid.uuid4()),
            "data_geracao": datetime.now().isoformat(),
            "data_referencia": data_relatorio.isoformat(),
            "versao": timestamp,
            "origem": "aplicacao_megusta",
            "tipo": "relatorio_operacional_estoque_diario"
        },
        "resumo_dia": {
            "total_movimentacoes": len(movimentos),
            "total_entradas": sum(1 for m in movimentos if m['tipo'] == 'ENTRADA'),
            "total_saidas": sum(1 for m in movimentos if m['tipo'] == 'SAIDA'),
            "valor_total_entradas": sum(Decimal(str(m['valor_total'])) for m in movimentos if m['tipo'] == 'ENTRADA'),
            "valor_total_saidas": sum(Decimal(str(m['valor_total'])) for m in movimentos if m['tipo'] == 'SAIDA'),
        },
        "estoque_final": estoque_atual,
        "movimentacoes": movimentos,
        "alertas": alertas,
        "kpis_operacionais": {
            "produtos_com_estoque_baixo": len([p for p in estoque_atual.values() if p['quantidade'] <= p['estoque_minimo']]),
            "produtos_sem_estoque": len([p for p in estoque_atual.values() if p['quantidade'] == 0]),
            "giro_estoque_dia": len(movimentos) / max(len(estoque_atual), 1) if estoque_atual else 0
        }
    }
    
    s3.put_object(
        Bucket=RELATORIOS_BUCKET,
        Key=key,
        Body=json.dumps(relatorio, cls=DecimalEncoder, ensure_ascii=False, indent=2).encode('utf-8'),
        ContentType='application/json',
        ServerSideEncryption='AES256',
        Metadata={
            'data-referencia': data_relatorio.isoformat(),
            'tipo-relatorio': 'estoque-diario',
            'versao': timestamp
        }
    )
    
    print(f"Relatório salvo: s3://{RELATORIOS_BUCKET}/{key}")
    return key


def exemplo_uso():
    """Exemplo de como chamar durante o dia."""
    
    hoje = date.today()
    
    # Simulação de movimentos ao longo do dia (a app acumula isso em memória/banco)
    movimentos_do_dia = [
        {
            "movimento_id": str(uuid.uuid4()),
            "timestamp": "2026-01-15T07:15:00",
            "tipo": "ENTRADA",
            "produto_id": "PROD-001",
            "produto_nome": "Farinha de Trigo Tipo 1",
            "quantidade": 50,
            "unidade": "kg",
            "valor_unitario": 4.50,
            "valor_total": 225.00,
            "fornecedor": "Distribuidora Central",
            "nota_fiscal": "NF-12345"
        },
        {
            "movimento_id": str(uuid.uuid4()),
            "timestamp": "2026-01-15T08:30:00",
            "tipo": "SAIDA",
            "produto_id": "PROD-001",
            "produto_nome": "Farinha de Trigo Tipo 1",
            "quantidade": 5,
            "unidade": "kg",
            "valor_unitario": 4.50,
            "valor_total": 22.50,
            "motivo": "Produção - Fogaças Tradicionais",
            "pedido_id": "PED-789"
        },
        {
            "movimento_id": str(uuid.uuid4()),
            "timestamp": "2026-01-15T12:00:00",
            "tipo": "SAIDA",
            "produto_id": "PROD-002",
            "produto_nome": "Fermento Biológico Seco",
            "quantidade": 2,
            "unidade": "kg",
            "valor_unitario": 45.00,
            "valor_total": 90.00,
            "motivo": "Produção - Pães Especiais",
            "pedido_id": "PED-790"
        }
    ]
    
    # Estoque atual no fim do dia (ou a cada geração de relatório)
    estoque_atual = {
        "PROD-001": {
            "produto_id": "PROD-001",
            "produto_nome": "Farinha de Trigo Tipo 1",
            "quantidade": 45,
            "unidade": "kg",
            "estoque_minimo": 10,
            "estoque_maximo": 100,
            "valor_unitario": 4.50,
            "categoria": "Insumo Base"
        },
        "PROD-002": {
            "produto_id": "PROD-002",
            "produto_nome": "Fermento Biológico Seco",
            "quantidade": 3,
            "unidade": "kg",
            "estoque_minimo": 5,
            "estoque_maximo": 20,
            "valor_unitario": 45.00,
            "categoria": "Insumo Base"
        },
        "PROD-003": {
            "produto_id": "PROD-003",
            "produto_nome": "Açúcar Refinado",
            "quantidade": 0,
            "unidade": "kg",
            "estoque_minimo": 15,
            "estoque_maximo": 50,
            "valor_unitario": 3.20,
            "categoria": "Insumo Base"
        }
    }
    
    # Alertas gerados
    alertas = [
        {
            "alerta_id": str(uuid.uuid4()),
            "tipo": "ESTOQUE_ZERADO",
            "severidade": "CRITICO",
            "produto_id": "PROD-003",
            "produto_nome": "Açúcar Refinado",
            "mensagem": "Estoque zerado - necessidade de compra urgente",
            "timestamp": "2026-01-15T15:00:00"
        },
        {
            "alerta_id": str(uuid.uuid4()),
            "tipo": "ESTOQUE_BAIXO",
            "severidade": "ATENCAO",
            "produto_id": "PROD-002",
            "produto_nome": "Fermento Biológico Seco",
            "mensagem": "Estoque abaixo do mínimo (3kg < 5kg)",
            "timestamp": "2026-01-15T12:05:00"
        }
    ]
    
    # Gerar relatório (pode ser chamado múltiplas vezes ao dia - ex: a cada hora)
    gerar_relatorio_estoque_diario(hoje, movimentos_do_dia, estoque_atual, alertas)


if __name__ == "__main__":
    exemplo_uso()