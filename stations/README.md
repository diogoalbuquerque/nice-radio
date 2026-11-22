# Lista de estações

**A partir da próxima versão do app**, ele baixa a lista de rádios e os logos
daqui (publicados na Cloudflare), não mais direto da Radio Browser. Até lá, as
edições são publicadas mas o app instalado ainda não as lê. A pipeline `.github/workflows/stations.yml`
atualiza tudo **toda segunda-feira** e também **na hora** em que você muda
`overrides.json` ou `custom_logos/`.

| Arquivo | Quem mexe | Para quê |
|---|---|---|
| `overrides.json` | **você** | esconder, renomear, trocar stream, adicionar rádio |
| `custom_logos/<id>.png` | **você** | logo escolhido por você (ganha do automático) |
| `lists/<UF>.json` | pipeline | a lista publicada de cada estado |
| `logos/<id>.png` | pipeline | logos achados automaticamente |
| `logos_missing.json` | pipeline | rádios sem logo (o app mostra as iniciais) |

## Como achar o id de uma rádio

Abra `lists/<UF>.json` (ex.: `lists/SP.json`), procure pelo nome e copie o
valor de `"stationuuid"`.

## `overrides.json`

```json
{
 "hide": ["963fa65f-0601-11e8-ae97-52543be04c81"],
 "rename": {"531fced7-b22b-11e8-afe1-52543be04c81": "Antena 1 São Paulo"},
 "stream": {"<id>": "https://novo-endereco-do-stream"},
 "add": [
  {
   "id": "manual-sp-minha-radio",
   "state": "São Paulo",
   "name": "Minha Rádio 99,9 FM",
   "stream": "https://endereco-do-stream",
   "homepage": "https://site-da-radio (opcional, para achar o logo)"
  }
 ]
}
```

- **hide**: some com a rádio. A pipeline já junta sozinha as cópias de uma
  mesma rádio (mesma frequência FM e uma palavra do nome em comum, ex.:
  "Melodia FM 97.5" e "Rádio Melodia 97,5 FM"), mantendo a mais votada; use
  `hide` para os casos que ela não pega.
- **rename**: troca o nome. Mantenha a frequência no nome ("98,1 FM") — o app
  ordena por ela.
- **stream**: troca o endereço do áudio.
- **add**: rádio que não existe na Radio Browser. O `id` precisa começar com
  `manual-` e **nunca deve mudar** depois de publicado (as favoritas das
  pessoas usam o id). `state` é o nome do estado com acento, como na lista acima.

Se o arquivo tiver erro, a pipeline falha e **nada é publicado** — o app segue
com a lista anterior. O erro aparece em *Actions → Stations* no GitHub.

## Logo próprio

Coloque um PNG quadrado (de preferência 160×160 ou maior) em
`custom_logos/<id>.png` e faça o push.

## Rodar na mão

No GitHub: *Actions → Stations → Run workflow*. No computador:
`python3 tool/build_stations.py --site build/stations-site` (precisa de
`pip install pillow`).
