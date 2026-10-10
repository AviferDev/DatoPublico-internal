# Registro de decisiones de arquitectura (ADR)

> Un **ADR** («Architecture Decision Record») captura **una** decisión técnica o de
> proceso, su contexto y sus consecuencias. Sirve para no reabrir en silencio
> decisiones ya tomadas y para que una sesión futura entienda **por qué** el
> repositorio está como está.

## Cuándo escribir un ADR

- Cuando se toma una decisión **durable** que condiciona features futuras
  (modelo de datos, arquitectura, integración externa, despliegue, flujo de
  trabajo, seguridad).
- Cuando una decisión **supersede** o **ajusta** otra anterior.
- **No** para detalles de implementación de una sola feature (eso va en
  `docs/specs/<feature-id>.md`) ni para lo ya fijado por los skills de arquitectura.

## Formato

- Fichero: `docs/adr/<NNNN>-<slug>.md`, con `NNNN` de 4 dígitos (`0001`, `0002`…)
  y `<slug>` en `kebab-case` sin acentos. Los números **no** se reutilizan ni se
  renumeran.
- Cabecera `# ADR NNNN: <título>` y estas secciones, en este orden:

```md
# ADR NNNN: <título>

## Estado

Aceptado (<AAAA-MM-DD>). [Quién decide y, si aplica, qué ADR supersede/ajusta.]

## Contexto

<Situación, restricciones y por qué hay que decidir.>

## Decisión

<La decisión, en afirmaciones concretas y accionables.>

## Alternativas consideradas

<Cada opción descartada y por qué.>

## Consecuencias

<Qué habilita, qué cuesta, qué documentación o código hay que tocar.>
```

## Reglas

- Una decisión por fichero; el título es corto y concreto.
- Estado habitual: `Aceptado` (decisión del dueño), `Superseded by ADR NNNN` o
  `Retirado`. No hay estados «propuesto» en el flujo: se discute antes de escribir.
- Para reabrir una decisión: escribir un ADR nuevo que la **supersede** o la
  **ajusta**, nunca editar el anterior salvo para marcar su estado.
- Antes de contradecir una decisión aceptada, léela.

## Índice

| ADR | Título | Estado |
| --- | --- | --- |
| [0001](0001-dos-repositorios-harness-privado.md) | Dos repositorios: producto público + harness privado | Aceptado |
| [0002](0002-fuente-texto-boe-xml.md) | El texto y los metadatos del BOE se toman del XML estructurado (`xml.php`) | Aceptado |
| [0003](0003-jdbc-hikari-sin-orm.md) | Capa de datos con JDBC + HikariCP (sin ORM) y esquema relacional inicial | Aceptado |
| [0004](0004-ingesta-programada-interna.md) | Ingesta programada interna por corrutina (sin cron externo) | Aceptado |
| [0005](0005-observabilidad-ingesta-logs-watchdog.md) | Observabilidad de la ingesta por logs estructurados + vigilante interno | Aceptado |
