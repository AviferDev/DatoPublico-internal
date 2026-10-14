# Feature Implementation Spec: UI de chat RAG

## Source Feature

- `id`: ui-chat
- `ft_id`: FT00037 (registrado en `docs/feature-ids.md`)
- `parts`: none (atómica; ≈26 ficheros de producto, por debajo del límite de 30;
  ver *Risks* para el plan de división si el recuento se acerca a 30)
- `area`: cliente-cmp
- `depends_on`: api-chat (FT00031, **`accepted`** y en `origin/main`) +
  ui-navegacion-estado (FT00034, **en validación** al planificar; su spec es
  `docs/specs/ui-navegacion-estado.md`)
- `status`: not_started (al planificar)
- `source`: `feature_list.json` (`notes`: `docs/roadmap.md` 0.6-T08, `DESIGN.md`);
  `docs/roadmap.md` §0.6.0 (`0.6-T08`)
- `claim`: rama `feat/ft00037-ui-chat` reclamada en `origin`
  (`3026963 chore(FT00033): claim ui-chat`, base `082245b` = `feat(FT00033):
  complete ui-detalle`); sin PR abierto hacia `main`. El claim fue explícito
  (el usuario nombró `ui-chat`); no hay otro trabajo en la rama.

> **Última pantalla del MVP de UI compartida.** Reutiliza la base de FT00032
> (tema `DatoPublicoTheme`, `design/components/`, i18n por recursos) y FT00033
> (`AiNotice`, `OfficialSourceLink`, capas `feature/<nombre>/{domain,data,ui}`) y
> monta sobre el **patrón de estado y navegación de FT00034** (ViewModel con
> `StateFlow`, `AppNavHost`/`AppRoutes`, `collectAsStateWithLifecycle`, DI manual).
> Consume el **contrato de chat** de FT00031 (`ChatResponseDto`/`ChatStatusDto`/
> `ChatCitationDto`, `POST /v1/chat`) y entrega la **pantalla de chat RAG**:
> pregunta o afirmación, respuesta con **citas a la fuente oficial** y los estados
> **carga/error/sin fundamento/refutada**. Deriva de `feature_list.json`,
> `docs/roadmap.md` 0.6-T08, `DESIGN.md` (§Layout/§Components/§Core Screens 4–5),
> `CONTEXT.md` (§Consulta / chat RAG) y `docs/domain-model.md` (§Consulta), **sin
> inventar**.

## Goal

Construir en `commonMain` de `:composeApp` la **pantalla de chat RAG** con la
dirección visual de `DESIGN.md`: un campo para **preguntar** o pegar una
**afirmación a verificar**, y una **respuesta fundamentada** que muestra el
**estado** del dominio (`respondida`, `refutada`, `sin_fundamento`), el **texto**
y la **lista de citas a la fuente oficial** (cada una enlaza al BOE), con los
estados **carga / error** y reintento, más el **aviso de IA** siempre visible.

La feature introduce la **tercera capa de feature** (`feature/chat/{domain,data,ui}`)
con sus modelos de dominio del cliente, un caso de uso (`AskChatQuestion`), un
repositorio **en memoria** de ejemplo (el cliente HTTP real es FT00035), el
**`ChatViewModel`** con `StateFlow` (patrón FT00034) y la **ruta `chat`** en el
grafo de navegación, más el **punto de entrada** desde el feed. **No** se
reimplementa la navegación/estado (FT00034) ni el HTTP (FT00035).

## Non-Goals

- **Cliente HTTP y `:shared`**: `ktor-client`, la URL base, la cache, los DTOs de
  wire del cliente y el mapeo `ChatResponseDto → modelos del cliente` son FT00035
  (`core/network`, `docs/specs/ui-cliente-http-cache.md`) y **no** están en
  `depends_on`. Esta feature usa un repositorio **en memoria** (ver *Risks*: gap de
  wiring). No se cablea `:shared`.
- **Reimplementar navegación/estado** (FT00034): no se crea otro grafo ni otro
  patrón de estado; se **extiende** `AppRoutes`/`AppNavHost` con la ruta `chat` y
  se sigue el patrón `XViewModel` + `StateFlow` + composables stateless.
- **Detalle real** (FT00033) y **búsqueda** (FT00036): no se tocan.
- **Historial de la conversación** (multi-turno, local o en servidor): fuera de
  alcance. `CONTEXT.md` fija «sin historial en el servidor» y
  `docs/risks-and-open-questions.md` deja abierto si el historial es local o
  efímero. Aquí hay **un solo intercambio** (pregunta + respuesta) efímero.
- **Asesoramiento jurídico**: no se detecta ni se responde a peticiones de
  asesoramiento (disclaimer en `docs/domain-model.md` §Edge Cases es de producto,
  no de esta feature); el guardrail real vive en el backend (FT00025).
- **Filtros de la consulta** (categoría/fecha/sección): la recuperación usa los
  valores por defecto del backend (FT00031); los filtros son de FT00036.
- **Streaming/tokens incrementales**, **voz**, **compartir respuesta**: fuera de
  alcance del MVP.
- **Framework de DI**: se mantiene **DI manual** (skill CMP); no se introduce
  Koin/Hilt.
- **Accesibilidad/i18n formal multi-idioma** (FT00043), **empaquetado/firma**
  (FT00038–FT00040).
- **No** se cambia `:shared`, ni `:backend`, ni migraciones, ni `init.sh`, ni CI,
  ni `DESIGN.md`, ni las reglas del gate.

## Job Story

When quiero saber qué dice el BOE sobre algo, o comprobar si una afirmación que he
leído es cierta,
I want escribir mi pregunta o pegar la afirmación y ver una respuesta clara con las
**fuentes oficiales** que la sustentan (o que me diga que no hay fundamento),
so I can informarme con trazabilidad al BOE y sin que se me sirva una afirmación
inventada.

## Users And Permissions

