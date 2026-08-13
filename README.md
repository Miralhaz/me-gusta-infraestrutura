# Guia de Contribuição

Este documento define o fluxo de desenvolvimento, criação de branches, commits e Pull Requests deste projeto.

O objetivo é manter o código organizado, facilitar a revisão das alterações e evitar que mudanças sejam inseridas diretamente na branch principal sem revisão.

---

## 📌 Sumário

* [Fluxo de desenvolvimento](#-fluxo-de-desenvolvimento)
* [Branches](#-branches)
* [Padrão de nomes das branches](#-padrão-de-nomes-das-branches)
* [Criando uma nova branch](#-criando-uma-nova-branch)
* [Commits](#-commits)
* [Pull Requests](#-pull-requests)
* [Regras para Pull Requests](#-regras-para-pull-requests)
* [Processo de revisão](#-processo-de-revisão)
* [Aprovação e merge](#-aprovação-e-merge)
* [O que fazer quando alterações forem solicitadas](#-o-que-fazer-quando-alterações-forem-solicitadas)
* [Conflitos com a main](#-conflitos-com-a-main)
* [Checklist do desenvolvedor](#-checklist-do-desenvolvedor)
* [Resumo do fluxo](#-resumo-do-fluxo)

---

# 🔄 Fluxo de desenvolvimento

Todas as alterações no projeto devem seguir o seguinte fluxo:

```text
main
 │
 │
 ├──────────────► Criar branch
 │                     │
 │                     ▼
 │               Desenvolver
 │                     │
 │                     ▼
 │                 Commits
 │                     │
 │                     ▼
 │               Push da branch
 │                     │
 │                     ▼
 │               Pull Request
 │                     │
 │                     ▼
 │              Revisão de código
 │                     │
 │             ┌───────┴────────┐
 │             │                │
 │        Alterações          Aprovado
 │        solicitadas            │
 │             │                 │
 │             ▼                 ▼
 │          Corrigir           Merge
 │             │                 │
 │             └──────►          │
 │                               ▼
 └────────────────────────────── main
```

A branch `main` deve representar sempre uma versão estável do projeto.

Por isso, **não devem ser realizadas alterações diretamente na `main`**.

Toda alteração deve partir de uma branch própria e chegar à `main` através de uma Pull Request.

---

# 🌿 Branches

As branches são utilizadas para separar diferentes tipos de trabalho.

A branch principal do projeto é:

```text
main
```

As alterações devem ser desenvolvidas em branches específicas.

Exemplos:

```text
feat/login
fix/correcao-autenticacao
chore/atualizacao-dependencias
```

---

# 🏷️ Padrão de nomes das branches

As branches devem seguir o seguinte padrão:

```text
tipo/descricao
```

Os tipos recomendados são:

| Tipo        | Uso                            |
| ----------- | ------------------------------ |
| `feat/`     | Nova funcionalidade            |
| `fix/`      | Correção de bug                |
| `chore/`    | Tarefas de manutenção          |
| `refactor/` | Refatoração de código          |
| `docs/`     | Alterações de documentação     |
| `test/`     | Criação ou alteração de testes |

### Exemplos

#### Nova funcionalidade

```bash
feat/login
feat/cadastro-usuario
feat/pagamento-pix
```

#### Correção

```bash
fix/erro-login
fix/validacao-email
fix/calculo-frete
```

#### Manutenção

```bash
chore/atualizacao-dependencias
chore/configuracao-docker
```

#### Documentação

```bash
docs/atualiza-readme
docs/documentacao-api
```

---

# 🚀 Criando uma nova branch

Antes de iniciar uma nova tarefa, certifique-se de estar com a `main` atualizada.

```bash
git checkout main
git pull origin main
```

Depois, crie sua branch:

```bash
git checkout -b feat/nome-da-feature
```

Exemplo:

```bash
git checkout -b feat/autenticacao
```

A partir desse momento, todo o desenvolvimento relacionado à tarefa deve ser feito nessa branch.

---

# 📝 Commits

Embora os commits não sejam validados automaticamente pelo Commitlint, devemos seguir um padrão para manter o histórico do projeto organizado.

O formato recomendado é:

```text
tipo: descrição
```

Neste projeto, os principais tipos são:

```text
feat:
fix:
chore:
```

### `feat`

Utilizado para novas funcionalidades.

```bash
git commit -m "feat: adiciona autenticação de usuários"
```

```bash
git commit -m "feat: adiciona recuperação de senha"
```

### `fix`

Utilizado para correções de problemas.

```bash
git commit -m "fix: corrige validação do login"
```

```bash
git commit -m "fix: corrige cálculo do frete"
```

### `chore`

Utilizado para tarefas de manutenção que não representam uma nova funcionalidade ou correção de regra de negócio.

```bash
git commit -m "chore: atualiza dependências"
```

```bash
git commit -m "chore: ajusta configuração do projeto"
```

### Boas práticas

Prefira commits pequenos e relacionados a uma única alteração.

Bom:

```text
feat: adiciona tela de login
fix: corrige validação da senha
chore: atualiza dependências
```

Evite:

```text
alterações
ajustes
mudanças
coisas
final
final2
agora vai
```

Também evite misturar alterações não relacionadas no mesmo commit.

---

# 🔀 Pull Requests

Toda alteração destinada à `main` deve ser enviada através de uma Pull Request (PR).

Uma Pull Request representa uma solicitação para que as alterações de uma branch sejam revisadas e posteriormente incorporadas à `main`.

Exemplo:

```text
feat/autenticacao
       │
       │
       ▼
Pull Request
       │
       ▼
     main
```

O autor da PR é responsável por garantir que ela esteja pronta para revisão.

---

# 📋 Regras para Pull Requests

Toda Pull Request deve seguir algumas regras.

## 1. A PR deve ter um objetivo claro

A Pull Request deve resolver **uma tarefa ou problema específico**.

Evite criar uma única PR contendo:

```text
- Nova funcionalidade
- Correção de outro problema
- Refatoração de outro módulo
- Atualização de documentação
- Alteração de configuração
```

Quando possível, essas alterações devem ser separadas em Pull Requests diferentes.

---

## 2. A descrição da PR deve explicar a alteração

A descrição deve permitir que outra pessoa entenda:

* O que foi alterado?
* Por que foi alterado?
* Como foi implementado?
* Como foi testado?
* Existe algum ponto que merece atenção especial?

Uma boa descrição reduz o tempo necessário para entender a alteração durante a revisão.

---

## 3. A PR deve estar pronta para revisão

Antes de solicitar uma revisão:

* O código deve estar funcionando.
* Os testes existentes devem passar.
* Não devem existir alterações temporárias ou arquivos desnecessários.
* A branch deve estar atualizada com a `main`, quando necessário.
* A descrição da PR deve estar preenchida.
* Todos os pontos relevantes devem estar documentados.

---

# 🔍 Processo de revisão

A revisão de código não deve ser encarada apenas como uma etapa de aprovação.

O objetivo é verificar se a alteração:

* Resolve o problema proposto.
* Está de acordo com os padrões do projeto.
* Não introduz problemas conhecidos.
* É suficientemente simples e legível.
* Não possui código desnecessário.
* Não quebra funcionalidades existentes.
* Possui testes adequados quando aplicável.

O revisor pode:

### 💬 Comentar

Utilizado quando existe uma dúvida, sugestão ou observação que não necessariamente impede o merge.

### 🔴 Solicitar alterações

Utilizado quando existe algum problema que precisa ser corrigido antes do merge.

### 🟢 Aprovar

Utilizado quando a alteração foi revisada e está pronta para ser incorporada à `main`.

---

# 👤 Aprovação da Pull Request

As Pull Requests devem ser aprovadas por **outra pessoa que não seja o autor da alteração**.

O autor não deve aprovar a própria Pull Request.

O GitHub não permite que o autor de uma PR aprove a própria PR. ([GitHub Docs][1])

Além disso, a proteção da `main` deve exigir pelo menos **1 aprovação** antes que a PR possa ser incorporada.

A configuração recomendada é:

```text
main
 │
 ├── Pull Request obrigatória
 │
 ├── 1 aprovação obrigatória
 │
 ├── Aprovação de outra pessoa
 │
 ├── Conversas resolvidas
 │
 └── Merge permitido
```

O GitHub permite configurar a branch protegida para exigir uma quantidade específica de aprovações antes do merge. ([GitHub Docs][2])

---

# 🔒 Proteção da `main`

A branch `main` deve ser protegida contra alterações diretas.

Recomenda-se configurar:

* [x] Require a pull request before merging
* [x] Require approvals
* [x] Required approvals: `1`
* [x] Require approval of the most recent reviewable push
* [x] Dismiss stale pull request approvals when new commits are pushed
* [x] Require conversation resolution before merging
* [x] Block force pushes
* [x] Block branch deletion
* [x] Não permitir bypass das regras, quando aplicável

O GitHub possui regras específicas para branches protegidas que permitem exigir Pull Requests, aprovações, resolução de conversas e outras condições antes do merge. ([GitHub Docs][2])

### Aprovação do último push

A opção:

```text
Require approval of the most recent reviewable push
```

é especialmente importante.

Ela garante que o último conjunto de alterações enviado à PR seja revisado por alguém diferente de quem realizou o último push. ([GitHub Docs][2])

Isso evita uma situação como:

```text
Pessoa A
   │
   ├── cria PR
   │
   ▼
Pessoa B
   │
   └── aprova
   │
   ▼
Pessoa A
   │
   ├── adiciona novas alterações
   └── push
```

Nesse cenário, a nova alteração precisa ser considerada novamente na revisão.

---

# 💬 Conversas da Pull Request

Todos os comentários relevantes feitos durante a revisão devem ser tratados antes do merge.

Se um revisor apontar um problema:

```text
Reviewer
   │
   └── "Essa validação precisa ser corrigida."
              │
              ▼
          Desenvolvedor
              │
              ├── corrige
              └── envia novo commit
```

Depois disso, a conversa deve ser marcada como resolvida quando o problema tiver sido tratado.

A proteção de branch do GitHub pode exigir que todas as conversas da PR estejam resolvidas antes do merge. ([GitHub Docs][3])

---

# 🔄 Novos commits após uma aprovação

Se forem adicionadas alterações relevantes depois da aprovação, a PR deve passar novamente por revisão.

Por isso, recomenda-se habilitar:

```text
Dismiss stale pull request approvals when new commits are pushed
```

Quando novos commits alteram o diff que foi aprovado, o GitHub pode invalidar a aprovação anterior e exigir uma nova revisão. ([GitHub Docs][2])

---

# 🛠️ O que fazer quando alterações forem solicitadas

Quando um revisor solicitar alterações:

1. Leia todos os comentários.
2. Faça as correções na mesma branch da PR.
3. Crie os commits necessários.
4. Faça o push.
5. Responda aos comentários quando necessário.
6. Resolva as conversas que foram efetivamente tratadas.
7. Solicite uma nova revisão.

Exemplo:

```bash
git add .
git commit -m "fix: corrige validação do login"
git push origin feat/autenticacao
```

A Pull Request será atualizada automaticamente.

**Não é necessário abrir uma nova PR.**

---

# 🔀 Conflitos com a `main`

Durante o desenvolvimento, a `main` pode receber novas alterações.

Caso sua branch fique desatualizada, atualize-a antes do merge.

Uma possibilidade é:

```bash
git checkout main
git pull origin main
git checkout feat/minha-feature
git merge main
```

Resolva os conflitos, caso existam, e depois envie as alterações:

```bash
git push origin feat/minha-feature
```

Outra possibilidade é utilizar `rebase`, caso essa seja a estratégia adotada pelo projeto.

O importante é que a PR esteja baseada em uma versão atualizada da `main` quando isso for necessário.

---

# 🧹 Antes de abrir uma Pull Request

Antes de criar a PR, verifique:

```bash
git status
```

Confirme que não existem arquivos desnecessários.

Depois:

```bash
git pull origin main
```

Atualize sua branch conforme a estratégia utilizada pelo projeto.

Execute os testes:

```bash
# comando específico do projeto
```

E faça o push:

```bash
git push origin nome-da-branch
```

---

# 📋 Checklist do desenvolvedor

Antes de solicitar a revisão da Pull Request:

* [ ] A branch possui um nome adequado.
* [ ] A branch foi criada a partir de uma `main` atualizada.
* [ ] A alteração possui um objetivo claro.
* [ ] Não existem arquivos desnecessários.
* [ ] Não existem credenciais ou informações sensíveis no código.
* [ ] O código foi revisado pelo próprio autor.
* [ ] Os testes foram executados.
* [ ] A aplicação foi testada quando necessário.
* [ ] Os commits possuem mensagens claras.
* [ ] Os commits seguem o padrão `feat:`, `fix:` ou `chore:` quando aplicável.
* [ ] A descrição da Pull Request está preenchida.
* [ ] A PR possui contexto suficiente para o revisor.
* [ ] Todos os comentários relevantes foram tratados.

---

# 👀 Checklist do revisor

Durante a revisão, considere:

* [ ] A alteração resolve o problema proposto?
* [ ] O código está correto?
* [ ] O código é legível?
* [ ] Existe algum comportamento inesperado?
* [ ] Existem possíveis problemas de segurança?
* [ ] Existem impactos em outras funcionalidades?
* [ ] Os testes são suficientes?
* [ ] Existem testes que deveriam ser adicionados?
* [ ] A alteração introduz código desnecessário?
* [ ] A documentação precisa ser atualizada?
* [ ] Todos os comentários relevantes foram tratados?

Se tudo estiver correto:

```text
Approve
```

Caso sejam necessárias alterações:

```text
Request changes
```

---

# 🚦 Quando uma PR pode ser aprovada?

Uma PR está pronta para aprovação quando:

1. O objetivo da alteração está claro.
2. O código foi revisado.
3. Os testes necessários passaram.
4. Os problemas encontrados foram corrigidos.
5. As conversas relevantes foram resolvidas.
6. Não existem alterações inesperadas.
7. O revisor está confortável com a alteração.

A aprovação deve representar que o revisor analisou as mudanças, e não simplesmente que "o código parece estar funcionando".

---

# 🚀 Merge

O merge somente deve acontecer quando todos os requisitos da Pull Request forem atendidos.

Exemplo:

```text
Pull Request
    │
    ├── PR aberta                  ✅
    ├── CI/Testes                  ✅
    ├── Revisão                    ✅
    ├── Aprovação de outra pessoa ✅
    ├── Conversas resolvidas      ✅
    └── Branch atualizada          ✅
                 │
                 ▼
               MERGE
                 │
                 ▼
                main
```

Sempre que possível, utilize o método de merge definido pelo projeto e evite realizar merges manuais que contornem as proteções configuradas.

---

# ❌ O que não fazer

## Não fazer push diretamente na `main`

```bash
git checkout main
git push origin main
```

A `main` deve ser protegida e alterações devem entrar através de Pull Requests.

---

## Não aprovar a própria PR

```text
Autor → abre PR
Autor → aprova PR ❌
```

A revisão deve ser realizada por outra pessoa.

---

## Não misturar várias tarefas

Evite:

```text
feat/login
    ├── login
    ├── novo dashboard
    ├── correção de pagamento
    └── atualização do Docker
```

Prefira:

```text
feat/login
feat/dashboard
fix/pagamento
chore/docker
```

---

## Não utilizar mensagens de commit genéricas

Evite:

```text
git commit -m "alterações"
git commit -m "ajustes"
git commit -m "final"
```

Prefira:

```text
git commit -m "feat: adiciona autenticação"
git commit -m "fix: corrige validação do usuário"
git commit -m "chore: atualiza dependências"
```

---

# 🧭 Resumo do fluxo

O fluxo padrão do projeto é:

```text
1. Atualizar a main
        ↓
2. Criar uma branch
        ↓
3. Desenvolver
        ↓
4. Criar commits organizados
        ↓
5. Executar testes
        ↓
6. Fazer push da branch
        ↓
7. Abrir Pull Request
        ↓
8. Solicitar revisão
        ↓
9. Outra pessoa revisa
        ↓
   ┌───────────────┐
   │               │
   ▼               ▼
Correções       Aprovado
   │               │
   └───►           │
                   ▼
              Merge na main
```

---

# 🎯 Regras principais

Se precisar lembrar apenas das regras mais importantes, são estas:

> **1. Nunca desenvolver diretamente na `main`.**

> **2. Toda alteração deve passar por uma Pull Request.**

> **3. Toda Pull Request deve ser revisada por outra pessoa.**

> **4. O autor não deve aprovar a própria Pull Request.**

> **5. A `main` exige pelo menos 1 aprovação antes do merge.**

> **6. Novas alterações após uma aprovação devem ser revisadas novamente quando necessário.**

> **7. Comentários relevantes devem ser tratados antes do merge.**

> **8. Commits devem ser claros e, preferencialmente, seguir `feat:`, `fix:` ou `chore:`.**

> **9. Pull Requests devem ser pequenas, objetivas e relacionadas a uma tarefa.**

> **10. A `main` deve permanecer estável.**

---

## 📚 Referências

As regras de proteção de branch e revisão descritas neste documento utilizam recursos nativos do GitHub, como **Protected Branches**, **Rulesets**, **Required Reviews** e **Required Status Checks**. ([GitHub Docs][2])

Documentação oficial:

* [GitHub — About protected branches](https://docs.github.com/en/repositories/configuring-branches-and-merges-in-your-repository/managing-protected-branches/about-protected-branches?utm_source=chatgpt.com)
* [GitHub — Managing a branch protection rule](https://docs.github.com/en/repositories/configuring-branches-and-merges-in-your-repository/managing-protected-branches/managing-a-branch-protection-rule?utm_source=chatgpt.com)
* [GitHub — Managing and standardizing pull requests](https://docs.github.com/en/pull-requests/reference/managing-and-standardizing-pull-requests?utm_source=chatgpt.com)
* [GitHub — Reviewing pull requests](https://docs.github.com/en/pull-requests/how-tos/review-pull-requests?utm_source=chatgpt.com)

[1]: https://docs.github.com/en/pull-requests/collaborating-with-pull-requests/reviewing-changes-in-pull-requests/approving-a-pull-request-with-required-reviews?apiVersion=2022-11-28&utm_source=chatgpt.com "Approving a pull request with required reviews - GitHub Docs"
[2]: https://docs.github.com/en/repositories/configuring-branches-and-merges-in-your-repository/managing-protected-branches/about-protected-branches?ref=the-mergify-blog&utm_source=chatgpt.com "About protected branches - GitHub Docs"
[3]: https://docs.github.com/en/repositories/configuring-branches-and-merges-in-your-repository/managing-protected-branches/about-protected-branches?utm_source=chatgpt.com "About protected branches - GitHub Docs"
