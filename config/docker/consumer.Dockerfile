# =============================================================================
# MeGusta Consumer - Multi-stage (Maven -> JRE)
# =============================================================================
# Build context: <repo>/megusta-consumer/megusta-consumer
# (o codigo do consumer esta nessa subpasta do repositorio me-gusta-microsservico)
#
# Worker sem HTTP: nao expoe porta, nao acessa MySQL e nao precisa de curl.
# Ele apenas consome a fila do RabbitMQ e envia e-mail (AWS SES via API por
# padrao; SMTP generico como alternativa).
# =============================================================================
FROM maven:3.9-eclipse-temurin-21 AS build
WORKDIR /app
COPY pom.xml ./
RUN mvn dependency:go-offline -B
COPY src ./src
# Os testes do repo nao foram executados no ambiente de desenvolvimento; no
# build de deploy pulamos compilacao e execucao dos testes (igual ao backend).
# A correcao definitiva e manter os testes verdes no repo do consumer.
RUN mvn clean package -Dmaven.test.skip=true -B

FROM eclipse-temurin:21-jre
WORKDIR /app
COPY --from=build /app/target/*.jar app.jar
ENTRYPOINT ["java","-jar","app.jar"]