- **Ciudadanía (usuario final):** anónima, solo lectura; sin cuentas, sin datos
  personales, sin analítica. La consulta **no** se persiste (ni en el dispositivo
  ni en el servidor); el historial es efímero.
- **Desarrollador (único actor técnico):** ejecuta los gates y sirve la app
  (Android/Web) para verificar y capturar.
- Sin autenticación ni autorización (el endpoint es público).

## Acceptance Scenarios

### Scenario 1: abrir el chat desde el feed

Given la app en el feed (FT00032/FT00034) con su encabezado,
When pulso la acción de **chat** del encabezado,
Then navego a la ruta `chat` y veo la pantalla de chat en su estado inicial
(invitación a preguntar); el botón de **atrás** vuelve al feed y su estado se
conserva (sin recargar).

### Scenario 2: pregunta respondida con citas

Given el repositorio de ejemplo y una pregunta sobre una publicación conocida,
When escribo la pregunta y pulso enviar,
Then paso por el estado **carga** (indicador + la pregunta enviada) y llego al
estado con **respuesta**: el texto de la respuesta, la etiqueta de estado
`respondida`, **≥1 cita** con su título y enlace a la fuente oficial, y el **aviso
de IA** visible; pulsar una cita abre la URL oficial (nunca lanza *crash*).

### Scenario 3: afirmación refutada

Given el repositorio de ejemplo y una afirmación que el corpus contradice,
When la envío,
Then la respuesta se marca claramente como **`refutada`** (icono + texto, no solo
color) y muestra **≥1 cita** a la fuente oficial.

### Scenario 4: consulta sin fundamento (no es error)

Given el repositorio de ejemplo y una consulta que el corpus no cubre,
When la envío,
Then la respuesta se marca como **`sin_fundamento`** con un mensaje que explica que
el BOE no permite confirmarla ni refutarla, **sin** citas y **sin** tratarse como
error (no hay icono de error ni botón de reintento obligatorio).

### Scenario 5: error y reintento

Given un repositorio que devuelve **fallo** (resultado tipado, sin excepción),
When envío la consulta,
Then aparece el estado de **error** con la pregunta enviada, icono, mensaje y botón
«Reintentar»; pulsar «Reintentar» reenvía la **misma** pregunta y, si el
repositorio ya responde, pasa a respuesta. La app **nunca** se cierra.

### Scenario 6: entrada inválida no rompe

Given el campo de entrada,
When está vacío (solo espacios) o supera el máximo de la API,
Then el botón de enviar queda **deshabilitado** y no se lanza ninguna petición; no
se provoca ningún *crash*.

### Scenario 7: ViewModel + `StateFlow`, UI stateless

Given la pantalla de chat,
When se inspecciona su estado,
Then lo expone un **`ChatViewModel`** (androidx.lifecycle multiplataforma) como
`StateFlow<ChatUiState>` con UDF (estado inmutable que la UI solo lee), la UI lo
recolecta con `collectAsStateWithLifecycle()`, los eventos son métodos del
ViewModel (`onQueryChange`/`onSubmit`/`onRetry`) y los composables son
**stateless**. La carga pasa siempre por el caso de uso `AskChatQuestion`.

### Scenario 8: i18n, previews, Material Icons y colores del tema

Given el código nuevo de UI,
When se revisan los composables,
Then **cada** función `@Composable` (pantalla, campo, respuesta, citas, estados y
la ruta) tiene su `@Preview` dentro del tema; **ningún** texto visible está
hardcodeado (solo literales en `@Preview`); los iconos con significado usan
`Icons.AutoMirrored.Outlined.*`/`Icons.Outlined.*` con `contentDescription`; y los
colores salen **solo** de `MaterialTheme.colorScheme.*`.

### Scenario 9: tres plataformas y gate verde

Given la UI en `commonMain`,
When compilo Android (`:composeApp:assembleDebug`), Web
(`:composeApp:wasmJsBrowserDistribution`) e iOS
(`:composeApp:linkDebugFrameworkIosSimulatorArm64`, host macOS), y ejecuto
`./gradlew build -PskipClient`, `./gradlew test`, `./gradlew detekt` (+
`:cpdCheck`) y `.harness/init.sh`,
Then las tres compilan con el **mismo** grafo (con la ruta `chat`), el atrás del
sistema/navegador vuelve al feed y el gate SDK-free sigue verde (`init.sh` **no**
se modifica).

### Scenario 10: capturas antes/después

Given un cambio de interfaz,
When se abre el PR,
Then la rama incluye capturas en `docs/pr/ft00037-ui-chat/` (al menos: feed base
**antes**, y **después** los estados respondida, refutada, sin fundamento y error),
enlazadas con URL absoluta a la rama (`docs/pr/README.md`).

## Repository Research

### Files Inspected

> La planificación se hizo sobre `origin/main` = `082245b` (`feat(FT00033): complete
> ui-detalle`) para `:composeApp`/`:shared`. El worktree de FT00034
> (`/Users/aviferdev/Documents/Git/DatoPublico-wt/ft00034`) **no era accesible**
> desde el sandbox de planificación (restricción `external_directory`); su contrato
> se tomó de `docs/specs/ui-navegacion-estado.md` (spec ya escrito). No se modificó
> nada.

- `shared/src/commonMain/kotlin/…/model/{ChatRequestDto,ChatResponseDto,
  ChatStatusDto,ChatCitationDto}.kt` — contrato de transporte de FT00031
  (`consulta`/`estado`/`respuesta`/`citas`; estados `respondida`/`refutada`/
  `sin_fundamento`; cita con `publicacionId`/`titulo`/`urlOficial`). Es lo que la UI
  **representa**; el cliente lo replica como capa anti-corrupción en FT00035.
- `composeApp/src/commonMain/kotlin/…/feature/detail/{domain,data,ui}/*` — patrón
  de feature a imitar: modelos de dominio propios, `*LoadResult` **tipado**
  (`Success`/`Failure`), puerto + `InMemory*Repository(mode, latencyMillis)`,
  `*UiState` (sealed), `*Route` (efectos) + `*Screen` (stateless) con estados y
  `@Preview`.
