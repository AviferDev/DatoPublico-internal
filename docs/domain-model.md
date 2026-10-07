# Domain Model

## Core Concepts

- **Norma:** disposición general publicada en la Sección I del BOE.
- **Fragmento (chunk):** porción de una norma (artículo o sección) usada para
  indexado y recuperación.
- **Resumen ciudadano:** explicación en lenguaje claro de una norma.
- **Fuente oficial:** URL al texto oficial de la norma en el BOE.
- **Confianza:** medida de calidad/riesgo del resumen generado automáticamente.
- **Feed diario:** agrupación de normas nuevas por fecha de publicación.
- **Usuario:** en 1.0.0, anónimo; no hay cuentas ni sesión persistente.
- **Colectivos afectados:** en 1.0.0, "¿A quién afecta?" describe colectivos
  amplios (ciudadanía, trabajadores, empresas, autónomos, arrendatarios…).

## Relationships

- Una **Norma** tiene **1..N Fragmentos**.
- Una **Norma** tiene **1 Resumen ciudadano** (en 1.0.0, sin versionado
  gestionado de resúmenes).
- Un **Resumen** referencia **1 Fuente oficial** (obligatoria).
- El **Feed diario** agrega **Normas** nuevas por fecha.
- Un **Resumen** puede estar en la **Cola de revisión** según su Confianza.

## States and Lifecycles

**Norma** (1.0.0): `publicada` → estado único gestionado. No se modelan
derogación ni modificación en esta versión.

**Resumen ciudadano:**

```text
pendiente
   → generado
      → validado_por_guardrails
         → publicado            (confianza suficiente)
         → en_cola_revision     (baja confianza)
            → revisado
               → publicado
               → descartado
      → descartado              (guardrail falla sin recuperación)
```

## Important Scenarios

- **Ingesta diaria:** descarga del sumario, parseo y persistencia de normas.
- **Backfill:** carga del histórico de los últimos 2-3 años.
- **Generación:** chunking → embeddings → recuperación → resumen + fuente.
- **Guardrail fallido:** el resumen no se publica o entra en cola.
- **Publicación:** el feed del día queda disponible en la API.
- **Búsqueda:** consulta del usuario contra el corpus indexado.

## Edge Cases

- Norma sin texto completo disponible en la fuente.
- Norma muy extensa (necesita chunking/recuperación cuidadosos).
- Duplicados o publicaciones corregidas por el BOE.
- Normas en lenguas cooficiales distintas del castellano (excluidas en la
  1.0.0).
- Norma que modifica otra existente (fuera de alcance de 1.0.0, pero presente en
  los datos).
- Fallo o cambio de formato de la fuente oficial durante la ingesta.
