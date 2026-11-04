# lince-ruby

Cliente de [Lince](https://github.com/prcalopa) para apps Rails desplegadas con Kamal. Hace cuatro cosas:

- **`/lince/health`**: comprueba la base de datos, la caché y Solid Queue, y devuelve la versión desplegada y cifras de recursos (memoria, disco, base de datos, cola y jobs fallidos). Responde 200 si todo va bien y 503 si no. **Es privado**: sin el token del proyecto en `Authorization: Bearer …` responde 404, como si no existiera.
- **Avisos de despliegue**: los hooks `pre-deploy` y `post-deploy` de Kamal llaman a `lince deploy`, que avisa a Lince. Si Lince no responde, el deploy sigue igual.
- **Errores de producción**: se suscribe al error reporter de Rails, agrupa por huella y manda lotes cada 10 segundos desde un hilo aparte. Del error solo salen la clase, el mensaje (sin emails, números largos, tokens ni query strings), el backtrace y el controlador o job. Nunca parámetros, cuerpos ni cabeceras. Ignora los errores de ruido habituales (`RecordNotFound`, `RoutingError`, CSRF…).
- **Latidos**: cada trabajo recurrente de `config/recurring.yml` (Solid Queue) avisa al terminar, con su horario, la hora a la que tocaba y lo que ha tardado. Lince avisa si uno no corre a su hora o si tarda casi tanto como su intervalo. Para crons de fuera: `Lince.heartbeat("backup", schedule: "every day at 3am")`.

Errores y latidos solo funcionan en producción.

## Instalar

En el `Gemfile`:

```ruby
gem "lince", github: "prcalopa/lince-ruby", tag: "v0.3.2"
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
| `LINCE_RUNNER_ERRORS` | `true` reporta los errores sin capturar en `rails runner` | sin reportar |

En un initializer se puede ajustar:

```ruby
Lince.configure do |c|
  c.ignored_errors += [ "MiApp::ErrorEsperado" ]
  c.errors = false      # sin captura de errores
  c.runner_errors = true # también los errores sin capturar en `rails runner`
  c.heartbeats = false  # sin latidos
end
```

Los errores que llegan sin capturar hasta `rails runner` no se reportan por defecto: suelen ser comandos escritos a mano y quien los lanza ya ve el fallo. Actívalos en un proyecto con `c.runner_errors = true` si usa `rails runner` para procesos que nadie mira, o solo durante un mantenimiento, sin desplegar:

```bash
bin/kamal app exec --reuse -e LINCE_RUNNER_ERRORS:true "bin/rails runner 'MiTarea.call'"
```

Los errores que un job o el propio código reportan antes de llegar a `rails runner` se siguen mandando.

El token solo sirve para mandar eventos de su proyecto a Lince. No da acceso a nada más.
