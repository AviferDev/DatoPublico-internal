# Feature Implementation Spec: Renombrado de identificadores a inglés

## Source Feature

- `id`: english-identifiers-rename
- `ft_id`: FT00047 (registrado en `docs/feature-ids.md`)
- `parts`: FT00047-PT1 … FT00047-PT6 (ver «Part Split»; el array `parts` lo
  aplica el orquestador en `feature_list.json`)
- `area`: calidad
- `depends_on`: ingesta-job-diario (FT00009, `accepted`, ya en `main`)
- `status`: accepted (implementado y fusionado 2026-10-16, PR #48, merge `e31dffdf3`)
- `source`: `feature_list.json`
- `claim`: rama `feat/ft00047-english-identifiers-rename` ya reclamada en el repo
  de producto (a cargo del orquestador).

## Goal

Aplicar de forma **incremental** la regla MUST ya vigente «todo el código va en
inglés» (`CONSTRAINTS.md` §«Nombres y contratos», `ARCHITECTURE.md`
§«Convenciones de nombres») al **código heredado en castellano**: renombrar los
**identificadores Kotlin** (paquetes, tipos, funciones, propiedades, constantes,
parámetros, variables y nombres de test) de `:shared` y `:backend` a inglés,
**sin** cambiar el JSON de wire, el esquema de BD, los tokens/datos de la fuente
ni el comportamiento.

Es un refactor **puramente mecánico**: el KDoc y los comentarios siguen en
castellano; cada `@SerialName` conserva su valor; los literales de datos (tokens
de wire, nombres de columna SQL, vocabulario del BOE como `"real decreto"` o
`"enero"`) no se traducen. El gate (`build`/`test`/`detekt`/`init.sh`) sigue
verde en cada parte.

## Non-Goals

- **Cambiar el contrato de wire**: los valores de `@SerialName`, las claves JSON
  y el formato no se tocan.
- **Cambiar el esquema de BD ni las migraciones** (`V1`–`V4`): los nombres de
  tabla/columna en SQL y en `backend/src/main/resources/db/migration/*.sql`
  permanecen en castellano (son datos, no identificadores Kotlin).
- **Traducir tokens/datos de la fuente**: valores de wire de `CategoryDto`/
  `BoeSectionDto`, vocabulario del BOE, mensajes de log/`require`, textos de
  prompt y literales de UI.
- **Traducir KDoc/comentarios**: siguen en castellano.
- **Cambiar comportamiento, dependencias, versiones o arquitectura**.
- **`:composeApp`**: solo tiene entrypoints (`App`, `MainActivity`,
  `MainViewController`, `main`); no contiene identificadores en castellano (solo
  el literal `"Esqueleto Compose Multiplatform"` y el nombre propio
  `DatoPublicoColorScheme`). Fuera de alcance salvo regresión.
- **Nuevas features** (FT00022+, UI, endpoints).

## Job Story

When desarrollo o reviso código de DatoPublico (contrato de `:shared` o capas
internas de `:backend`),
I want leer identificadores en inglés de forma consistente (y KDoc/comentarios en
castellano),
so I can mantener el código sin mezclar idiomas en los identificadores, sin
romper el contrato de wire ni el comportamiento.

## Users And Permissions

- **Desarrollador/agente implementer:** ejecuta el renombrado por partes y el
  gate. No hay usuarios ni permisos de producto implicados.
- **Revisor/validator:** verifica el mapeo old→new, la ausencia de cambios de
  wire/BD y el gate verde.

## Acceptance Scenarios

### Scenario 1: símbolos en inglés, wire intacto

Given el código de producto con los identificadores heredados en castellano
When se aplica el mapeo de renombrado de esta spec
Then no queda ningún identificador en castellano en paquetes, tipos, funciones,
propiedades, constantes ni tests de `:shared`/`:backend`; el KDoc/comentarios
siguen en castellano; y ningún valor de `@SerialName`, clave JSON ni columna SQL
cambia.

### Scenario 2: gate verde en cada parte

Given una parte `FT00047-PTn` aplicada sobre el estado mergeado de la parte
anterior
When se ejecuta el gate estándar
Then `./gradlew build -PskipClient`, `./gradlew test`, `./gradlew detekt`
(incluye `:cpdCheck`) y `.harness/init.sh` terminan con exit 0 y los tests de
wire/BD siguen pasando sin modificar sus aserciones.

### Scenario 3: JSON byte-idéntico para fixtures representativos

Given un `PublicationDto`/`SummaryDto`/`ResumenDiarioDto` de ejemplo y un
fixture real del sumario del BOE
When se serializa con `DatoPublicoJson` antes y después del renombrado
Then el JSON resultante es **byte-idéntico** (mismos tokens `snake_case`, misma
notación `II.B`, mismas claves `queCambia`/`aQuienAfecta`/`cifrasClave`/
`fuenteOficial`/`avisoIA`/`plazo`/`fechaLimite`/`descripcion`).

## Repository Research

### Files Inspected

- `shared/src/commonMain/kotlin/es/aviferdev/datopublico/model/*.kt` — contrato
  (`PublicacionDto`, `ResumenDto`, `ResumenDiarioDto`, `PlazoDto`, `CategoriaDto`,
  `SeccionBoeDto`).
- `shared/src/commonMain/kotlin/es/aviferdev/datopublico/validation/*.kt` —
  validador del contrato (usa `CategoriaDto`, `ResumenDto`, `PlazoDto`).
- `shared/src/commonTest/**` — `SerializationTest`, `CategoriaWireTest`,
  `CitizenSummaryContractTest`, `CitizenSummaryValidatorTest`.
- `backend/.../ingesta/sumario/*` (`BoeSumarioClient`, `BoeSumarioHttpClient`,
  `SumarioWireDto`, `EntradaSumario`, `SingleOrArraySerializer`).
- `backend/.../ingesta/publicacion/*` (`Publicacion`, `DocumentoBoe`,
  `PublicacionParser`, `BoePublicacionParser`, `BoeTextoClient`,
  `BoeTextoHttpClient`, `BoeXmlParser`).
- `backend/.../ingesta/categorizacion/*` (`PublicationClassifier`,
  `DeadlineExtractor` — ya en inglés salvo el paquete).
- `backend/.../ingesta/job/*` y `ingesta/backfill/*` (paquete `ingesta` en
  castellano; resto en inglés).
- `backend/.../persistence/*` (`PublicationRepository` mapea `Publicacion`,
  `FragmentRepository`, `SummaryRepository`, `ReviewQueueRepository`,
  `SummaryCacheRepository`).
- `backend/.../relevance/*`, `backend/.../rag/**` (referencian `Publicacion`,
  `ResumenDto`, `PlazoDto`, `CategoriaDto`, `SeccionBoeDto`).
- `backend/.../Application.kt`, `plugins/*`, `infra/*` (imports de `ingesta.*`;
  sin identificadores castellanos propios).
- `backend/src/main/resources/db/migration/V1..V4` (esquema en castellano).
- `composeApp/src/**` (sin identificadores en castellano).

### Existing Patterns To Follow

- Renombrado previo de contenedores en `:shared` (Sessions 013/014):
  `Publicacion`→`PublicacionDto`, `Resumen`→`ResumenDto`, `DailySummary`→
  `ResumenDiarioDto` con `git mv`, **mismos tokens de wire y JSON**.
- `@SerialName` explícito en cada propiedad `@Serializable` y en los valores de
  enum de wire (`CONSTRAINTS.md` §«Serialización»).
- El código nuevo (FT00009+) ya está en inglés; el heredado se concentra en
  `:shared` y en `ingesta/` de `:backend`.
- Límite de **30 ficheros** por PR y partes `FTxxxxx-PTn`
  (`docs/git-workflow.md`, skill `feature-task-ids`).

### Current Gaps / Footprint (verificado con grep)

- Total producto: **171 ficheros `.kt`** (`:shared` 15, `:backend` 151,
  `:composeApp` 5).
- Ficheros afectados por el renombrado (unión de grep): **≈103**
  (`:shared` main 8 / test 4; `:backend` main 49 / test 42).
- Referencias: `SeccionBoeDto` 40 ficheros, `CategoriaDto` 34, `PlazoDto` 16,
  `ResumenDto` 18, `PublicacionDto` 7, `ResumenDiarioDto` 2.
- Paquete `ingesta`: 53 ficheros lo declaran y 40 lo importan.
- `Publicacion` (backend): 36 ficheros. `EntradaSumario`: 18. `BoeSumario*`: 16.
  `BoePublicacion*`: 11. `BoeTexto*`: 12.
- **313** nombres de test con backtick; un subconjunto relevante son oraciones en
  castellano (p. ej. `` `mapea una entrada del sumario y usa la categoria por
  defecto de la seccion` ``) que deben traducirse.

> **Hallazgo clave de tamaño:** los renombrados son **atómicos por símbolo** (un
> tipo renombrado obliga a actualizar todas sus referencias en el mismo PR para
> no romper la compilación). Varios símbolos superan por sí solos los 30
> ficheros (`SeccionBoeDto` ≈40, `CategoriaDto` ≈34). Por tanto, **no es posible
> cumplir estrictamente el límite de 30 ficheros por PR con renombrados puros**;
> ver «Part Split» para la recomendación.

## Rename Mapping (old → new)

Regla: **todo identificador Kotlin a inglés**; `@SerialName`, claves JSON,
columnas SQL y literales de datos **intactos**.

### `:shared` (`es.aviferdev.datopublico.model` / `.validation`)

| Old | New |
| --- | --- |
| `PublicacionDto` (fichero `PublicacionDto.kt`) | `PublicationDto` (`PublicationDto.kt`) |
| `ResumenDto` (`ResumenDto.kt`) | `SummaryDto` (`SummaryDto.kt`) |
| `ResumenDiarioDto` (`ResumenDiarioDto.kt`) | `DailySummaryDto` (`DailySummaryDto.kt`) |
| `PlazoDto` (`PlazoDto.kt`) | `DeadlineDto` (`DeadlineDto.kt`) |
| `CategoriaDto` (`CategoriaDto.kt`) | `CategoryDto` (`CategoryDto.kt`) |
| `SeccionBoeDto` (`SeccionBoeDto.kt`) | `BoeSectionDto` (`BoeSectionDto.kt`) |
| `PublicacionDto.titulo` | `title` |
| `PublicacionDto.fechaPublicacion` | `publicationDate` |
| `PublicacionDto.organismo` | `issuingBody` |
| `PublicacionDto.seccion` | `section` |
| `PublicacionDto.epigrafe` | `heading` |
| `PublicacionDto.categoria` | `category` |
| `PublicacionDto.urlOficial` | `officialUrl` |
| `PublicacionDto.resumen` | `summary` |
| `PublicacionDto.plazo` | `deadline` |
| `ResumenDto.queCambia` | `whatChanges` |
| `ResumenDto.aQuienAfecta` | `whoIsAffected` |
| `ResumenDto.cifrasClave` | `keyFigures` |
| `ResumenDto.fuenteOficial` | `officialSource` |
| `ResumenDto.avisoIA` | `aiNotice` |
| `ResumenDto.plazo` | `deadline` |
| `PlazoDto.fechaLimite` | `deadlineDate` |
| `PlazoDto.descripcion` | `description` |
| `ResumenDiarioDto.fecha` | `date` |
| `ResumenDiarioDto.publicaciones` | `publications` |
| `CategoriaDto.NORMAS_Y_LEGISLACION` | `NORMS_AND_LEGISLATION` |
| `CategoriaDto.NOMBRAMIENTOS_Y_CESES` | `APPOINTMENTS_AND_DISMISSALS` |
| `CategoriaDto.OPOSICIONES_Y_EMPLEO_PUBLICO` | `PUBLIC_EMPLOYMENT_AND_JOB_OFFERS` |
| `CategoriaDto.BECAS_SUBVENCIONES_Y_AYUDAS` | `SCHOLARSHIPS_GRANTS_AND_AID` |
| `CategoriaDto.PREMIOS` | `AWARDS` |
| `CategoriaDto.CONVENIOS_Y_ACUERDOS` | `AGREEMENTS_AND_CONVENTIONS` |
| `CategoriaDto.EDUCACION_Y_PLANES_DE_ESTUDIO` | `EDUCATION_AND_STUDY_PLANS` |
| `CategoriaDto.MEDIO_AMBIENTE` | `ENVIRONMENT` |
| `CategoriaDto.RECURSOS_Y_RESOLUCIONES` | `APPEALS_AND_RESOLUTIONS` |
| `CategoriaDto.INFORMACION_PUBLICA_Y_CONCESIONES` | `PUBLIC_INFORMATION_AND_CONCESSIONS` |
| `CategoriaDto.OTRAS_DISPOSICIONES_Y_ANUNCIOS` | `OTHER_PROVISIONS_AND_ANNOUNCEMENTS` |
| `SeccionBoeDto.I/II_A/II_B/III/IV/V_A/V_B/V_C` | sin cambio (notación oficial) |

### `:backend` `ingesta/sumario` → `ingestion/summary`

| Old | New |
| --- | --- |
| paquete `...backend.ingesta.sumario` | `...backend.ingestion.summary` |
| `EntradaSumario` | `SummaryEntry` |
| `BoeSumarioClient` / `BoeSumarioException` / `BoeSumarioHttpClient` | `BoeSummaryClient` / `BoeSummaryException` / `BoeSummaryHttpClient` |
| `boeSumarioHttpClient` / `BOE_SUMARIO_BASE_URL` | `boeSummaryHttpClient` / `BOE_SUMMARY_BASE_URL` |
| `BoeSumarioResponseDto` / `BoeSumarioDto` / `BoeSumarioDiarioDto` | `BoeSummaryResponseDto` / `BoeSummaryDto` / `BoeSummaryDailyDto` |
| `BoeMetadatosDto` / `BoeDiarioDto` / `BoeSeccionDto` | `BoeMetadataDto` / `BoeDailyDto` / `BoeSectionDto` |
| `BoeDepartamentoDto` / `BoeTextoDto` / `BoeEpigrafeDto` | `BoeDepartmentDto` / `BoeTextDto` / `BoeHeadingDto` |
| `BoeSumarioItemDto` / `BoeUrlPdfDto` | `BoeSummaryItemDto` / `BoePdfUrlDto` |
| `BoeStatusDto` / `BoeDataDto` | sin cambio (ya inglés) |
| `DiarioListSerializer` / `SeccionListSerializer` | `DailyListSerializer` / `SectionListSerializer` |
| `DepartamentoListSerializer` / `EpigrafeListSerializer` | `DepartmentListSerializer` / `HeadingListSerializer` |
| `ItemListSerializer` | sin cambio |
| `obtenerSumario` | `fetchSummary` |
| `toEntradasSumario` / `entradas` / `toEntrada` | `toSummaryEntries` / `entries` / `toEntry` |
| `seccionBoeDe` / `urlDe` | `boeSectionOf` / `urlFor` |
| props `identificador/titulo/fechaPublicacion/seccion/organismo/epigrafe/urlOficial/urlXml/urlPdf` | `identifier/title/publicationDate/section/issuingBody/heading/officialUrl/xmlUrl/pdfUrl` |
| props `sumario/metadatos/publicacion/numero/codigo/nombre/departamento/texto/urlHtml/diario/sumarioDiario` | `summary/metadata/publication/number/code/name/department/text/htmlUrl/daily/dailySummary` |
| props `paginaInicial/paginaFinal`; `control`, `szBytes`, `szKBytes`, `item` | `firstPage/lastPage`; el resto sin cambio |
| local `fechaIso` | `isoDate` |
| fichero `SumarioWireDto.kt` | `SummaryWireDto.kt` |

### `:backend` `ingesta/publicacion` → `ingestion/publication`

| Old | New |
| --- | --- |
| paquete `...backend.ingesta.publicacion` | `...backend.ingestion.publication` |
| `Publicacion` (`Publicacion.kt`) | `Publication` (`Publication.kt`) |
| `DocumentoBoe` (`DocumentoBoe.kt`) | `BoeDocument` (`BoeDocument.kt`) |
| `MetadatosBoe` | `BoeMetadata` |
| `PublicacionParser` (`PublicacionParser.kt`) | `PublicationParser` (`PublicationParser.kt`) |
| `BoePublicacionParser` / `BoePublicacionHttpParser` | `BoePublicationParser` / `BoePublicationHttpParser` |
| `BoeTextoClient` / `BoeTextoHttpClient` / `BoeTextoException` | `BoeTextClient` / `BoeTextHttpClient` / `BoeTextException` |
| `boeTextoHttpClient` | `boeTextHttpClient` |
| `BoeXmlParser` | sin cambio |
| `parsear` (interfaz y parser) | `parse` |
| `obtenerDocumento` | `fetchDocument` |
| `documentoDe` / `textoDe` / `metadatosDe` | `documentOf` / `textOf` / `metadataOf` |
| `textoHijo` / `hijoDirecto` | `childText` / `directChild` |
| `lineasDe` / `lineasDeNodos` / `lineasDeNodo` / `lineasDeElemento` | `linesOf` / `linesOfNodes` / `linesOfNode` / `linesOfElement` |
| `esUnidadDeTexto` / `tieneDescendienteUnidad` / `textoNormalizado` | `isTextUnit` / `hasUnitDescendant` / `normalizedText` |
| `documentoBuilderFactory` | `documentBuilderFactory` |
| const `ESPACIO_DURO` / `ESPACIOS` / `ETIQUETAS_UNIDAD` | `HARD_SPACE` / `WHITESPACE` / `TEXT_UNIT_TAGS` |
| locals `documento/metadatos/nodo/elemento/padre/etiqueta/nodos/texto/lineas` | `document/metadata/node/element/parent/tag/nodes/text/lines` |
| `Publicacion` props `titulo/fechaPublicacion/organismo/seccion/epigrafe/texto/urlOficial/urlXml/urlPdf/rango/categoria/plazo` | `title/publicationDate/issuingBody/section/heading/body/officialUrl/xmlUrl/pdfUrl/rank/category/deadline` |
| `DocumentoBoe` props `texto/metadatos` | `body/metadata` |
| `MetadatosBoe` props `rango/departamento/fechaDisposicion/numeroOficial/urlPdf/origenLegislativo` | `rank/department/dispositionDate/officialNumber/pdfUrl/legislativeOrigin` |

### `:backend` `ingesta` (raíz) y `ingesta/categorizacion`

| Old | New |
| --- | --- |
| paquete `...backend.ingesta` (job, backfill, etc.) | `...backend.ingestion` |
| paquete `...backend.ingesta.categorizacion` | `...backend.ingestion.categorization` |
| `PublicationClassifier` / `DeadlineExtractor` y sus miembros | sin cambio (ya en inglés) |

### `:backend` persistence / relevance / rag (referencias)

| Old | New |
| --- | --- |
| `PublicationRepository` tipo `Publicacion` / `PlazoDto` / `CategoriaDto` / `SeccionBoeDto` | `Publication` / `DeadlineDto` / `CategoryDto` / `BoeSectionDto` |
| `Publicacion.toPublicationEntity()` / `PublicationEntity.toDomain()` (args `fechaLimite`/`descripcion`) | `Publication.toPublicationEntity()` / `PublicationEntity.toDomain()` (args `deadlineDate`/`description`) |
| `Highlight.publication: Publicacion`; `HighlightRanker` `.seccion/.rango/.categoria/.plazo/.organismo` | `.section/.rank/.category/.deadline/.issuingBody` |
| `ArticleChunker.chunk(publicacion)`; `.seccion/.texto` | `chunk(publication)`; `.section/.body` |
| `FragmentIndexer.index(publication: Publicacion)` | `Publication` |
| `RetrievalGoldenSet.toPublicacion()` y construcción `Publicacion(titulo=…, organismo=…, …)` | `toPublication()` y `Publication(title=…, issuingBody=…, …)` |
| `SummaryGenerationDto` props `queCambia/aQuienAfecta/cifrasClave/plazo`; `toResumenDto` | `whatChanges/whoIsAffected/keyFigures/deadline`; `toSummaryDto` |
| `SummaryGuardrail` / `OfficialSourceValidator` `.urlOficial` / `summary.fuenteOficial` / `.categoria` | `.officialUrl` / `.officialSource` / `.category` |
| `SummaryGroundingChecker` `ResumenDto` / `summary.queCambia/aQuienAfecta/cifrasClave` | `SummaryDto` / `.whatChanges/.whoIsAffected/.keyFigures` |
| `CitizenSummaryGenerator` / `CachedCitizenSummaryGenerator` / `CitizenSummaryPromptBuilder` / `CitizenSummaryResult` refs | tipos/props en inglés |
| `SearchFilter` KDoc `[...Publicacion.fechaPublicacion]` | `[...Publication.publicationDate]` |
| `SearchFilterSql` columnas `p.categoria/p.seccion/p.organismo` | **sin cambio** (SQL) |
| `Application.kt` imports `ingesta.*`, `BoePublicacionHttpParser`, `BoeTextoHttpClient`, `boeTextoHttpClient`, `BoeSumarioHttpClient`, `boeSumarioHttpClient` | rutas y símbolos en inglés |

### Tests

- Nombres de clase: `CategoriaWireTest`→`CategoryWireTest`,
  `BoeSumarioClientTest`→`BoeSummaryClientTest`,
  `SumarioParsingTest`→`SummaryParsingTest`,
  `BoePublicacionParserTest`→`BoePublicationParserTest`,
  `PublicacionParserTest`→`PublicationParserTest`,
  `BoeTextoClientTest`→`BoeTextClientTest`,
  `ResumenCacheMigrationSqlTest`→`SummaryCacheMigrationSqlTest`, etc.
- Nombres de método con backtick en castellano → inglés (p. ej.
  `` `mapea una entrada del sumario y usa la categoria por defecto de la
  seccion` `` → `` `maps a summary entry and uses the section default
  category` ``). Los literales de datos dentro de los tests (fixtures JSON,
  tokens de wire) no se traducen.
- Locals/constantes de test en castellano (`resumen`, `publicacion`, `minima`,
  `tokensEsperados`, `entrada`, `documento`, `TEXTO_CONVOCATORIA_CON_PLAZO`…)
  → inglés.
- Ficheros de test renombrados si llevan el nombre del tipo.

## Part Split (FT00047-PTn)

Orden por dependencia; cada parte se ramifica desde el estado mergeado de la
anterior. La lista exacta de ficheros por parte se deriva con los grep de
«Verification Plan» (referencias al símbolo en `shared/src` + `backend/src`).

| Parte | Alcance (símbolos) | Ficheros ≈ | ≤30 |
| --- | --- | --- | --- |
| **PT1** | `:shared` data classes: `PublicationDto`, `SummaryDto`, `DailySummaryDto`, `DeadlineDto` + sus propiedades + todas las referencias | 29 | ✅ |
| **PT2** | `:shared` enums de wire: `CategoryDto` (+11 constantes) y `BoeSectionDto` + todas las referencias | 49 | ⚠ |
| **PT3** | `:backend` `ingesta/sumario`→`ingestion/summary` (paquete + `SummaryEntry`/`BoeSummary*`/DTOs de wire/serializers) + referencias en job/backfill/Application/tests | 30 | ⚠ |
| **PT4** | `:backend` `ingesta/publicacion`→`ingestion/publication` (paquete + `Publication`/`BoeDocument`/`BoeMetadata`/`BoePublication*`/`BoeText*`/`PublicationParser`/`BoeXmlParser`) + referencias | 50 | ⚠ |
| **PT5** | `:backend` raíz `ingesta`→`ingestion` (job/backfill) y `ingesta/categorizacion`→`ingestion/categorization` + referencias | 30 | ⚠ |
| **PT6** | Internos restantes: persistence/relevance/rag (`toPublication`, `SummaryGenerationDto` props, extensiones), `Application.kt`, y **nombres/identificadores de test en castellano** + barrido de cierre | 50 | ⚠ |

**Sobre el límite de 30 (decisión para el orquestador).** PT2/PT3/PT4/PT5/PT6
superan el límite por **atomicidad de símbolo** (no es divisible sin romper la
compilación; p. ej. `BoeSectionDto` se referencia en ≈40 ficheros). Se
recomienda **una de estas dos vías**:

1. **Excepción documentada** (recomendada): aprobar estas partes como PR de
   **renombrado mecánico** aunque superen 30 ficheros, con la tabla de mapeo como
   guía de revisión y el gate verde. El límite es una guía de revisabilidad; un
   renombrado puro, sin cambios de wire/BD, es de bajo riesgo.
2. **Renombrado por etapas con alias temporal** (si se exige ≤30): en `:shared`
   introducir el nombre inglés como canónico y un `typealias` `@Deprecated` con
   el nombre antiguo; migrar las referencias por lotes ≤30; retirar el alias en
   la última parte. **No cubre** constantes de enum ni propiedades (no
   aliasables), por lo que requiere además accesores `@Deprecated`; es más
   complejo y solo para nombres de tipo.

Cada parte **debe** incluir las referencias en tests al símbolo renombrado para
mantener el gate verde. El orden PT1→PT6 evita dependencias cruzadas (los tipos
de `:shared` se renombran antes que sus consumidores de `:backend`; dentro de
`:backend`, `ingesta/sumario` antes que `ingesta/publicacion`).

## Technical Approach

1. Para cada parte, aplicar el mapeo con `git mv` (ficheros) + edición de
   identificadores. **No** tocar: valores de `@SerialName`, claves JSON,
   literales SQL de columna, migraciones, tokens de wire, vocabulario del BOE ni
   mensajes dirigidos al operador.
2. Renombrar paquetes moviendo directorios (`git mv`) y actualizando
   `package`/`import`; mantener `settings.gradle.kts`/`build.gradle.kts` (los
   módulos no cambian).
3. Traducir los nombres de test con backtick y los identificadores locales de
   test; conservar los fixtures y tokens de wire.
4. Mantener KDoc/comentarios en castellano; actualizar los enlaces KDoc
   `[TipoAntiguo]`→`[TipoNuevo]`.
5. Cerrar con el barrido de completitud y el gate completo.

## Expected File Changes

- `shared/src/commonMain/.../model/{PublicacionDto,ResumenDto,ResumenDiarioDto,PlazoDto,CategoriaDto,SeccionBoeDto}.kt`
  → `{PublicationDto,SummaryDto,DailySummaryDto,DeadlineDto,CategoryDto,BoeSectionDto}.kt` (modify/rename).
- `shared/src/commonMain/.../validation/{CitizenSummaryValidator,CitizenSummaryVariant}.kt` (modify; refs).
- `shared/src/commonTest/**` (modify/rename; refs + nombres de test).
- `backend/.../ingesta/sumario/*` → `backend/.../ingestion/summary/*` (rename + modify).
- `backend/.../ingesta/publicacion/*` → `backend/.../ingestion/publication/*` (rename + modify).
- `backend/.../ingesta/{job,backfill,categorizacion}/*` (package + refs).
- `backend/.../persistence/{PublicationRepository,SummaryCacheRepository}.kt` (modify).
- `backend/.../relevance/*`, `backend/.../rag/**` (modify; refs).
- `backend/.../Application.kt` (modify; imports).
- `backend/src/test/**` (modify/rename; refs + nombres de test).
- **No** se modifican: `db/migration/*.sql`, `@SerialName`, `:composeApp`.

La lista completa por parte se obtiene con:
`grep -rlE --include='*.kt' '\b<Símbolo>\b' shared/src backend/src`.

## Visual Design Impact

- UI involved: no. Cambio puramente de identificadores Kotlin; sin efecto visual.
- Design source: not applicable.
- Screens or states affected: none.
- New design artifact required: no.

## Durable Documentation Impact

- `ARCHITECTURE.md`: **update** — §«Convenciones de nombres» cita
  `PublicacionDto`, `CategoriaDto`, `EntradaSumario`, `Publicacion`,
  `BoeSumarioClient` como deuda FT00047; tras el renombrado hay que actualizar
  los ejemplos a los nombres ingleses y retirar la nota de deuda.
- `CONSTRAINTS.md`: **update** — §«Nombres y contratos» cita los mismos
  identificadores en castellano como deuda; actualizar los ejemplos y la
  referencia a FT00047 cuando esté cerrada.
- `AGENTS.md`: **not needed** — la regla ya está enunciada; no cambia el flujo.
- `docs/domain-model.md` / `CONTEXT.md`: **not needed** — describen el dominio en
  prosa; revisar solo referencias a nombres de tipo si las hubiera.
- `docs/feature-ids.md`: **update** — estado de FT00047 (y sus partes).
- ADR: **not needed** — no hay decisión durable nueva; se aplica una regla
  existente.

## Implementation Plan

1. **PT1**: renombrar las data classes de `:shared` y sus propiedades + refs;
   gate verde.
2. **PT2**: renombrar los enums de wire y las constantes de `CategoryDto` + refs;
   gate verde.
3. **PT3**: renombrar `ingesta/sumario`→`ingestion/summary` + símbolos + refs;
   gate verde.
4. **PT4**: renombrar `ingesta/publicacion`→`ingestion/publication` + símbolos +
   refs; gate verde.
5. **PT5**: renombrar la raíz `ingesta`→`ingestion` y `categorizacion`; gate
   verde.
6. **PT6**: internos restantes (persistence/relevance/rag/Application) + nombres
   de test en castellano + barrido de cierre; gate verde.
7. Actualizar `ARCHITECTURE.md`/`CONSTRAINTS.md` y registrar evidencia.

## Implementation Tasks

- [x] (PT1) Mapear `:shared` data classes + propiedades; `git mv` ficheros.
- [x] (PT1) Actualizar refs en `:shared`/`:backend` y tests; gate.
- [x] (PT2) Renombrar `CategoryDto`/`BoeSectionDto` + constantes; refs; gate.
- [x] (PT3) Renombrar `ingesta/sumario`→`ingestion/summary`; refs; gate.
- [x] (PT4) Renombrar `ingesta/publicacion`→`ingestion/publication`; refs; gate.
- [x] (PT5) Renombrar raíz `ingesta`→`ingestion` + `categorizacion`; refs; gate.
- [x] (PT6) Internos persistence/relevance/rag + Application; nombres de test;
      barrido de cierre; gate.
- [x] Actualizar `ARCHITECTURE.md`/`CONSTRAINTS.md`; registrar evidencia.

> Implementado (2026-10-16, PR #48). Desviación: `BoeSeccionDto`→
> `BoeSectionNodeDto` (colisión con `BoeSectionDto` de `:shared`).

## Verification Plan

Gate estándar (desde la raíz del producto `..`), SDK-free, sin arrancar
servidores:

- `./gradlew build -PskipClient` → BUILD SUCCESSFUL.
- `./gradlew test` → `:shared:jvmTest` + `:backend:test` verdes (los tests de
  wire/BD pasan **sin modificar aserciones**).
- `./gradlew detekt` (Detekt + `:cpdCheck`) → sin hallazgos nuevos.
- `../.harness/init.sh` (o `.harness/init.sh`) → exit 0; no arranca servidores.

Completitud (0 coincidencias tras la última parte):

```sh
grep -rnE --include='*.kt' \
  '\b(PublicacionDto|ResumenDto|ResumenDiarioDto|PlazoDto|CategoriaDto|SeccionBoeDto|EntradaSumario|DocumentoBoe|MetadatosBoe|BoeSumario[A-Za-z]*|BoePublicacion[A-Za-z]*|BoeTexto[A-Za-z]*|PublicacionParser|SumarioWire[A-Za-z]*|toEntradasSumario|obtenerSumario|obtenerDocumento|seccionBoeDe|toResumenDto)\b' \
  shared/src backend/src composeApp/src
```

Barrido de raíces castellanas (triaje manual; los hits deben ser solo KDoc,
literales de datos, SQL, migraciones o nombres propios):

```sh
grep -rEn --include='*.kt' \
  '\b(publicacion|sumario|entrada|documento|metadatos|diario|departamento|epigrafe|titulo|organismo|categoria|seccion|plazo|resumen|fuente|aviso|cifras|cambia|afecta|descripcion|rango|numero|codigo|nombre|pagina|obtener|parsear|ingesta|categorizacion)\b' \
  shared/src backend/src composeApp/src \
  | grep -vE ':[0-9]+: *(//|\*|/\*)'
```

Invariantes (deben ser **vacíos**):

```sh
# 1) Ningún @SerialName cambiado:
git diff main...HEAD -- '*.kt' | grep -E '^[-+].*@SerialName'
# 2) Migraciones intactas:
git diff --stat main...HEAD -- backend/src/main/resources/db/migration
# 3) SQL de columnas de BD intacto (revisión del diff de persistence/retrieval).
```

JSON byte-idéntico: `./gradlew :shared:jvmTest` incluye
`SerializationTest.publicationWithResumenRoundTrips` (asserta
`"oposiciones_y_empleo_publico"` y `"II.B"`),
`CitizenSummaryContractTest.summaryJsonKeepsFrozenWireKeys` (claves
`queCambia/aQuienAfecta/cifrasClave/fuenteOficial/avisoIA/plazo`) y
`summaryJsonKeepsFrozenDeadlineKeys` (`fechaLimite/descripcion`);
`BoeSumarioClientTest`/`SumarioParsingTest` validan fixtures reales del BOE
byte-idénticos. Estos tests deben pasar sin tocar sus aserciones. Si se desea,
añadir un test de snapshot JSON para `PublicationDto`/`SummaryDto` (mismo JSON
antes/después).

No hay E2E persistente en el repo (no aplica); la cobertura de wire/BD por
unit/integration con dobles es suficiente porque no cambia ningún flujo.

## Evidence To Capture

- Salida de `./gradlew build -PskipClient` / `test` / `detekt` / `init.sh` (exit
  0) por cada parte.
- Recuento de tests (`:shared` 26; `:backend` ≈278) sin regresiones.
- Resultado del grep de completitud (0 coincidencias) y del barrido de raíces
  (solo comentarios/literales).
- `git diff` mostrando 0 cambios en `@SerialName`, migraciones y SQL de columnas.
- Actualización de `ARCHITECTURE.md`/`CONSTRAINTS.md`.

## Validator Checklist

- [ ] No queda ningún identificador en castellano en paquetes, tipos, funciones,
      propiedades, constantes ni tests de `:shared`/`:backend`; KDoc/comentarios
      en castellano.
- [ ] Ningún `@SerialName`, clave JSON, columna SQL ni migración ha cambiado.
- [ ] JSON byte-idéntico para fixtures representativos (tests de wire verdes sin
      cambiar aserciones).
- [ ] `build`/`test`/`detekt`/`init.sh` verdes en cada parte y en el estado final.
- [ ] `:composeApp` intacto; sin cambios de comportamiento.
- [ ] `ARCHITECTURE.md`/`CONSTRAINTS.md` actualizados.
- [ ] El mapeo old→new de la spec se respetó (sin nombres inventados).

## Harness Bookkeeping (a aplicar por el orquestador)

- `feature_list.json` (FT00047): añadir el array `parts` con
  `FT00047-PT1..PT6` (`area`/`scope`/`status`) según la tabla «Part Split»;
  estado `not_started`→`in_progress` al arrancar; evidencia al cerrar.
- `docs/feature-ids.md`: reflejar el estado de FT00047.
- `PROGRESS.md`: entrada de sesión con la decisión sobre el límite de 30 y el
  resultado por parte.
