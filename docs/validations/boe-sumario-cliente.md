# Validación — boe-sumario-cliente (FT00006)

> **Nota (2026-10-10):** este documento recoge la validación **original** (alcance de 5 secciones: I, II.A, II.B, III, V.B) y la revalidación del refactor de **retorno único**. Ambas quedan **superadas** por el **cambio de alcance** a todo el BOE (8 secciones) y la norma de `@SerialName`; ver la sección **«Revalidación del cambio de alcance y `@SerialName`»** al final.

- Fecha: 2026-10-10
- Rol: `validator` (independiente del implementador)
- Feature: `boe-sumario-cliente` (FT00006), estado de entrada: `passing`
- Spec: `docs/specs/boe-sumario-cliente.md`
- Rama de producto: `feat/ft00006-boe-sumario-cliente` (diff sin commitear vs `origin/main`; claim `03b00b8`)
- Veredicto: **`accept`**

## Checks reejecutados (evidencia real, no autoevaluación)

| Check | Comando | Resultado |
| --- | --- | --- |
| Tests backend | `./gradlew :backend:test --rerun-tasks` (JDK 21 JBR) | **BUILD SUCCESSFUL**; XML sin failures/errors: SmokeTest 1/0/0, AppConfigTest 6/0/0, HealthTest 2/0/0, SumarioParsingTest 3/0/0, BoeSumarioClientTest 5/0/0, BoeSumarioLiveTest 1/0/0 (**18 tests**) |
| Gate build | `./gradlew build --no-daemon` | **BUILD SUCCESSFUL**, **197 tareas** |
| Gate test | `./gradlew test` | **BUILD SUCCESSFUL** (`:shared` 11, `:backend` 18, `:composeApp` smokes 0 fallos) |
| Gate harness | `env -u JAVA_HOME .harness/init.sh` | **exit 0** («Gate OK…») |
| Flyway fuera del gate | `./gradlew build --dry-run \| grep -i flyway` | vacío (esperado) |
| sin red en el gate | grep de `boeSumarioHttpClient`/`CIO`/`HttpClient(` en `backend/src/test` | solo `BoeSumarioLiveTest` (guardado por `BOE_LIVE_TEST`) usa la factory real; el resto usa `MockEngine`/decodifica strings |
| API real | `curl -H 'Accept: application/json' …/boe/sumario/{20261009,20240102}` | **HTTP 200** (344715 B / 193855 B); `20261011` (domingo) → **404 XML**; fecha mal formada → **400** |
| Fixtures reales | `shasum -a 256` + `cmp` vs API en vivo | **byte-idénticos**: `20261009` `da22a076…215a1f`, `20240102` `547a8666…c64fefe` |
| Recuento por sección | script sobre la respuesta viva | 20261009: corpus **205** = I 5 / II.A 16 / II.B 31 / III 69 / V.B 84; **V.A 32 fuera**; `BOE-B-2026-32742` ausente. 20240102: corpus **64** = II.A 6 / II.B 24 / III 18 / V.B 16; IV 24 / V.A 51 / V.C 4 fuera |
| Escenario 6 (opt-in) | `BOE_LIVE_TEST=1 ./gradlew :backend:test --tests '*BoeSumarioLiveTest'` | Sin truststore: FAILED por `SunCertPathBuilderException` (JBR sin raíz FNMT-RCM; **entorno, no código**). Con truststore temporal: **BUILD SUCCESSFUL** |
| LiveTest sin env | `./gradlew :backend:test` | XML `1/0/0` **sin abrir sockets** (salta por guard) → gate sin red |

## Escenarios del spec

1. ✔ Fixture real: entradas de I/II.A/II.B/III/V.B con identificador, control, título, fecha, organismo, epígrafe y URLs; sin IV/V.A.
2. ✔ `item` objeto y array (20261009: 37 obj/25 arr; 20240102: 25 obj/17 arr) y `departamento` objeto, con test de equivalencia.
3. ✔ `404` (día sin publicación) → lista vacía.
4. ✔ Petición `GET https://www.boe.es/datosabiertos/api/boe/sumario/20261009` con `Accept: application/json`.
5. ✔ `500` e `IOException` → `BoeSumarioException` con fecha y causa.
6. ✔ Llamada real (curl y test opt-in).

## Alcance, arquitectura y seguridad