- `composeApp/src/commonMain/kotlin/…/design/components/{AiNotice,OfficialSourceLink,
  SectionBlock}.kt` — `AiNotice` (aviso de IA; KDoc dice «lo reutilizará el chat»),
  `OfficialSourceLink` (enlace oficial con guarda `http(s)://` antes de
  `LocalUriHandler`, sin *crash*) y su helper privado `isHttpUrl`.
- `composeApp/src/commonMain/kotlin/…/design/theme/DatoPublicoTheme.kt` — única
  entrada de tema (tokens de `DESIGN.md`); **no** se redefine.
- `composeApp/src/commonMain/composeResources/values/strings.xml` — 47 claves i18n
  (castellano) del feed y el detalle; hay que añadir las del chat.
- `composeApp/src/commonMain/kotlin/…/feature/feed/ui/{FeedScreen,FeedRoute}.kt` —
  encabezado del feed (título `app_title`) y contrato de la ruta; punto de entrada
  del chat y lugar donde FT00034 propaga `onPublicationClick`.
- `composeApp/src/commonMain/kotlin/…/feature/feed/ui/{FeedUiState,FeedStateHolder}.kt`
  y `…/feature/detail/ui/{DetailUiState,DetailStateHolder}.kt` — patrón de estados
  local; **FT00034** los sustituye por `FeedViewModel`/`DetailViewModel` con
  `StateFlow` (base de la que parte el chat).
- `composeApp/src/commonMain/kotlin/…/app/App.kt` — composition root manual actual;
  FT00034 lo cambia a `DatoPublicoTheme { AppNavHost(feedViewModelFactory, …) }`.
- `composeApp/build.gradle.kts` — `commonMain` con Compose (runtime/foundation/
  material3/ui/tooling-preview/resources); `commonTest` con `kotlin("test")` +
  `kotlinx-coroutines-test`. **No** hay `material-icons-extended` (solo
  `material-icons-core`): los iconos disponibles son el set reducido (incluye
  `Icons.AutoMirrored.Outlined.Send`; **no** `Chat`/`Forum`).
- `gradle/libs.versions.toml` — Kotlin `2.1.20`, CMP `1.7.3`, coroutines `1.10.1`;
  **no** hay lifecycle/navigation todavía (los añade FT00034).
- `composeApp/src/commonTest/kotlin/…/feature/feed/FeedStateHolderTest.kt` — patrón
  de test de estado con `runTest` y repositorios dobles (FT00034 lo migra a
  `FeedViewModelTest` con `Dispatchers.setMain`).
- `.harness/{DESIGN.md,CONTEXT.md,ARCHITECTURE.md §`:composeApp`,CONSTRAINTS.md
  §«Cliente»,§«Chat RAG»,§«Producto y datos»,§«Estilo»,docs/domain-model.md
  §Consulta,docs/roadmap.md §0.6.0,docs/risks-and-open-questions.md,docs/pr/README.md}`,
  `docs/adr/{0020,0024,0027,0028}.md` y los specs `ui-feed.md`, `ui-detalle.md`,
  `ui-navegacion-estado.md`, `ui-cliente-http-cache.md` y `api-chat.md`.
- Skills `.agents/skills/{compose-multiplatform-architecture,rag-datapublico}` —
  capas UI→Dominio→Datos, `XViewModel` + `StateFlow`, composables stateless, DI
  manual, navegación feed/detalle/búsqueda/chat; chat = responder con citas y
  distinguir `respondida`/`refutada`/`sin_fundamento`.

### Existing Patterns To Follow

- **UI única en `commonMain`**, entrypoints mínimos por plataforma; **DI manual**
  por constructor/factory.
- **UDF**: estado inmutable que la UI solo lee; eventos como métodos del ViewModel;
  composables **stateless**; `collectAsStateWithLifecycle()` (patrón FT00034).
- **Capas de feature** `feature/chat/{domain,data,ui}`; la UI no conoce red ni
  DTOs; todo pasa por un caso de uso (`AskChatQuestion`).
- **Resultados tipados, sin excepciones hacia la UI** (`ChatLoadResult`), un solo
  `return`, sin `else if`, funciones ≤40 líneas, KDoc en castellano, identificadores
  en inglés.
- **Estilo MUST de UI**: `@Preview` en toda función `@Composable`, textos por
  recursos, Material Icons con `contentDescription`, colores solo de
  `MaterialTheme.colorScheme`, sin *crashes* deliberados.
- **Tests de estado/dominio en `commonTest`** con `runTest`; **sin tests de vistas**;
  sin red ni BD.
- **Version catalog + Kotlin DSL**; no se añaden dependencias nuevas en esta
  feature (las de lifecycle/navigation las introduce FT00034).

### Current Gaps

- **FT00034 no está en `main`** (en validación): al implementar FT00037 hay que
  partir del merge de FT00034 (`AppRoutes`/`AppNavHost`/`FeedViewModel`); si aún no
  está, la feature queda **bloqueada**.
- **No existe `feature/chat/`** ni la ruta `chat` en el grafo.
- **No hay red** en `:composeApp`: el endpoint `POST /v1/chat` no se consume (el
  cliente HTTP es FT00035 y **no** es dependencia). La UI se apoya en un repositorio
  en memoria (mismo criterio que FT00033).
- **`material-icons-extended` no está**: no hay icono `Chat`/`Forum` en el set core;
  el punto de entrada usa **texto**, no un icono inexistente.
- El corpus/`/v1/chat` real puede devolver `sin_fundamento` hasta que el pipeline
  esté cableado (gap de planificación ya registrado, Sessions 068/070).

## Technical Approach

### 1. Dominio (`feature/chat/domain/`, nuevos)

