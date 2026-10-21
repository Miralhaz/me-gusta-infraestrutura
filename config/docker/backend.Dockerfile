# =============================================================================
# MeGusta Backend - Multi-stage (Maven -> JRE)
# =============================================================================
# Build context: <repo>/megusta  (o codigo do backend esta nessa subpasta)
# Requer Java 21 (definido no pom.xml). A imagem inclui curl para o
# healthcheck do Swarm (GET /v3/api-docs, que e permitAll no backend).
# =============================================================================
FROM maven:3.9-eclipse-temurin-21 AS build
WORKDIR /app
COPY pom.xml ./
RUN mvn dependency:go-offline -B
COPY src ./src
# -DskipTests NAO executa os testes, mas ainda COMPILA o src/test. O
# RelatorioServiceTest.java do repo esta desatualizado (usa uma API antiga:
# construtor sem args, listar(), buscarPorId(int), RelatorioResumoResponseDto)
# e quebra o testCompile. Para a imagem de deploy, pulamos a compilacao dos
# testes tambem. (Correcao definitiva: atualizar/remover esse teste no repo.)
RUN mvn clean package -Dmaven.test.skip=true -B

FROM eclipse-temurin:21-jre
WORKDIR /app
RUN apt-get update \
    && apt-get install -y --no-install-recommends curl \
    && rm -rf /var/lib/apt/lists/*
COPY --from=build /app/target/*.jar app.jar
EXPOSE 8080
ENTRYPOINT ["java","-jar","app.jar"]
