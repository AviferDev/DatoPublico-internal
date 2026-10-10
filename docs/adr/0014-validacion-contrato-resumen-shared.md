# ADR 0014: Validación del contrato del resumen ciudadano en `:shared`

## Estado

Aceptado (2026-10-10). Decisión del dueño para FT00019 (`contrato-resumen-ciudadano`).

## Contexto

El contrato del **resumen ciudadano** ya existe como DTO de wire en `:shared`
(`ResumenDto`: `queCambia`, `aQuienAfecta`, `cifrasClave`, `fuenteOficial`,
`avisoIA`, `plazo`, con `@SerialName` explícito; FT00002). Sin embargo, su
obligatoriedad y validación solo estaban **comentadas** en el KDoc: no había
ninguna comprobación ejecutable de que un resumen tuviera fuente oficial, las
secciones «¿Qué cambia?»/«¿A quién afecta?» y —para empleo público y becas— el
**plazo**.

El resumen lo **genera** el backend (FT00020) y lo **revisa** el pipeline de
guardrails (FT00022), que decidirá publicar, enviar a revisión o descartar. Antes
de generar hay que fijar el **contrato** que ese pipeline debe respetar, sin
mezclarlo con la verificación de **contenido** (alcanzabilidad del enlace,
afirmaciones fuera del contexto recuperado), que es otra responsabilidad.

## Decisión

Añadir en `:shared`, paquete `es.aviferdev.datopublico.validation`, la validación
**pura del contrato** del resumen ciudadano:

- `CitizenSummaryVariant` (`GENERAL`, `EMPLOYMENT_OR_SCHOLARSHIP`) y
  `CitizenSummaryVariantResolver.variantFor(category)` resuelven la variante a
  partir de la `CategoriaDto`; es un **valor interno** (sin sufijo `Dto`, no
  `@Serializable`) porque no es un tipo de wire.
- `CitizenSummaryViolation` enumera las violaciones y `CitizenSummaryValidation`
  expone `violations` y un `isValid` **derivado** (`violations.isEmpty()`).
- `CitizenSummaryValidator.validate(summary, category)` es un `object` **puro**
  (sin red, BD, reloj ni estado) que **acumula** violaciones y **no lanza**: un
  resumen inválido es un **resultado esperado** para el consumidor, no un error de
  programación. Comprueba fuente oficial obligatoria con enlace absoluto
  `http(s)://`, secciones no vacías, cifras clave sin entradas en blanco y, en la
  variante de empleo/beca, plazo con `fechaLimite` no vacía.
- Se **reutilizan** `ResumenDto`/`CategoriaDto`/`PlazoDto`; **no** se crea un DTO
  nuevo y **no** se cambia el JSON de wire de `ResumenDto`.

## Alternativas consideradas

- **Validar en `:backend`.** Se descarta: el contrato es compartido y el cliente
  puede reutilizar el validador para no renderizar resúmenes incompletos; además
  `:shared` es donde vive el contrato que se valida.
- **Lanzar una excepción ante un resumen inválido** (patrón *fail-fast* de
  configuración, `PgVector`/`SearchFilterSql`). Se descarta: un resumen inválido es
  un estado de dominio esperado (ir a revisión/descartar), no un error de
  programación; el consumidor necesita la **lista** de violaciones, no la primera.
- **Crear un DTO de resumen nuevo o renombrar el existente.** Se descarta: rompería
  el contrato de wire congelado de `ResumenDto` (FT00002) sin necesidad.
- **Validar también la veracidad/alcanzabilidad aquí.** Se descarta: son
  **guardrails de contenido** (FT00022); este validador comprueba solo la
  **estructura y la presencia** de la fuente.

## Consecuencias

- FT00020 (generación) y FT00022/FT00023 (guardrails y cola de revisión) consumen
  un validador estable y sin excepciones; el cliente puede reutilizarlo.
- La frontera queda explícita: **contrato** (FT00019, `:shared`) vs. **guardrails
  de contenido** (FT00022, `:backend`).
- Es una **librería sin wiring**: no se cablea en `Application.kt`, no añade
  endpoints/UI ni migración, y no toca `:backend`/`:composeApp`.
- El contrato de wire de `ResumenDto` **no cambia**; los tests de contrato
  (`CitizenSummaryContractTest`) fijan las claves de wire.
- La exigencia del **aviso de IA** (`avisoIA`) queda para FT00023; aquí solo se
  modela (ya está en `ResumenDto`).
- Riesgo conocido: una convocatoria de empleo/beca cuya fuente no traiga plazo
  quedará inválida y deberá ir a revisión; la política fina se resolverá en
  FT00022/FT00023.
