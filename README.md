# lince-ruby

Cliente de [Lince](https://github.com/prcalopa) para apps Rails desplegadas con Kamal. Hace dos cosas:

- **`/lince/health`**: comprueba la base de datos, la caché y Solid Queue y devuelve la versión desplegada. Responde 200 si todo va bien y 503 si no. No da datos sensibles.
- **Avisos de despliegue**: los hooks `pre-deploy` y `post-deploy` de Kamal llaman a `lince deploy`, que avisa a Lince. Si Lince no responde, el deploy sigue igual.

## Instalar

En el `Gemfile`:

```ruby
gem "lince", github: "prcalopa/lince-ruby", tag: "v0.1.1"
```

```bash
bundle install
bin/rails lince:install
bin/rails credentials:edit
```

En las credenciales:

```yaml
lince:
  token: el-token-del-proyecto   # Lince › Ajustes del proyecto › Integración
```

`lince:install` crea `.kamal/hooks/pre-deploy` y `post-deploy`, o les añade una línea si ya existen. Los hooks solo llaman a la gema, así que al actualizarla no hay que tocarlos.

## Actualizar

Dependabot abre el PR cuando sale una versión nueva. Lince también avisa si una app se queda atrás.

## Configuración

| Variable | Para qué | Por defecto |
|---|---|---|
| `LINCE_TOKEN` | Token del proyecto, si no está en las credenciales | — |
| `LINCE_ENDPOINT` | Dónde está Lince | `https://lince.perecalopa.dev` |

El token solo sirve para mandar eventos de su proyecto a Lince. No da acceso a nada más.