- **Alcance acotado** (`git status`/grep): `Application.kt`, plugins/infra, migraciones Flyway, `:shared`, `:composeApp`, `settings.gradle.kts`/raíz del build y CI **intactos**. Sin endpoint, BD, job, clasificación ni descarga de texto completo. **Sin wiring en el arranque** (el startup no hace llamadas externas).
- **Arquitectura**: paquete feature-first `ingesta/sumario/`; dominio interno `EntradaSumario` sin Ktor/HTTP ni serialización; DTOs de wire `@Serializable` con sufijo `Dto`; cliente por interfaz con `HttpClient` inyectado + factory CIO (`expectSuccess=false`, `ContentNegotiation` con `DatoPublicoJson`); `CancellationException` re-lanzada. Cumple las convenciones de nombres y la skill `ktor-backend-architecture`.
- **Seguridad**: sin hallazgos. API pública de solo lectura, sin credenciales ni datos personales. URL construida solo desde una constante + `LocalDate.format(BASIC_ISO_DATE)` (sin entrada de usuario → sin SSRF/inyección). Fallo de red/estado inesperado → excepción tipada sin fuga de internals. Dependencias `ktor-client-cio`/`ktor-client-mock` justificadas (mismo `version.ref`).

## Documentación/harness

- `ARCHITECTURE.md` (`ingesta/sumario/` + frontera **Backend → BOE** de solo lectura), `CONSTRAINTS.md` (MUST: gate sin llamadas de red; pruebas externas opt-in fuera de gate/CI) y `docs/desarrollo-local.md` (cliente + check opt-in + nota del truststore) actualizados y coherentes.
- `AGENTS.md` sin tocar (correcto); `init.sh` sin cambios (exit 0). `feature_list.json`/`PROGRESS.md`/`feature-ids.md` con evidencia real y recuentos reproducidos.

## Hallazgos (todos Low, no bloquean)

1. `BoeSumarioLiveTest` se reporta como «passed» en el XML del gate (no «skipped») porque usa `return@runTest`: no abre sockets (cumple el MUST), pero la evidencia de cobertura efectiva es ligeramente engañosa.
2. `boeSumarioHttpClient()` no define `HttpTimeout` explícito: acotar el timeout es prudente (reintentos/backoff → FT00009).
3. La envoltura `departamento.texto.item` no se modela (hoy solo aparece en IV/V.C, excluidas): riesgo defensivo si el BOE la introdujera en una sección del corpus.
4. Campos faltantes → cadena vacía (`identificador.orEmpty()`, `urlOficial.orEmpty()`) sin filtrar entradas incompletas; aceptable para esta feature.
5. Cosméticos de evidencia: la entrada de `20240102` en `feature_list.json` cita IV/V.A pero no V.C (también descartada). Cabecera del spec actualizada a `accepted` al persistir.

## No reproducido aquí

- El escenario 6 en JVM requiere el truststore FNMT (limitación de `cacerts` del JBR); se verificó tanto con truststore temporal como con `curl` (llavero del sistema). No afecta al gate.

## Revalidación de la reparación (retorno único) — 2026-10-10

- Veredicto: **`accept`** (segunda pasada, `feature-validator` independiente).
- Motivo: MUST durable nuevo «una sola salida por función; prohibido el *early
  return* (incluidos `return@…`); aplica también a los tests» (`CONSTRAINTS.md`
  §«Estilo de código»).
- Comprobado por el validador:
  - MUST presente y claro en `CONSTRAINTS.md`.
  - Refactor **sin cambio de comportamiento** en
    `SingleOrArraySerializer.deserialize`, `BoeSeccionDto.entradas`,
    `AppConfig.parsePort` (preexistente de FT00004) y `BoeSumarioLiveTest` (guarda
    `if`/`else`, sin `return@runTest`); mismos casos, mensajes y aserciones.
  - Solo quedan **5 salidas únicas** y **0 `return@`** en
    `backend/src`/`shared/src`/`composeApp/src`.
  - `./gradlew :backend:test --rerun-tasks` → 18 tests, 0 fallos; gate
    (`build --no-daemon` 197 tareas, `test` 3 módulos, `init.sh` exit 0).
  - Alcance: solo 4 ficheros de producto + docs del harness; sin tocar
    `Application.kt`/Flyway/`:shared`/`:composeApp`/raíz/CI.
- Producto: commit `87af9dc refactor(FT00006): una sola salida por funcion`;
  PR #6; CI en verde run `38040596946` (head `87af9dc`).

