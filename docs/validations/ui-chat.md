# Validación — `ui-chat` (FT00037)

- **Fecha:** 2026-10-14
- **Rol:** `feature-validator` (validación independiente; `revise` → reparación → `accept`; vía agente `general` en el worktree)
- **Spec:** `docs/specs/ui-chat.md`
- **Rama:** `feat/ft00037-ui-chat` (rebasada sobre `origin/main` = `c5f8ca1`; HEAD `3fb60a3`)
- **Diff:** 30 ficheros
- **Veredicto final:** **`accept`**

## Gate reejecutado (real)

| Comando | Resultado |
| --- | --- |
| `:composeApp:jvmTest` | **78 tests, 0 fallos** (24 de chat, con `MockEngine`) |
| `:composeApp:assembleDebug` | OK |
| `:composeApp:wasmJsBrowserDistribution` | OK |
| `:composeApp:linkDebugFrameworkIosSimulatorArm64` | OK |
| `test` / `build -PskipClient` | OK |
| `detekt` + `:cpdCheck` | OK |

## Comprobaciones

- Estados idle/carga/respondida/refutada/sin fundamento/error+reintento.
- `sin_fundamento` como estado (no error, citas vacías); `respondida`/`refutada`
  con ≥1 cita y aviso de IA.
- `AskChatQuestion` (`MAX_QUERY_LENGTH=1000`, blanco no llama).
- `HttpChatRepository`/`ChatApi` sobre `core/network` (`POST /v1/chat`), inyectado
  en `App()`; repositorio en memoria para previews/tests.
- Navegación aditiva (`AppRoutes.CHAT`, destino `chat`, entrada desde el feed);
  encabezado del feed visible en **todos** los estados.
- `@Preview` en toda función `@Composable`; i18n; Material Icons; colores del tema;
  estilo MUST; sin tocar `:shared`/`:backend`/CI/`init.sh`.

## Hallazgos

- **MUST (cerrado):** `ChatStatusLabel` sin `@Preview` → añadida.
- **Medium (cerrado):** entrada al chat solo desde el estado `Content` del feed →
  encabezado movido fuera de la rama de estado.
- **Low (parcial declarado):** capturas `refutada`/`error` no incluidas por el
  límite de 30 ficheros (verificadas en vivo; `sin_fundamento` sí incluida).
- **Low (resuelto por el orquestador):** docs durables del harness (ADR 0032 + docs).
- **Low (declarado):** HTTP real (ajuste del orquestador); DTOs+mapeo en un fichero;
  `ChatUiState.kt` fusionado en `ChatViewModel.kt`.

Sin hallazgos High. Sin hallazgos de seguridad.