- `ChatModels.kt`:
  - `enum class ChatStatus { ANSWERED, REFUTED, UNFOUNDED }` — espejo del enum de
    wire `ChatStatusDto` (tokens `respondida`/`refutada`/`sin_fundamento`); el
    texto visible se resuelve por recurso i18n, **no** por el nombre del enum.
  - `data class ChatCitation(val publicationId: String, val title: String, val
    officialUrl: String)` — espejo de `ChatCitationDto`.
  - `data class ChatAnswer(val status: ChatStatus, val text: String, val citations:
    List<ChatCitation>)` — `UNFOUNDED` ⇒ `citations` vacía; `ANSWERED`/`REFUTED`
    ⇒ ≥1 cita (invariante del contrato, FT00031/ADR 0020).
  - `sealed interface ChatLoadResult { data class Success(val answer: ChatAnswer);
    data object Failure }` — fallo **tipado**, nunca excepción.
- `AskChatQuestion.kt`: caso de uso `class AskChatQuestion(private val repository:
  ChatRepository) { suspend operator fun invoke(query: String): ChatLoadResult }`.
  Incluye `const val MAX_QUERY_LENGTH = 1000` en el `companion object` (espeja
  `ChatService.MAX_QUERY_LENGTH` de FT00031: evita un `400` por longitud) y una
  guarda de entrada **en blanco** que devuelve `Failure` **sin** llamar al
  repositorio (defensiva; la UI ya deshabilita el envío).

### 2. Datos (`feature/chat/data/`, nuevos)

- `ChatRepository.kt`: puerto `interface ChatRepository { suspend fun ask(query:
  String): ChatLoadResult }` (frontera que implementará FT00035 con `core/network`).
- `InMemoryChatRepository.kt`: implementación **en memoria** con datos de ejemplo,
  **placeholder** hasta FT00035 (mismo criterio que `InMemoryDetailRepository`).
  - `enum class InMemoryChatMode { SAMPLE, UNAVAILABLE }`.
  - `class InMemoryChatRepository(mode = SAMPLE, latencyMillis = 250L)`: en
    `SAMPLE` clasifica de forma **determinista** por el texto de la consulta
    (documentado en KDoc y cubierto por tests): una afirmación con marcadores de
    refutación (`"refut"`, `"falso"`, `"no es cierto"`, sin distinguir mayúsculas)
    ⇒ `REFUTED` con citas; una consulta con palabras del corpus de ejemplo
    (`"beca"`, `"empleo"`, `"norma"`, `"plazo"`) ⇒ `ANSWERED` con citas; cualquier
    otra ⇒ `UNFOUNDED` sin citas. En `UNAVAILABLE` ⇒ `Failure`. Datos de ejemplo
    deterministas (sin reloj ni aleatoriedad) para tests y `@Preview`.
  - La latencia simulada (`delay`) es la que hace observable el estado `Loading`.

### 3. Estado y UI (`feature/chat/ui/`, nuevos)

- `ChatUiState.kt`:
  ```kotlin
  data class ChatUiState(val query: String = "", val response: ChatResponseState = ChatResponseState.Idle)
  sealed interface ChatResponseState {
      data object Idle : ChatResponseState
      data class Loading(val question: String) : ChatResponseState
      data class Content(val question: String, val answer: ChatAnswer) : ChatResponseState
      data class Error(val question: String) : ChatResponseState
  }
  ```
  El campo de entrada vive en el **estado** (UDF: la UI solo lee); los estados
  `Loading`/`Content`/`Error` llevan la **pregunta enviada** para poder mostrarla y
  reintentar sin depender del campo (que se **limpia** al enviar).
- `ChatViewModel.kt`:
  - `class ChatViewModel(private val askChatQuestion: AskChatQuestion) : ViewModel()`.
  - `val uiState: StateFlow<ChatUiState>`: se implementa con un
    `MutableStateFlow<ChatUiState>(ChatUiState())` + `asStateFlow()`. **Desviación
    justificada** del ejemplo del skill (`stateIn`): el estado nace de **eventos del
    usuario**, no de un flujo frío que haya que compartir; `asStateFlow()` mantiene
    el contrato `StateFlow` y el UDF. Se documenta en el ADR.
  - Eventos: `onQueryChange(value)` (actualiza `query`), `onSubmit()` (ignora si
    `query.isBlank()` o `length > MAX_QUERY_LENGTH`; pasa a `Loading(question)`,
    limpia `query` y lanza en `viewModelScope` el caso de uso, mapeando
    `Success → Content(question, answer)` / `Failure → Error(question)`),
    `onRetry()` (reenvía la pregunta del estado actual si no es `Idle`).
  - `companion object { fun factory(repository: ChatRepository = InMemoryChatRepository()):
    ViewModelProvider.Factory }` con `viewModelFactory { initializer { ChatViewModel(
    AskChatQuestion(repository)) } }` (DI manual).
- `ChatRoute.kt`: `ChatRoute(onBack: () -> Unit, modifier: Modifier = Modifier,
  viewModel: ChatViewModel = viewModel(factory = ChatViewModel.factory()))`;
  recolecta `val state by viewModel.uiState.collectAsStateWithLifecycle()` y delega
  en `ChatScreen`. Es el **único** composable con el ViewModel.
- `ChatScreen.kt`: **stateless** `ChatScreen(state, onQueryChange, onSubmit, onRetry,
  onBack, modifier)`; cabecera con **atrás** (`Icons.AutoMirrored.Outlined.ArrowBack`
  + `cd_back` reutilizado) y título `chat_title`; debajo, `ChatQuestionField` y el
  contenido según `state.response` (`Idle` → invitación; `Loading` → pregunta +
  indicador; `Content` → pregunta + `ChatAnswerCard` + `ChatCitations` + `AiNotice`;
  `Error` → pregunta + error + reintento). `when` como expresión, sin `else if`,
  funciones ≤40 líneas.
- `ChatQuestionField.kt`: `OutlinedTextField` multilínea (`maxLines = 4`) con
  etiqueta/placeholder de recursos y `IconButton` de envío con
  `Icons.AutoMirrored.Outlined.Send` + `contentDescription` de recurso,
  **deshabilitado** si la consulta está en blanco o excede `MAX_QUERY_LENGTH`.
