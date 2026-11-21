# iWolfAnalyticsKIT

SDK de analítica de **iWolf Studios** distribuido como **Swift Package**, diseñado para registrar eventos de aplicaciones iOS y macOS y enviarlos al backend de iWolf Studios Analytics mediante una cola persistente.

> Estado: SDK revisado antes de su primera integración con AwakeNest. La última ejecución comunicada por el proyecto fue de **114 tests correctos**. La integración real con AwakeNest y la validación extremo a extremo con el backend siguen pendientes.

## Compatibilidad

- iOS 15 o posterior.
- macOS 14 o posterior.
- Swift Package Manager.
- Concurrencia de Swift (`actor`, `async`/`await`).

## Instalación

En Xcode, añade el paquete mediante **File → Add Package Dependencies…** e introduce la URL del repositorio:

```text
git@github.com:omarGSR/iWolfStudiosAnalyticsKIT.git
```

Selecciona el producto del paquete para el target correspondiente. La versión o referencia de dependencia debe elegirse según los tags/branches publicados en el repositorio.

## Inicio rápido

```swift
import iWolfAnalyticsKIT

let configuration = AnalyticsConfiguration(
    baseURL: URL(string: "https://api.iwolfstudios.io")!,
    appKey: Bundle.main.bundleIdentifier ?? ""
)

try await iWolfAnalyticsKIT.shared.configure(configuration)
```

`configure(_:)`:

1. Prepara la cola persistente, el cliente HTTP, el manager y el scheduler.
2. Guarda **un** evento `app_open` por inicialización correcta del SDK en el proceso.
3. Activa la sincronización automática.
4. Es idempotente: llamadas repetidas o concurrentes no duplican la inicialización.

La URL anterior es el valor por defecto observado en `AnalyticsConfiguration`; confirma la URL definitiva del entorno antes del despliegue.

## Registrar eventos

```swift
try await iWolfAnalyticsKIT.shared.track("settings_opened")

try await iWolfAnalyticsKIT.shared.track(
    "session_started",
    sessionUUID: UUID(),
    metadata: [
        "mode": "discreet",
        "source": "menu_bar"
    ]
)
```

Parámetros de `track`:

| Parámetro | Tipo | Descripción |
| --- | --- | --- |
| `eventName` | `String` | Nombre del evento. |
| `sessionUUID` | `UUID?` | Identificador opcional de sesión. |
| `metadata` | `[String: String]?` | Metadatos opcionales. |

Cada evento tiene su propio UUID y fecha de creación. `track()` **persiste primero** el evento y después notifica al scheduler mediante una tarea asíncrona: no espera a que termine la petición HTTP. Si el SDK no está configurado, lanza `AnalyticsSDKError.notConfigured`.

Los nombres `settings_opened` y `session_started` son ejemplos: conviene definir un catálogo de eventos específico para AwakeNest antes de instrumentarla.

## Sincronización

La sincronización automática aplica una política interna y el estado del manager. Valores acordados para producción:

| Parámetro | Valor |
| --- | --- |
| Tamaño de batch por defecto | 20 eventos |
| Intervalo normal | 120 segundos |
| Umbral para intervalo normal | 3 eventos |
| Envío forzado de colas pequeñas | 10 minutos |
| Batch completo | Envío inmediato |
| Máximo de reintentos por rechazo individual temporal | 4, por defecto |

**Importante:** los intervalos de 120 segundos y 10 minutos son la política acordada durante la revisión; el ZIP de referencia disponible contenía constantes anteriores (180 segundos y 15 minutos). Verifica `AnalyticsLimits.swift` en la rama actual antes de dar por cerrada la configuración de producción.

También es posible solicitar una sincronización manual:

```swift
try await iWolfAnalyticsKIT.shared.sync()
```

La sincronización manual no está sujeta a los umbrales de cantidad/tiempo del scheduler, pero **sí** respeta el estado del manager (por ejemplo, backoff o detención por error permanente).

## Ciclo de vida de la aplicación

Cuando la aplicación vuelve a estar activa, se puede solicitar una reevaluación de la cola:

```swift
await iWolfAnalyticsKIT.shared.applicationDidBecomeActive()
```

Este método **no** genera un nuevo `app_open`; solo solicita al scheduler que reevalúe los eventos pendientes.

Para suspender y reanudar la sincronización automática:

```swift
await iWolfAnalyticsKIT.shared.stopAutomaticSync()
await iWolfAnalyticsKIT.shared.startAutomaticSync()
```

Detener el scheduler no elimina los eventos. Reiniciarlo tampoco elimina un estado permanente de detención del manager. No se debe depender de una petición HTTP síncrona durante el cierre de la app: los eventos pendientes permanecen en almacenamiento local para un arranque posterior, salvo las excepciones de descarte descritas abajo.

## Persistencia y entrega

- Los eventos se guardan localmente antes de enviarse.
- La cola usa un archivo JSON en Application Support, bajo el identificador de bundle de la aplicación, en la carpeta `Analytics/events_queue.json` según la implementación inspeccionada.
- Las peticiones usan `POST /api/v1/events/batch`.
- El envío es por lotes; las respuestas pueden aceptar o rechazar eventos individuales.
- La cola persistente permite recuperar eventos tras interrupciones o cierres de la aplicación.

**La entrega no está garantizada**: hay rechazos permanentes, agotamiento de reintentos individuales y errores globales que, por política, pueden vaciar la cola.

## Política de errores — resumen

| Situación | Comportamiento |
| --- | --- |
| HTTP 5xx o error de red | Conservar eventos y reintentar con backoff; sin incrementar `retryCount` individual. |
| HTTP 429 | Reintento global posterior según el estado de sincronización. |
| HTTP 413 | Reducir tamaño efectivo del batch. |
| Error global `invalid_app_key` o `application_not_found` | Detener sincronización y vaciar la cola persistente. |
| Otros errores globales permanentes (p. ej., HTTP 401) | Detener sincronización conservando eventos. |
| Rechazo individual temporal conocido | Incrementar `retryCount` y reintentar hasta el máximo configurado. |
| Rechazo individual permanente o desconocido | Eliminar el evento rechazado. |
| Rechazo individual de configuración/seguridad clasificado como `keep` | Mantener el evento sin incrementar su contador. |

Los errores **globales** de una respuesta HTTP y los rechazos **individuales** de una respuesta válida son rutas distintas. Consulta [`ARCHITECTURE.md`](ARCHITECTURE.md) para las reglas detalladas y las prioridades entre batches concurrentes.

## Pruebas y validación

La última suite ejecutada por el desarrollador pasó **114 tests**. Incluye cobertura de configuración concurrente, `app_open`, persistencia, `track()` sin espera de red, scheduler, stop/restart, backoff y errores globales con batches concurrentes.

Antes de publicar:

1. Verificar las constantes finales de `AnalyticsLimits.swift`.
2. Integrar el SDK en AwakeNest y definir sus eventos.
3. Comprobar la API real, el identificador de aplicación y el formato de respuestas.
4. Validar el comportamiento en el ciclo de vida real de macOS y, posteriormente, en iOS.

## Arquitectura

Consulta [ARCHITECTURE.md](ARCHITECTURE.md).
