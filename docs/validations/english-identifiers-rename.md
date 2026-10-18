# Validación — `english-identifiers-rename` (FT00047)

- **Rama**: `feat/ft00047-english-identifiers-rename` (PR #48) · fusionada en `main`
  como `e31dffd` (fast-forward; árbol idéntico al CI testeado `a8fb098`).
- **Rango validado**: `2fdb02a..e31dffd` (6 commits `7601a77` → `e31dffd`, partes
  PT1–PT6).
- **Spec**: `docs/specs/english-identifiers-rename.md`.
- **Validador**: `feature-validator` (independiente del implementador).
- **Fecha**: 2026-10-18.

## Veredicto

**`accept`** (sin reparaciones obligatorias).

| Ronda | Veredicto | Motivo |
| --- | --- | --- |
| 1 | **`accept`** | Escenarios S1–S3 cumplidos; invariantes de wire/BD verificados; solo hallazgos Low/Info no bloqueantes. |

## Checks reejecutados

| Check | Comando | Resultado |
| --- | --- | --- |
| Gate estándar | `./gradlew build -PskipClient` | BUILD SUCCESSFUL (exit 0); detekt + `:cpdCheck` verdes |
| Tests | `./gradlew :shared:jvmTest :backend:test -PskipClient --rerun-tasks` | BUILD SUCCESSFUL; `:shared` **39**, `:backend` **486**, 0 fallos/errores/skips |
| CI | run `38913504444` (workflow «CI», job «Build and test») | `success` |

Comprobaciones estáticas propias:

| Invariante | Resultado |
| --- | --- |
| Claves `@SerialName` (valores) | **119 valores, `diff` vacío** antes/después (coincide con spec y bitácora) |
| Migraciones Flyway | **0** ficheros modificados |
| SQL de columnas/tablas | **0** cambios |
| Ficheros de `:composeApp` | **0** |
| Identificadores en castellano | **ninguno** en declaraciones (solo KDoc/prosa/literales de datos/SQL/tokens de wire) |
| Alcance | 159 ficheros (3105+/3103−), 6 commits atómicos; único no-`.kt`: `openapi.json` |
| Excepción de 30 ficheros | Documentada en `docs/git-workflow.md` §«Excepción: renombrados mecánicos atómicos» |

## Escenarios de aceptación

- **S1** (símbolos en inglés, wire intacto): ✅
- **S2** (gate verde): ✅
- **S3** (JSON byte-idéntico; tests de wire congelados sin tocar sus aserciones): ✅

## Hallazgos (todos no bloqueantes)

### F1 — Cambio no declarado en el contrato OpenAPI (Low)

`backend/src/main/resources/openapi/openapi.json` es el único fichero no-`.kt` del
diff: se renombraron las claves de `components.schemas`
(`PublicacionDto`→`PublicationDto`, `ResumenDto`→`SummaryDto`,
`ResumenDiarioDto`→`DailySummaryDto`, `PlazoDto`→`DeadlineDto`,
`CategoriaDto`→`CategoryDto`, `SeccionBoeDto`→`BoeSectionDto`) y sus `$ref`. No
aparece en «Expected File Changes» del spec ni en la evidencia.

Es **consecuencia mecánica necesaria**: `OpenApiContractTest` (anti-deriva) indexa
los esquemas por nombre de tipo, así que `openapi.json` debe seguir al renombrado
o el gate falla. Los *payloads* y los tokens de wire no cambian (nombres de
propiedad y `snake_case` intactos), por lo que **no rompe clientes**.
**Requerido**: dejar constancia en la evidencia/bitácora (hecho en el cierre).

### F2 — Enlaces KDoc obsoletos (~18 en 8 ficheros) (Low)

`[fechaLimite]`, `[fuenteOficial]`, `[urlOficial]`, `[urlXml]`, `[urlPdf]`,
`[fechaPublicacion]`, `[epigrafe]`, `[resumen]`, `[plazo]`, `[fecha]`,
`[publicaciones]`, `[avisoIA]`, `[obtenerDocumento]`, `[toResumenDto]` en
`PublicationDto.kt`, `DeadlineDto.kt`, `DailySummaryDto.kt`, `SummaryDto.kt`,
`Publication.kt`, `BoeTextClient.kt`, `SummaryEntry.kt`, `BoeSummaryClient.kt` y
`SummaryGenerationDto.kt`. El spec (Technical Approach §4) pedía actualizar los
enlaces KDoc; los `[TipoAntiguo]` sí se actualizaron, pero no las props/funciones.
No los valida el compilador ni detekt (solo Dokka). **Deuda** (PR menor de docs).

### F3 — Literal con el nombre antiguo (Low)

`BoePublicationLiveTest.kt:25` → `println("BoePublicacionLiveTest omitido: …")`
mientras la clase es `BoePublicationLiveTest`. Sin impacto funcional. **Deuda**.

### F4 — KDoc de `:composeApp` con nombres antiguos (Info)

`SearchResponseDto.kt`, `SearchModels.kt`, `DetailModels.kt`, `FeedResponseDto.kt`
y `FeedModels.kt` citan en prosa los nombres antiguos de `:shared`. `:composeApp`
estaba fuera de alcance (invariante respetado). **Deuda**.

### F5 — Evidencia imprecisa sobre el grep de completitud (Info)

`PROGRESS.md` Session 088 y la evidencia afirman «grep → 0 coincidencias»; el grep
del listado del spec devuelve **10 hits** (9 en KDoc/comentarios y 1 literal de
`println`). Semánticamente correcto (no son identificadores), pero la cifra «0» no
es reproducible literalmente.

### F6 — Salvedad `CategoryDto.name` (Low/Note, documentada)

`PublicationRepository.kt:66` persiste `category?.name` y `:94` lee
`CategoryDto.valueOf(...)`; `SearchFilterSql.kt:54` liga `value.name`;
`CitizenSummaryPromptBuilder.kt:62` embebe `${category.name}` en el prompt. Con
PT2 los valores persistidos pasan de `NORMAS_Y_LEGISLACION` a
`NORMS_AND_LEGISLATION`. El token de wire sigue intacto por `@SerialName`.

Sin seeds en migraciones `V1`–`V5` y sin datos de producción conocidos (el
despliegue de FT00041/FT00052 no está poblado), así que **no requiere migración
ahora**. **Riesgo residual**: si existe una BD poblada antes del release, cualquier
fila antigua rompería `valueOf` en lectura (fail-fast → 500). En ese caso hace
falta un `UPDATE` de un solo uso. El equipo lo documentó explícitamente.

### F7 — Docs durables parcialmente actualizadas (Info)

`ARCHITECTURE.md` §«Convenciones de nombres» y `CONSTRAINTS.md` §«Nombres y
contratos» (lo exigido por el spec) sí se actualizaron. Otras secciones conservan
nombres antiguos en prosa (p. ej. `FeedDtoMapper.toPublicacionDto` en
`CONSTRAINTS.md` §Detalle, `ResumenDiarioDto` en `ARCHITECTURE.md` §Contrato de
wire). El spec acotó la actualización → deuda de barrido.

### F8 — Precisión de evidencia: «merge commit» (Info)

`e31dffd` es un commit de un solo padre (fast-forward del PR #48), no un *merge
commit*. El árbol es idéntico al del CI testeado (`git diff` vacío).

## Seguridad

Refactor puro de identificadores: sin secretos, sin cambios de auth/authz,
entrada/salida, rutas ni llamadas externas; SQL intacto y parametrizado; sin
dependencias nuevas. **Sin hallazgos de seguridad.**

## Estado de documentación / harness

- `feature_list.json`: FT00047 y sus 6 partes `accepted` con evidencia por parte ✅
- `docs/feature-ids.md`: FT00047 `accepted` ✅
- `PROGRESS.md` Session 088: presente y coherente (con las imprecisiones F5/F2) ✅
- `ARCHITECTURE.md`/`CONSTRAINTS.md`: secciones exigidas actualizadas ✅ (F7 = deuda)
- Handoff: el árbol queda arrancable (`build`/`tests` verdes).

## Follow-up (no bloqueante)

1. Actualizar los enlaces KDoc obsoletos (F2) y el literal de F3 en un PR menor.
2. Barrido opcional de nombres antiguos en prosa de `ARCHITECTURE.md`/`CONSTRAINTS.md`
   y en el KDoc de `:composeApp` (F4/F7).
3. Antes del release: si existe una BD poblada, `UPDATE` de un solo uso de los
   valores de categoría (F6).
