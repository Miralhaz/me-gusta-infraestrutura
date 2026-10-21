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

# Configuração (vhost, usuário default, cluster formation, quorum queues)
COPY rabbitmq.conf /etc/rabbitmq/rabbitmq.conf

# Filas, exchange, bindings e policy de HA (quorum)
COPY definitions.json /etc/rabbitmq/definitions.json
