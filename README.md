# Escalimetro

- [Escopo](./PRD.md)
- [Contribuição](./CONTRIBUTING.md)

## Requisitos

- *Elixir 1.18.1* e *Erlang/OTP 26*
- *Node 24.1.0* e NPM *10.9.0*
- *Docker* com *Docker Compose*

## Configuração

- Inicie o PostgreSQL local

```shell
mix db.up
```

> `mix db.down` para encerrar

- Baixe as dependências, build, migrations e seed base

```shell
mix setup
```

> O seed base cria o sysadmin `admin@escalimetro.dev` com senha `devpassword123`.

- Opcionalmente, crie o cenário completo de desenvolvimento

```shell
mix dev.setup
```

> O cenário dev cria usuários, participantes, evento, pautas e votos de exemplo. Os usuários `admin@escalimetro.dev`, `rei@escalimetro.dev`, `neni@escalimetro.dev` e `vitor@escalimetro.dev` usam a senha `devpassword123`, pode sempre resetar de volta a ele com com `mix fresh`

## Execução

- Inicie o servidor

```shell
mix server
```
