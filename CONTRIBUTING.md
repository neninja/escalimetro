# Contribuindo

## DX

Experiência de desenvolvimento (DX)

### Configuração e Execução

Igual ao disposto no [README](./README.md)

### Banco

- `mix fresh` recria banco com seed

### Debug

- Utilize `dbg`
- Utilize a extensão `live_debugger`
- Utilize a rota `/dev/dashboard`

### Integração

Sempre que possível, rode os testes e formatação de código

```shell
mix precommit
```

## Testes end to end

O projeto já está configurado para rodar servidor para testes automaticamente, portanto `mix test` e `mix precommit` rodam todos testes incluindo os E2E. Eles ficam na pasta `test/feature`.

Debug de erro não é o forte dessa abordagem, mas se necessário utilize `@tag trace: :open` no teste problemático para abrir o chrome e entender o problema.

> - Teste é bom, code coverage é vaidade.
> - Teste bom de verdade é o E2E, use Playwright e escreva o teste como se fosse um usuário de verdade abrindo o chrome e realizando os fluxos principais. Começa pelo mais crítico.
> - Achou um bug em produção? Escreve um teste unitário. Isso MATA aquele bug reincidente (que deixa o cliente puto da vida)
> 
> https://x.com/ocodista/status/2046562253097312362