- `ChatAnswerCard.kt`: tarjeta de la respuesta con **etiqueta de estado** (icono +
  texto, **no** solo color): `ANSWERED` → tono neutro (`surface`/`primaryContainer`),
  `REFUTED` → tono de atención/error (`errorContainer`, `Icons.Outlined.Warning`),
  `UNFOUNDED` → `surfaceVariant` con `Icons.Outlined.Info` y el mensaje
  `chat_unfounded_message`. Texto de la respuesta y, si aplica, el aviso de IA.
- `ChatCitations.kt`: lista de citas; cada una `Surface(onClick = …)` con
  `Icons.AutoMirrored.Outlined.ExitToApp`, el **título** de la publicación y una
  etiqueta de fuente oficial; abre `officialUrl` con `LocalUriHandler` tras la
  guarda `http(s)://` (**reutiliza** el helper `isHttpUrl`, que se promueve a
  `internal` en `design/components/OfficialSourceLink.kt`). URL no navegable ⇒
  enlace deshabilitado, **sin** *crash*.

### 4. Navegación y punto de entrada (modificaciones, sobre FT00034)

- `app/AppRoutes.kt` (modify): añadir `const val CHAT = "chat"` (sin argumentos).
- `app/AppNavHost.kt` (modify): añadir el `composable(AppRoutes.CHAT)` →
  `ChatRoute(onBack = { navController.popBackStack() })`, construyendo la factoría
  del chat **dentro** del nav host (`ChatViewModel.factory()`), de modo que `App()`
  **no** cambia. El feed recibe `onOpenChat = { navController.navigate(AppRoutes.CHAT) }`.
- `feature/feed/ui/FeedRoute.kt` + `FeedScreen.kt` (modify): añadir
  `onOpenChat: () -> Unit` y, en el encabezado del feed, una acción de **texto**
  (`chat_entry`, p. ej. «Preguntar al BOE») alineada a la derecha del título.
  **Sin** icono nuevo: el set `material-icons-core` no tiene `Chat`/`Forum` y **no**
  se añade `material-icons-extended` (evita engordar Wasm/iOS; ver *Risks*).

### 5. `AiNotice` (modify, aditivo)

`design/components/AiNotice.kt` gana un parámetro opcional
`text: String = stringResource(Res.string.detail_ai_notice)`; el chat pasa
`chat_ai_notice` («Respuesta generada con inteligencia artificial a partir del BOE.
Comprueba siempre la fuente oficial.»). El detalle (FT00033) **no** cambia de
comportamiento (usa el valor por defecto). Si el compilador rechazara el valor por
defecto composable, alternativa: dos sobrecargas (una delega en la otra).

### 6. Restricciones de estilo a vigilar

- **Sin crash**: `Failure` modelado; consulta en blanco ignorada; URL no `http(s)`
  deshabilitada; sin `!!`/`throw`/`error`/`TODO` como control.
- **Previews**: cada `@Composable` (incluida `ChatRoute` con un ViewModel de
  preview/repositorio en memoria y cada estado) lleva su `@Preview` dentro del tema.
- **CPD/detekt**: los `@Preview` de los cuatro estados y la tarjeta de respuesta son
  candidatos a duplicación >100 tokens; factorizar el contenido y variar datos.
- **≤40 líneas/función**: si `ChatScreen` crece, extraer cada estado a una función
  privada (como en `FeedScreen`/`DetailScreen`).
- **`Icons.AutoMirrored.Outlined.Send`** está en `material-icons-core` (verificado en
  el artefacto de CMP `1.7.3`); si se usara una variante no disponible, fallback
  `Icons.Outlined.Send`.

## Expected File Changes

Rutas en el repo de producto (`..`); `es/aviferdev/datopublico` se abrevia `…`:

- `composeApp/src/commonMain/kotlin/…/feature/chat/domain/ChatModels.kt` — create;
  `ChatStatus`/`ChatCitation`/`ChatAnswer`/`ChatLoadResult`.
- `composeApp/src/commonMain/kotlin/…/feature/chat/domain/AskChatQuestion.kt` —
  create; caso de uso + `MAX_QUERY_LENGTH`.
- `composeApp/src/commonMain/kotlin/…/feature/chat/data/ChatRepository.kt` — create;
  puerto.
- `composeApp/src/commonMain/kotlin/…/feature/chat/data/InMemoryChatRepository.kt` —
  create; placeholder determinista + datos de ejemplo.
- `composeApp/src/commonMain/kotlin/…/feature/chat/ui/ChatUiState.kt` — create.
- `composeApp/src/commonMain/kotlin/…/feature/chat/ui/ChatViewModel.kt` — create;
  ViewModel + `StateFlow` + `factory()`.
- `composeApp/src/commonMain/kotlin/…/feature/chat/ui/ChatRoute.kt` — create.
- `composeApp/src/commonMain/kotlin/…/feature/chat/ui/ChatScreen.kt` — create;
  stateless + estados.
- `composeApp/src/commonMain/kotlin/…/feature/chat/ui/ChatQuestionField.kt` — create;
  entrada + envío.
- `composeApp/src/commonMain/kotlin/…/feature/chat/ui/ChatAnswerCard.kt` — create;
  estado + texto.
- `composeApp/src/commonMain/kotlin/…/feature/chat/ui/ChatCitations.kt` — create;
  citas con enlace oficial.
- `composeApp/src/commonMain/kotlin/…/app/AppRoutes.kt` — modify; ruta `chat`.
- `composeApp/src/commonMain/kotlin/…/app/AppNavHost.kt` — modify; destino `chat` +
  `onOpenChat`.
- `composeApp/src/commonMain/kotlin/…/feature/feed/ui/FeedRoute.kt` — modify;
  `onOpenChat`.
- `composeApp/src/commonMain/kotlin/…/feature/feed/ui/FeedScreen.kt` — modify;
  acción de chat en el encabezado.
