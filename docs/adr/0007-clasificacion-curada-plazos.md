# ADR 0007: Clasificación curada determinista y extracción acotada de plazos (sin IA)

## Estado

Aceptado (2026-10-10). Decisión del dueño del proyecto. No supersede ningún ADR.

## Contexto

La 1.0.0 ingiere **todo el sumario del BOE** (secciones I, II.A, II.B, III, IV,
V.A, V.B y V.C). El feed y los filtros deben hablar por **familia de contenido**
(las 11 categorías curadas de `CategoriaDto`), no por sección, y las
convocatorias (empleo público, becas y subvenciones) deben exponer su **plazo de
solicitud** cuando la fuente lo indica.

Hay dos tentaciones que conviene descartar por adelantado:

1. **Clasificar con IA/LLM** (o con embeddings): coste por publicación, no
   determinista, difícil de testear en el gate y de auditar; además embebe la
   clasificación en el pipeline RAG, que es una decisión posterior (FT00014–16).
2. **Extraer los plazos con generación**: los textos del BOE son texto libre y
   abundan frases que *parecen* un plazo sin serlo («plazo de ejecución», plazos
   de recurso, de resolución, de subsanación). Un generador alucinaría fechas.

Se necesita una base **verificable en el gate** (sin red ni BD) y estable como
contrato, que alimente la ingesta existente sin tocar el arranque
(`Application.kt`) ni el contrato de `:shared` (la persistencia de FT00008 ya
guarda `categoria` y `plazo` nullable).

## Decisión

- **Clasificación curada determinista.** En `:backend`,
  `ingesta/categorizacion/PublicationClassifier` mapea **sección + epígrafe +
  título** a una de las 11 `CategoriaDto` mediante una **tabla de reglas de
  palabra clave ordenada** (primero el epígrafe, luego el título) y **categorías
  por defecto por sección** cuando ninguna regla casa. Es **pura** (sin red, BD,
  IA, reloj ni estado) y **siempre** devuelve una categoría (nunca `null`); el
  **epígrafe original se conserva** como metadato. El orden de las reglas es el
  contrato determinista.
- **Extracción de plazos heurística y acotada.** `DeadlineExtractor` reconoce
  únicamente patrones concretos —`plazo de <N> días [hábiles|naturales]` con la
  coletilla «a contar/contados/a partir … el día siguiente al de la publicación»,
  y fechas explícitas «hasta el <d> de <mes> de <aaaa>» / «hasta el dd/mm/aaaa»—
  tras una **puerta de contexto** («presentación de solicitudes» / «presentar …
  solicitud/documentación») y **descarta** los contextos de ejecución, resolución,
  recurso, subsanación, alegaciones o informe. Devuelve `PlazoDto` o, si no es
  fiable, **`null`**: **nunca inventa una fecha**. Los «días hábiles» cuentan solo
  sábados y domingos (sin calendario de festivos).
- **Cableado aditivo** en `PublicacionParser` mediante colaboradores con valor
  por defecto, de modo que el job diario (FT00009) y el backfill (FT00011), que
  reutilizan el parser, obtienen `categoria`/`plazo` sin cambios en
  `Application.kt`, en `:shared` ni en el esquema.

## Alternativas consideradas

- **Clasificación por LLM o embeddings.** Descartada: coste, no determinismo,
  dificultad de verificación en el gate y acoplamiento prematuro al RAG.
- **Plazos con generación/LLM.** Descartada: riesgo de alucinación de fechas y
  de falsos positivos en plazos de ejecución/recurso.
- **Clasificar solo por sección (sin reglas de epígrafe).** Descartada: la
  sección es demasiado gruesa (I mezcla subvenciones y normativa; III mezcla
  ayudas y otras disposiciones) y no cumple los escenarios del spec.
- **Tabla de reglas como configuración externa (BD/fichero).** Descartada para la
  1.0.0: una tabla en código versionada es determinista, testeable y suficiente;
  si crece, se migrará (deuda aceptada).

## Consecuencias

- **Habilita** el feed por categoría, los filtros y el resaltado del plazo en la
  UI (FT00032+) sin coste de IA y con comportamiento reproducible.
- **Cuesta** asumir que el mapeo sección/epígrafe → categoría es **heurístico**
  (epígrafes irregulares o ausentes) y que los plazos son **parciales**: patrones
  no cubiertos (tablas/PDF, «un mes», «entrada en vigor») y festivos quedan como
  deuda documentada. El detalle fino de clasificación es deuda aceptada.
- **Cambia** el resultado del parser de FT00007: `categoria` deja de ser `null` y
  `plazo` puede tener valor; los tests de FT00007 afectados se actualizan (cambio
  esperado, no regresión de contrato).
- **Documentación/código**: reglas MUST en `CONSTRAINTS.md`, mapa de
  `ingesta/categorizacion/` en `ARCHITECTURE.md` y nota en
  `docs/desarrollo-local.md`. Sin cambios en `:shared`, migraciones, `Application.kt`
  ni CI.