## Aclaración de la convención de nombres — 2026-10-10

Tras la duda «¿por qué `EntradaSumario` no tiene sufijo?» (decisión del owner):

- `Dto` = **todo** tipo `@Serializable`/de transporte (contrato de `:shared` **y**
  DTOs de `:backend`, p. ej. `HealthDto`, `BoeSumarioResponseDto`).
- `Entity`/`Row`/`Ui` = roles de capas internas (persistencia, fila de BD, UI).
- **Sin sufijo** = modelos de **dominio/valor internos** que no son ninguno de los
  anteriores ni serializables → `EntradaSumario` es correcto tal cual.
- Documentado en `CONSTRAINTS.md` §«Nombres y contratos» y `ARCHITECTURE.md`
  §«Convenciones de nombres». Sin cambios de código.

## Revalidación del cambio de alcance y `@SerialName` — 2026-10-10

- Veredicto: **`accept`** (revalidación independiente, `feature-validator`), tras una primera pasada `revise` (integridad de árbol/evidencia) reparada.
- **Alcance nuevo**: la 1.0.0 cubre **todo el sumario del BOE** — secciones I, II.A, II.B, III, IV, V.A, V.B y V.C (códigos `1`, `2A`, `2B`, `3`, `4`, `5A`, `5B`, `5C`); **ninguna sección se excluye** y se usan **todos los campos** (incluida `urlPdf`).
- **`@SerialName` explícito** en **toda** propiedad de los DTOs `@Serializable` de `:shared` (`PublicacionDto` 10, `ResumenDto` 6, `PlazoDto` 2, `ResumenDiarioDto` 2) y de `:backend` (`SumarioWireDto` 36, `HealthDto` 1); 0 propiedades y 0 valores de enum sin `@SerialName`. `SeccionBoeDto` pasa a **8** valores. JSON de wire invariante.

### Checks reejecutados (evidencia real)

| Check | Resultado |
| --- | --- |
| `:shared:jvmTest --rerun-tasks` | BUILD SUCCESSFUL — SmokeTest 1, CategoriaWireTest 3, SerializationTest 7 (**11 tests**) |
| `:backend:test --rerun-tasks` | BUILD SUCCESSFUL — SmokeTest 1, AppConfigTest 6, HealthTest 2, **SumarioParsingTest 5**, BoeSumarioClientTest 5, BoeSumarioLiveTest 1 (**20 tests, 0 fallos**) |
| Recuentos por sección | `20261009` → **237** (I 5/II.A 16/II.B 31/III 69/**V.A 32**/V.B 84); `20240102` → **143** (II.A 6/II.B 24/III 18/**IV 24**/**V.A 51**/V.B 16/**V.C 4**) |
| `departamento.texto.item` (IV/V.C) | Modelado (`BoeTextoDto`); `BOE-B-2024-1` (IV) y `BOE-B-2024-92` (V.C) extraídos correctamente |
| Unión de las 8 secciones | Nuevo test `la union de las secciones de ambos fixtures cubre las ocho del BOE` (`SeccionBoeDto.entries`) |
| Gate | `./gradlew build --no-daemon` (**201 tareas**, con detekt/CPD de Session 033), `./gradlew test` (3 módulos), `env -u JAVA_HOME .harness/init.sh` **exit 0** |
| API real (`curl` 20240102) | HTTP 200; incluye IV 24/V.A 51/V.C 4 (total 143) |
| Retorno único | 5 salidas únicas; 0 `return@` |

### Alcance / integridad de árbol

- La feature **sí** toca `:shared` (8 secciones + `@SerialName`). El **árbol de trabajo** convive con el workstream de tooling **Session 033** (detekt/CPD, `settings.gradle.kts`, `libs.versions.toml`, `opencode.json`, `config/`), **ajeno** a FT00002/FT00006 y que el orquestador commitea por separado.
- Pendiente de cierre (no bloqueante, ajeno a la funcionalidad): refrescar/registrar en `PROGRESS.md` (fichero compartido con Session 033) y marcar como históricas las líneas de evidencia superadas en `feature_list.json`.

### Seguridad

Sin hallazgos: API pública de solo lectura, sin credenciales ni datos personales de usuarios; URL construida solo desde constante + `LocalDate.format(BASIC_ISO_DATE)`; errores tipados; sin red en el gate (test opt-in guardado por `BOE_LIVE_TEST`).