- `composeApp/src/commonMain/kotlin/…/design/components/AiNotice.kt` — modify;
  parámetro `text` opcional (aditivo).
- `composeApp/src/commonMain/kotlin/…/design/components/OfficialSourceLink.kt` —
  modify; `isHttpUrl` pasa a `internal` (reutilización).
- `composeApp/src/commonMain/composeResources/values/strings.xml` — modify; textos
  del chat y `contentDescription`.
- `composeApp/src/commonTest/kotlin/…/feature/chat/ChatViewModelTest.kt` — create;
  `Idle → Loading → Content/Error`, estados `ANSWERED/REFUTED/UNFOUNDED`, reintento,
  entrada en blanco ignorada.
- `composeApp/src/commonTest/kotlin/…/feature/chat/InMemoryChatRepositoryTest.kt` —
  create; clasificación determinista (answered/refuted/unfounded) y modo
  `UNAVAILABLE`.
- `composeApp/src/commonTest/kotlin/…/feature/chat/AskChatQuestionTest.kt` — create;
  guarda de consulta en blanco/longitud y paso por el puerto.
- `composeApp/src/commonTest/kotlin/…/app/AppRoutesTest.kt` — modify; ruta `chat`
  (creado por FT00034).
- `docs/pr/ft00037-ui-chat/antes-feed.png` — create; feed base (sin chat).
- `docs/pr/ft00037-ui-chat/despues-chat-respondida.png` — create.
- `docs/pr/ft00037-ui-chat/despues-chat-refutada.png` — create.
- `docs/pr/ft00037-ui-chat/despues-chat-sin-fundamento.png` — create.
- `docs/pr/ft00037-ui-chat/despues-chat-error.png` — create (opcional: carga).
- `docs/desarrollo-local.md` — modify; nota del chat (pantalla, estados y
  placeholder).

Harness (privado, repo aparte): ADR nuevo + índice, `ARCHITECTURE.md`,
`CONSTRAINTS.md`, skill `compose-multiplatform-architecture`, `PROGRESS.md`,
`feature_list.json` (ver *Durable Documentation Impact*).

Total ≈ **26 ficheros de producto** (incluidas capturas) → **atómica**, por debajo
del límite de 30. Si el recuento real se acercara a 30 (p. ej. al añadir el wiring
HTTP), se dividiría en `FT00037-PT1` (dominio + datos + ViewModel + tests) y
`FT00037-PT2` (UI + navegación + i18n + capturas), encadenadas.

## Visual Design Impact

- UI involved: **yes**.
- Design source: `.harness/DESIGN.md` (tokens = fuente de verdad; **no** cambia).
- Screens or states affected: **Chat RAG** (Core Screen 4, nueva) en sus estados
  inicial/carga/respondida/refutada/sin fundamento/error; **Feed** (nueva acción de
  chat en el encabezado). El estado `sin_fundamento`/`refutada` se señala con icono +
  texto, no solo color (`DESIGN.md` §Accessibility).
- New design artifact required: **no** — `DESIGN.md` ya describe la pantalla de chat
  («conversación simple, con las citas a la fuente siempre visibles junto a la
  respuesta») y la «Respuesta de chat: texto + lista de citas, con estado de
  "sin fundamento"/"refutada" claramente señalado».

## Durable Documentation Impact

- `ARCHITECTURE.md`: **update** — `:composeApp` gana la capa `feature/chat/`
  (dominio/datos/UI), el `ChatViewModel` con `StateFlow`, la ruta `chat` en el grafo
  y el punto de entrada desde el feed; se anota que el HTTP sigue diferido (FT00035)
  y el repositorio en memoria.
- `CONSTRAINTS.md`: **update** (pequeño) — MUST nuevos del chat: la pantalla vive en
  `feature/chat/`, muestra **siempre** las citas a la fuente oficial y el aviso de IA
  en respuestas `respondida`/`refutada`, trata `sin_fundamento` como **estado** (no
  error) y **no** persiste historial; el chat se abre desde la ruta `chat` de
  `AppNavHost`.
- `AGENTS.md`: **not needed** — no cambia el flujo, el arranque ni la verificación.
- Other docs: `docs/adr/<nuevo>-chat-cliente-citas-estados.md` — **create** (decisión
  durable: chat como tercera capa de feature sobre el patrón FT00034, un solo
  intercambio efímero, citas con guarda `http(s)`, `MutableStateFlow`+`asStateFlow()`
  por ser estado dirigido por eventos, HTTP diferido) + índice `docs/adr/README.md`
  (número libre al implementar; previsiblemente **0029**, porque FT00034 también
  reclamó 0028 en su spec — verificar el índice antes de crearlo); skill
  `compose-multiplatform-architecture` §«Estado actual» — **update**;
  `docs/desarrollo-local.md` (producto) — **update**.

## Implementation Plan

1. **Capturar el «antes»** (feed base, sin acción de chat) antes de tocar código.
2. Confirmar que FT00034 está en `main` (`AppRoutes`/`AppNavHost`/`FeedViewModel`);
   si no, **parar** (dependencia sin satisfacer).
3. `feature/chat/domain` + `data` (`ChatModels`, `AskChatQuestion`, `ChatRepository`,
   `InMemoryChatRepository`) + tests de dominio/repositorio.
4. `ChatUiState` + `ChatViewModel` (+ `factory`) + `ChatViewModelTest`.
5. `ChatRoute`/`ChatScreen`/`ChatQuestionField`/`ChatAnswerCard`/`ChatCitations` con
   sus `@Preview`; `AiNotice` con el parámetro `text`; `isHttpUrl` a `internal`.
6. Textos i18n; ruta `chat` en `AppRoutes`/`AppNavHost`; acción de chat en el feed
   (`FeedRoute`/`FeedScreen`); test de `AppRoutes`.
