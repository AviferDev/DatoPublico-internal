# ADR 0004: Ingesta programada interna por corrutina (sin cron externo)

## Estado

Aceptado (2026-10-10). Decisión del dueño del proyecto, adoptada al implementar
`ingesta-job-diario` (FT00009). No supersede ningún ADR; precisa la operación de
ingesta descrita en `CONSTRAINTS.md` y `docs/roadmap.md`.

## Contexto

La ingesta de `docs/roadmap.md` 0.2-T04/T05 exige descargar el sumario del BOE,
parsear cada publicación y **persistirla de forma idempotente** a las 9:30, con
una **segunda pasada** por la tarde. Hasta FT00009 las piezas existían (cliente
del sumario FT00006, parser FT00007, repositorios JDBC FT00008) pero nada las
orquestaba ni las cableaba en el arranque.

El objetivo de despliegue es una máquina única pequeña, sin infraestructura
adicional (nada de systemd timers, Kubernetes CronJob ni cron del host). Hay que
decidir **cómo se programa** el job, **qué ventana horaria** usa por defecto y
**cómo se garantiza** que reejecutar no duplica.

## Decisión

1. **Scheduler interno por corrutina.** El job se lanza como una corrutina del
   propio backend (`IngestaScheduler`), no con el plugin experimental de
   *scheduling* de Ktor ni con un cron externo. El reloj (`now`) y la espera
   (`delay`) son **inyectables** para poder probar el disparo con tiempo virtual.
2. **Ventana `09:30` + segunda pasada `18:00` en `Europe/Madrid`, configurable.**
   El default (documentado en `IngestaConfig`) resuelve la duda abierta de la
   ventana de la tarde; se ajusta por entorno (`INGESTA_*`) sin tocar código.
3. **Idempotencia por `upsert` de `id`.** La segunda pasada re-parsea la **misma
   fecha** para aplicar correcciones que publique el BOE; `PublicationRepository.save`
   es un *upsert* por `id`, así que reejecutar no duplica filas.
4. **Cableado condicional y no bloqueante.** `Application.kt` arranca la ingesta
   solo si `INGESTA_ENABLED` está activo **y** la configuración de BD resuelve;
   cualquier fallo al construirla se registra y el servidor sigue sirviendo
   `/health`. Los recursos (bucle, pool JDBC, clientes HTTP) se cierran en
   `ApplicationStopped`.
5. **Timeouts de red explícitos.** Los clientes HTTP del backend fijan
   `HttpTimeout` (conectar ~10 s, petición/socket ~30 s) para que una descarga
   colgada no bloquee la ventana del job.

## Alternativas consideradas

- **Cron externo / systemd timer / Kubernetes CronJob.** Descartado: añade
  infraestructura y estado fuera del proceso para una máquina única; además el
  contenedor tendría que hablar con el backend. La corrutina interna mantiene el
  despliegue en un solo proceso.
- **Plugin de *scheduling* de Ktor.** Descartado: es experimental y una
  dependencia más; una corrutina propia es suficiente y testeable con tiempo
  virtual.
- **Omitir la segunda pasada si ya hay filas de la fecha.** Descartado: perdería
  las correcciones que el BOE publica por la tarde sobre el mismo `id`; el
  *upsert* reaplica la versión vigente.
- **Solo 9:30 (sin segunda pasada).** Descartado: el BOE corrige sumarios a lo
  largo del día y el corpus quedaría incompleto hasta el día siguiente.

## Consecuencias

- **Habilita** el backfill (FT00011), la clasificación (FT00012) y la
  observabilidad/alerta (FT00010) sobre un job ya programado.
- **Cuesta** que el proceso deba estar en marcha a la hora de la ventana (si se
  reinicia tarde, se recupera con la siguiente ventana o el backfill); el job
  asume el **esquema migrado** (`:backend:flywayMigrate`), no migra al arrancar.
- **Riesgo operativo**: en una máquina de 8 GB la segunda pasada re-parsea la
  fecha completa; se vigila el tiempo de ejecución (optimización diferida).
- Duradero: regla **MUST** en `CONSTRAINTS.md` (timeouts de red explícitos) y
  descripción de `ingesta/job/` y del cableado condicional en `ARCHITECTURE.md`.
