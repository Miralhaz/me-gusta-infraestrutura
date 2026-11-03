# =============================================================================
# MeGusta RabbitMQ - Custom Image (config embutida)
# =============================================================================
# No Docker Swarm, bind mounts com caminhos relativos não existem nos nós
# workers (a task falha em "bind source path does not exist"). Por isso a
# configuração é embutida na imagem, igual fazemos com o banco.
#
# Build context: config/docker/rabbitmq
# Build: docker build -t megusta-rabbitmq:latest config/docker/rabbitmq
# =============================================================================
FROM rabbitmq:4-management-alpine

# Configuração (vhost, usuário default, listeners, limites de recurso).
#
# NÃO copie nem carregue definitions.json: no RabbitMQ 4.4.x o import via
# `management.load_definitions` trava o boot em "Importing concurrently 1
# users..." (reproduzido com a imagem oficial). A topologia é declarada pelos
# próprios serviços: o backend cria o exchange "megusta.estoque" e o consumer
# cria a fila "megusta.email.alertas", o binding e a DLQ. O usuário admin e o
# vhost "/" vêm de default_user/default_pass/default_vhost no rabbitmq.conf.
COPY rabbitmq.conf /etc/rabbitmq/rabbitmq.conf