7. Verificar Android/Wasm/iOS, los cuatro estados y el atrás; capturar el «después».
8. Actualizar `ARCHITECTURE.md`, `CONSTRAINTS.md`, ADR + índice, la skill y
   `docs/desarrollo-local.md`; commitear capturas; `PROGRESS.md`/`feature_list.json`
   los cierra el orquestador.

## Implementation Tasks

- [ ] Capturar `antes-feed.png` antes de tocar código.
- [ ] Verificar que la base es el merge de FT00034 (si no, bloquear).
- [ ] `feature/chat/domain/{ChatModels,AskChatQuestion}.kt` y
      `feature/chat/data/{ChatRepository,InMemoryChatRepository}.kt`.
- [ ] `feature/chat/ui/{ChatUiState,ChatViewModel,ChatRoute,ChatScreen,
      ChatQuestionField,ChatAnswerCard,ChatCitations}.kt`.
- [ ] Tests `commonTest`: `ChatViewModelTest`, `InMemoryChatRepositoryTest`,
      `AskChatQuestionTest`; `AppRoutesTest` (ruta `chat`).
- [ ] Textos i18n del chat; `AiNotice` con `text`; `isHttpUrl` `internal`.
- [ ] Ruta `chat` en `AppRoutes`/`AppNavHost`; acción de chat en `FeedRoute`/`FeedScreen`.
- [ ] `:shared` **no** se cablea; sin red, sin `ktor-client`, sin serialización.
- [ ] Gate: `assembleDebug`, `wasmJsBrowserDistribution`, iOS, `jvmTest`,
      `detekt` + `:cpdCheck`, `init.sh` (SDK-free) y `init.sh --with-client`.
- [ ] Docs durables (ADR + índice, `ARCHITECTURE.md`, `CONSTRAINTS.md`, skill,
      `docs/desarrollo-local.md`) y capturas commiteadas.

## Verification Plan

Desde la raíz del producto (`..`, JDK 21; Android SDK y `local.properties` para el
cliente):

- **Gate SDK-free (obligatorio, sin cambios)**: `./gradlew build -PskipClient`,
  `./gradlew test`, `./gradlew detekt` (+ `:cpdCheck`) y `env -u JAVA_HOME
  .harness/init.sh` → BUILD SUCCESSFUL / exit 0. `init.sh` **no** se modifica.
- **Gate con cliente (`--with-client`)**: `./gradlew :composeApp:assembleDebug`,
  `./gradlew :composeApp:wasmJsBrowserDistribution` y `./gradlew :composeApp:jvmTest`
  (tests nuevos + los existentes) en verde; `./gradlew detekt` cubre `:composeApp`.
- **iOS (host macOS)**: `./gradlew :composeApp:compileKotlinIosSimulatorArm64` +
  `:composeApp:linkDebugFrameworkIosSimulatorArm64` (o `init.sh --with-ios`).
- **Tests**: `ChatViewModelTest` cubre `Idle → Loading → Content(ANSWERED/REFUTED/
  UNFOUNDED)` y `Error`, el reintento con la misma pregunta y que una consulta en
  blanco no cambia el estado; `InMemoryChatRepositoryTest` cubre la clasificación
  determinista y `UNAVAILABLE`; `AskChatQuestionTest` cubre la guarda y la longitud.
  Requiere `Dispatchers.setMain(StandardTestDispatcher())` (con `resetMain()`),
  porque `viewModelScope` usa el dispatcher Main.
- **Manual (una plataforma representativa)**: servir
  `composeApp/build/dist/wasmJs/productionExecutable/` en `http://127.0.0.1` (o APK
  en emulador); pulsar la acción de chat del feed → escribir una pregunta → ver la
  respuesta con citas y el aviso de IA → pulsar una cita (abre el BOE) → **atrás**
  (botón y atrás del sistema/navegador) y comprobar que el feed conserva su estado.
  El estado de error se verifica con `InMemoryChatMode.UNAVAILABLE` (o el
  repositorio de preview); el placeholder **no** recibe datos reales.
- **Sin red ni BD**: ningún test ni gate abre sockets ni toca PostgreSQL.
- **E2E**: no aplica — el repo **no** tiene comando E2E persistente para el cliente
  (`wasmJsBrowserTest`/Karma/Chrome fuera del gate); la cobertura es de estado/
  dominio + verificación visual manual + previews.
- **Capturas (obligatorio)**: `docs/pr/ft00037-ui-chat/` con el feed base (`antes`) y
  los estados respondida/refutada/sin fundamento/error (`después`), enlazadas en el
  PR con URL absoluta a la rama (`docs/pr/README.md`); si no hay navegador/emulador,
  justificarlo en el PR.

## Evidence To Capture

- Salida de `:composeApp:jvmTest` (recuento de tests, 0 fallos, incluidos
  `ChatViewModelTest`/`InMemoryChatRepositoryTest`/`AskChatQuestionTest`),
  `:composeApp:assembleDebug`, `:composeApp:wasmJsBrowserDistribution` y del gate
  (`build -PskipClient`, `test`, `detekt` + `:cpdCheck`, `init.sh` exit 0;
  `--with-client` verde).
- Capturas en `docs/pr/ft00037-ui-chat/` (antes y los cuatro estados).
- Confirmación manual de: chat → pregunta → respuesta con citas y aviso de IA;
  cita abre la URL oficial; atrás vuelve al feed con su estado conservado.
- Confirmación de que no hay texto visible hardcodeado, que cada `@Composable` tiene
  `@Preview`, que los colores salen solo de `colorScheme` y que `sin_fundamento` se
  muestra como estado (no error).
- Confirmación de que `:shared`, `:backend`, CI e `init.sh` no cambian y de que no se
  añaden dependencias nuevas.
- Ficheros del commit `FT00037`, PR y run de CI; entradas en `PROGRESS.md` y
  `feature_list.json` (`evidence`).

## Validator Checklist

