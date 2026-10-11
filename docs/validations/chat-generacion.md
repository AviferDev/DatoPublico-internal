# Validación — `chat-generacion` (FT00025)

- Veredicto: **`accept`**
- Fecha: 2026-10-11
- Rol: `validator` (independiente, solo lectura; no implementa ni corrige)
- Spec: `.harness/docs/specs/chat-generacion.md`
- Rama: `feat/ft00025-chat-generacion` (claim `63daeb1 chore(FT00025): claim`
  sobre `origin/main` `f8ff126`; cambios de la feature **sin commitear** en el
  árbol de trabajo)
- Estado en `feature_list.json`: `passing` (persistido a `accepted` por el
  orquestador).

## Checks reejecutados (JAVA_HOME = JBR 21, desde `..`)

| Comando | Resultado |
| --- | --- |
| `./gradlew :backend:test --rerun-tasks` | BUILD SUCCESSFUL; **385** tests, 0 fallos, 0 errores, 0 omitidos (+29 nuevos; los 356 de FT00024 intactos). |
| `./gradlew build --no-daemon -PskipClient` | BUILD SUCCESSFUL (23 tareas). |
| `./gradlew test` | BUILD SUCCESSFUL (63 tareas, 3 módulos). |
| `./gradlew detekt` + `:cpdCheck` (forzados con `--rerun-tasks`) | BUILD SUCCESSFUL; sin duplicación nueva. |
| `env -u JAVA_HOME .harness/init.sh` | **exit 0** («Gate OK»). |
| Offline | `RagChatServiceLiveTest` (y demás live) **omitido** sin `OPENCODE_LIVE_TEST=1`; sin abrir sockets. |
| Fail-fast sin clave | `OPENCODE_LIVE_TEST=1` sin `OPENCODE_API_KEY` → `TextGenerationException` en `RagChatServiceLiveTest.kt:49` (antes de crear el cliente HTTP). Estado verde restaurado después (XML final 385/0). |

Recuento real de tests nuevos (+29 = 385−356): `ChatPromptBuilderTest` 4,
`ChatOutputParserTest` 8, `ChatGroundingCheckerTest` 5, `RagChatServiceTest` 11,
`RagChatServiceLiveTest` 1 (opt-in).

## Escenarios del spec

1–3 (gate): `RagChatServiceTest` con dobles — `Answered`/`Refuted` con cita
(URL inyectada = `officialUrl`) y `Unfounded` con la respuesta del modelo.
4 (gate): contexto vacío ⇒ `Unfounded` **sin invocar** al proveedor
(`provider.calls == 0`); `RagChatService.kt:70-71`. Verificado.
5 (gate): el doble recibe un `GenerationRequest` con la consulta y el contexto
numerado `[0]`/`[1]`; el servicio no conoce OpenCode/Ktor/HTTP. Verificado.
6 (gate): grounding léxico **degrada** a `Unfounded` con `UNFOUNDED_MESSAGE`
(`RagChatService.kt:102-111`); no publica la afirmación fuera del corpus.
Verificado.
7 (gate): citas vacías / publicación no resoluble ⇒ `Unfounded`; índice fuera de
rango y estado desconocido ⇒ `ChatGenerationException`. Verificado.
8 (gate sin red/BD/modelo/OpenCode): todos los comandos del gate en verde;
offline confirmado. Verificado.
9 (opt-in real con OpenCode): **no ejecutado** — no hay `OPENCODE_API_KEY` (no se
inventó); fail-fast sin clave confirmado. Deuda documentada, coherente con
FT00024.

## Hallazgos

Ninguno High/Medium. Deuda **Low** no bloqueante:

- **Duplicación con `SummaryGroundingChecker`**: `ChatGroundingChecker.kt`
  reproduce casi literalmente `isSupported`/`supportRatio` y los helpers de
  `SummaryGroundingChecker.kt:76-122`; `:cpdCheck` no lo señala (bajo el umbral de
  100 tokens). El spec/ADR 0020 lo anticipan como refactor aditivo opcional.
- **Live test como soft-skip**: `RagChatServiceLiveTest` «pasa» sin la env var
  (patrón idéntico a los demás live del repo).
- **Escenario 9 sin ejecutar** por falta de `OPENCODE_API_KEY`.
- **No-inyección del prompt**: `ChatPromptBuilderTest` verifica la instrucción
  delimitadora, no un fragmento adversarial; la defensa real es el grounding +
  «datos, no instrucciones».

## Seguridad

Sin hallazgos. Sin secretos en el diff (clave solo por entorno, fail-fast, nunca
versionada); sin llamadas de red en el gate; el contexto remoto se trata como **no
confiable** (delimitado como datos, no instrucciones) y el grounding degrada lo no
sustentado; la **URL oficial la inyecta** `CitationResolver` (el modelo solo aporta
índices, nunca URLs); sin SQL/ORM/BD/PII nuevos.

## Alcance, arquitectura y estilo

- Alcance verificado por `git status`: solo directorios nuevos
  `rag/chat/` (main 7 + test 5) y `docs/desarrollo-local.md` (mod). **Intactos**:
  `Application.kt`, `ingesta/`, `persistence/`, `rag/{retrieval,generation,
  guardrails,summary,review,evaluation}/`, migraciones, `:shared`, `:composeApp`,
  CI e `init.sh`; sin dependencias Gradle nuevas ni migración.
- `TextGenerationProvider`/`OpenCode*`/`SummaryTextNormalizer`/
  `SummaryGroundingChecker`/`HybridSearch`/`SearchFilter` **no modificados**; se
  reutilizan `MIN_CLAIM_SUPPORT` (0.6) y `SummaryTextNormalizer`.
- Dirección de dependencias correcta (`rag/chat/` → retrieval/generation/
  guardrails/persistence/ingesta); `CitationResolver` es `fun interface`; sin
  wiring.
- Estilo MUST: `return` único, sin `else if` (solo `when`), funciones ≤40 líneas,
  `@SerialName` explícito en `ChatOutputDto`, sufijo `Dto` solo en el DTO de
  transporte, KDoc en castellano / identificadores en inglés.

## Documentación y harness

- `ARCHITECTURE.md` (`rag/chat/` + frontera OpenCode + ADR 0020), `CONSTRAINTS.md`
  §«Chat RAG», ADR `docs/adr/0020-chat-rag-citas-inyectadas-grounding.md` +
  índice, skill `rag-datapublico` §5/§7 y `docs/desarrollo-local.md` actualizados
  y coherentes con el código.
- `feature_list.json` FT00025 `passing` con evidencia; `docs/feature-ids.md` línea
  43 `passing`; `PROGRESS.md` Session 066. JSON válido.
- **Pendiente del orquestador**: persistir `accepted` en `feature_list.json` y
  `docs/feature-ids.md`; commit/push/PR.

## Veracidad de la evidencia del implementer

**Veraz.** Reproducidos todos los números: 385/0 tests, +29 nuevos, 356 previos
intactos, `build -PskipClient` 23 tareas, `test` 63 tareas, `detekt`+`:cpdCheck`
verdes, `init.sh` exit 0, live omitido sin sockets, fail-fast sin clave, alcance
acotado y docs durables. Sin discrepancias.