- [ ] Alcance acotado: `feature/chat/{domain,data,ui}` + ruta `chat` + entrada desde
      el feed; **sin** HTTP/`:shared` (FT00035), **sin** reimplementar
      navegación/estado (FT00034), **sin** historial, **sin** filtros, **sin**
      framework de DI, **sin** cambios en `:shared`/`:backend`/CI/`init.sh`/`DESIGN.md`.
- [ ] Escenarios 1–10 pasan (entrada + atrás, respondida con citas, refutada, sin
      fundamento, error/reintento, entrada inválida, ViewModel+`StateFlow`, i18n/
      previews/iconos/colores, tres plataformas + gate, capturas).
- [ ] `ChatViewModel` expone `StateFlow<ChatUiState>`; composables stateless; UI
      recolecta con `collectAsStateWithLifecycle`; todo pasa por `AskChatQuestion`.
- [ ] `sin_fundamento` **no** es error (sin icono/botón de error) y lleva citas
      vacías; `respondida`/`refutada` llevan ≥1 cita; las citas abren la URL oficial
      con guarda `http(s)://` sin *crash*; el aviso de IA es visible.
- [ ] Cada `@Composable` de UI tiene `@Preview` dentro del tema; ningún texto visible
      hardcodeado; iconos con significado usan Material Icons + `contentDescription`;
      colores **solo** de `MaterialTheme.colorScheme.*`.
- [ ] Nunca se provoca un crash: consulta en blanco ignorada, `Failure` modelado con
      reintento, URL inválida deshabilitada.
- [ ] Estilo MUST: un solo `return`, sin `else if`, funciones ≤40 líneas, KDoc en
      castellano, identificadores en inglés.
- [ ] El gate SDK-free sigue verde; el gate con cliente compila Android/Wasm/iOS y
      pasa `jvmTest`; `init.sh` no se modifica; el PR no supera los 30 ficheros.
- [ ] Capturas antes/después en `docs/pr/ft00037-ui-chat/` enlazadas con URL absoluta
      a la rama (o justificación).
- [ ] `ARCHITECTURE.md`, `CONSTRAINTS.md`, ADR nuevo + índice, la skill de CMP y
      `docs/desarrollo-local.md` actualizados; `PROGRESS.md` y `feature_list.json`
      corregidos.

## Risks / Open Questions

- **Gap de wiring HTTP (el riesgo mayor).** FT00037 **no** depende de FT00035
  (`ui-cliente-http-cache`) y el HTTP está fuera de alcance: igual que FT00033 con el
  detalle, la pantalla se entrega con **repositorio en memoria** y el endpoint
  `POST /v1/chat` **no** se consume. Ninguna feature del MVP cablea hoy el HTTP de
  detalle/chat/búsqueda (FT00035 los excluye explícitamente en sus *Non-Goals*). Se
  recomienda planificar una **feature de wiring** (p. ej. `FT00048`) o extender
  FT00035 para que, reutilizando `core/network`, añada
  `HttpChatRepository`/`HttpDetailRepository`/`HttpSearchRepository`; el puerto y el
  mapeo están diseñados para que ese trabajo sea puramente aditivo. Hasta entonces,
  la aceptación se cumple con el placeholder (precedente FT00033).
- **Dependencia en validación.** FT00034 (`ui-navegacion-estado`) aún no está en
  `main`: la implementación debe partir de su merge. Si el merge se retrasa, FT00037
  queda **bloqueada**. Su contrato (`AppRoutes`/`AppNavHost`/`FeedViewModel`/
  `collectAsStateWithLifecycle`) se ha tomado de `docs/specs/ui-navegacion-estado.md`;
  si el merge cambia nombres/firmas, ajustar los puntos de integración (ruta `chat`,
  `onOpenChat`, factoría del ViewModel).
- **Punto de entrada al chat.** `DESIGN.md` no especifica la *chrome* de navegación.
  Se elige una acción de **texto** en el encabezado del feed (no hay icono `Chat` en
  `material-icons-core` y no se añade `material-icons-extended`). Si el orquestador
  prefiere otra solución (p. ej. barra inferior o FAB), es un cambio de chrome que
  afecta a las capturas; decidirlo antes de implementar. La búsqueda (FT00036)
  necesitará un punto de entrada equivalente: coordinar para no duplicar.
- **`AiNotice` con parámetro `text`.** Modificación aditiva de un componente usado
  por FT00033; el detalle mantiene el valor por defecto. Si el valor por defecto
  composable (`stringResource`) diera problemas, usar dos sobrecargas.
- **Clasificación determinista del placeholder.** El repositorio en memoria decide
  `answered`/`refuted`/`unfounded` por palabras del texto; es **solo** para montar y
  verificar la UI, no simula la calidad del RAG real. Documentado en KDoc y cubierto
  por tests.
- **`material-icons-core` limitado.** Solo el set reducido; `Send` está disponible
  (`Icons.AutoMirrored.Outlined.Send`), `Chat`/`Forum` **no**. Cualquier icono nuevo
  debe comprobarse contra el set antes de usarlo.
- **Un solo intercambio.** `DESIGN.md` dice «conversación simple»; el historial
  local/efímero es una pregunta abierta (`docs/risks-and-open-questions.md`). Se
  entrega **un** intercambio (pregunta + respuesta) efímero; el multi-turno local se
  puede añadir después sin cambiar el contrato del endpoint.
- **Rate limiting (429).** El endpoint limita el chat (FT00030, 6/60 s). Con el
  placeholder no aplica; cuando se cablee el HTTP, un `429` se mapeará a `Failure`
  (mensaje de reintento genérico); distinguir «demasiadas consultas» es un follow-up.
- **CPD/detekt sobre previews y tarjetas de estado.** `:cpdCheck` barre `commonMain`;
  factorizar el contenido de los estados para no duplicar bloques >100 tokens.
- **División.** ≈26 ficheros (incluidas capturas) → **atómica**; si al implementar el
  recuento se acerca a 30, partir en `FT00037-PT1` (dominio/datos/ViewModel/tests) +
  `FT00037-PT2` (UI/navegación/i18n/capturas).
