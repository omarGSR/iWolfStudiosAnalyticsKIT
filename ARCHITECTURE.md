# iWolfAnalyticsKIT — Arquitectura

## 1. Alcance y estado

Este documento describe la arquitectura del SDK Swift de iWolf Studios Analytics, revisada el **21 de noviembre de 2026** antes de su integración con AwakeNest.

**Fuentes utilizadas:** archivos actualizados `iWolfAnalyticsKIT.swift`, `AnalyticsSyncScheduler.swift`, tests de manager/scheduler/SDK y código fuente del ZIP de referencia. El ZIP es **anterior** a varias correcciones recientes: cuando difiere de los tests o de las decisiones verificadas durante la revisión, se indica explícitamente. No debe considerarse un snapshot íntegro de la última rama.

## 2. Componentes

| Componente | Responsabilidad |
| --- | --- |
| `iWolfAnalyticsKIT` | Actor de entrada pública; configuración, `track`, `sync` y ciclo de vida. |
| `AnalyticsConfiguration` | URL base, app key, tamaño de batch, máximo de reintentos y concurrencia HTTP. |
| `AnalyticsEvent` | Evento con UUID, fecha, nombre, sesión opcional y metadatos. |
| `AnalyticsEventQueue` | Actor que persiste la cola FIFO y los contadores individuales de reintentos. |
| `QueuedAnalyticsEvent` | Evento persistido junto a su información de cola y reintentos. |
| `AnalyticsSyncScheduler` | Decide cuándo evaluar y solicitar la sincronización automática. |
| `AnalyticsSyncPolicy` | Regla de batch completo, intervalo normal y envío forzado. |
| `AnalyticsSyncManager` | Reserva batches, coordina solicitudes concurrentes, procesa resultados y aplica estados de error. |
| `AnalyticsBatchSelector` | Selección de eventos para lotes. |
| `AnalyticsAPIClient` | Serializa el batch y ejecuta `POST /api/v1/events/batch`. |
| `AnalyticsEndpoint` | Centraliza las rutas de API. |
| `AnalyticsBatchResponseProcessor` | Procesa aceptación y rechazo individual de eventos. |
| `AnalyticsGlobalErrorHandler` | Convierte errores de petición/batch en acciones globales. |
| `AnalyticsEventErrorHandler` | Convierte rechazos de un evento en acciones individuales. |
| `AnalyticsSyncState` | Estado de disponibilidad, backoff, detención y tamaño efectivo de batch. |
| `AnalyticsInstallationManager` | Gestiona un UUID persistente por instalación. |
| `AnalyticsDeviceInfo` | Obtiene datos técnicos de la app y dispositivo. |

## 3. Flujo de datos

```text
Aplicación (AwakeNest / iOS)
        │
        ├── configure(configuration)
        │       ├── crea dependencias
        │       ├── persiste app_open
        │       └── inicia AnalyticsSyncScheduler
        │
        └── track(eventName, sessionUUID?, metadata?)
                │
                ▼
       AnalyticsEventQueue (JSON persistente)
                │
                └── notificación asíncrona (no espera a HTTP)
                        │
                        ▼
                AnalyticsSyncScheduler
                        │  política + estado del manager
                        ▼
                AnalyticsSyncManager
                        │  reserva lotes sin duplicar eventos en vuelo
                        ▼
                AnalyticsAPIClient
                        │
                        ▼
                POST /api/v1/events/batch
                        │
             ┌──────────┴───────────┐
             ▼                      ▼
       Error global          Respuesta válida
             │               con aceptados/rechazados
             ▼                      │
       GlobalErrorHandler           ▼
                             EventErrorHandler
             └──────────┬───────────┘
                        ▼
               Actualización de cola
                  y estado de sync
```

## 4. API pública y ciclo de vida

`iWolfAnalyticsKIT` es un `actor` con singleton `shared` y un inicializador interno para tests. `configure(_:)` se ejecuta una vez por proceso; las llamadas concurrentes esperan la misma tarea de inicialización. Encola un `app_open` antes de arrancar el scheduler.

`track()` construye el evento, lo **persiste** y lanza una tarea para `eventEnqueued()`. La tarea de notificación puede terminar después del retorno de `track()`; la persistencia es la garantía inmediata.

`sync()` solicita al manager sincronizar, sin aplicar los umbrales temporales del scheduler. `applicationDidBecomeActive()` reevalúa la cola si el SDK está configurado. `stopAutomaticSync()` y `startAutomaticSync()` controlan el scheduler, no restablecen automáticamente un manager detenido por error permanente.

No hay un hook público de cierre obligatorio. El almacenamiento persistente evita que el cierre normal de la aplicación requiera esperar a la red.

## 5. Cola persistente

La cola almacena eventos con sus identificadores y contador de reintentos. La implementación de referencia utiliza `Application Support/<bundle identifier>/Analytics/events_queue.json` y codificación JSON con fechas ISO 8601.

Operaciones principales:

- `enqueue`: persistir antes de confirmar la inserción.
- `peek`: consultar los eventos FIFO, con exclusión de UUID ya reservados.
- `remove(ids:)`: retirar eventos aceptados o descartados.
- `incrementRetryCount(for:)`: aumentar reintentos **solo** cuando corresponde a un rechazo individual temporal.
- `removeAll()`: persistir la cola vacía y limpiar memoria, incorporado en la revisión posterior al ZIP.

Si una escritura de persistencia falla, la operación no debe tratarse como completada. La cola sobrevive a reinicios de proceso siempre que su archivo permanezca accesible.

## 6. Política de sincronización automática

**Valores acordados para producción:**

| Condición | Acción |
| --- | --- |
| Cola vacía | No sincronizar. |
| Cola alcanza tamaño efectivo del batch (20 por defecto) | Sincronizar inmediatamente. |
| Hay al menos 3 eventos sin completar batch | Sincronizar tras 120 segundos de antigüedad del evento más antiguo. |
| Hay 1–2 eventos | Forzar evaluación/sincronización a los 10 minutos. |
| Manager en backoff | Esperar hasta `nextRetryAt`. |
| Intento sin progreso de cola | Aplicar cooldown para evitar bucles rápidos. |
| Manager detenido | No programar nuevas solicitudes. |

**Verificación pendiente:** el ZIP de referencia todavía define 180 segundos y 15 minutos en `AnalyticsLimits.swift`. La política de 120 segundos/10 minutos procede de la decisión de diseño posterior y debe comprobarse en la rama final.

El scheduler usa `generation` para invalidar evaluaciones antiguas tras stop/restart; `evaluationGeneration` y `needsEvaluation` coordinan evaluaciones sin recursión. Cancela tareas programadas al detenerse y vuelve a evaluar al reiniciarse.

## 7. Concurrencia y selección de batches

`AnalyticsSyncManager` reserva eventos para evitar que dos peticiones HTTP seleccionen los mismos UUID. La configuración limita la cantidad de peticiones simultáneas (2 por defecto en la implementación de referencia; máximo configurable hasta 4).

La revisión del manager confirmó este comportamiento:

1. Reserva los batches iniciales disponibles.
2. Envía las solicitudes concurrentemente.
3. Procesa cada resultado y libera su reserva.
4. Mientras no se haya observado un error global, puede reservar el siguiente batch.
5. Al observar el **primer error global**, deja de programar nuevos batches, pero espera a que finalicen los que ya estaban en vuelo.
6. Aplica la acción global de mayor prioridad al concluir las solicitudes en curso.

Esto implica que el número de peticiones puede variar según el orden de las respuestas. Los tests `testStopAndClearErrorFirst` y `testStopAndClearSuccessFirst` verifican respectivamente que el error llegue primero y que una respuesta correcta permita programar un batch adicional antes de observar el error.

## 8. Distinción fundamental: error global vs. rechazo individual

**Nunca debe aplicarse una política individual a un error global.**

- **Error global:** falla la petición o el batch completo (respuesta HTTP no satisfactoria, falta de red, etc.). Lo resuelve `AnalyticsGlobalErrorHandler` y lo aplica el manager al estado global.
- **Rechazo individual:** el backend responde correctamente (HTTP 2xx válido) pero marca uno o varios eventos como rechazados. Lo resuelve `AnalyticsEventErrorHandler` y se aplica solo a esos eventos.

### 8.1 Errores globales

| Caso | Acción | Cola | `retryCount` individual |
| --- | --- | --- | --- |
| Sin conexión / fallo de transporte | `retry` | Conservar | No aumenta |
| HTTP 500, 503 y otros 5xx | `retry` | Conservar | No aumenta |
| HTTP 429 | `retry` | Conservar | No aumenta |
| HTTP 413 / batch demasiado grande | `reduceBatchSize` | Conservar y reducir batch | No aumenta |
| `invalid_app_key` global (HTTP 400) | `stopAndClear` | **Vaciar completamente** | No aplica |
| `application_not_found` global (HTTP 404) | `stopAndClear` | **Vaciar completamente** | No aplica |
| HTTP 401 y otros errores globales permanentes | `stop` | Conservar | No aumenta |

Los fallos temporales globales mantienen los eventos para reintentos posteriores con backoff, **sin límite basado en `maxRetries` individual**. No significa reintento continuo sin espera: siempre debe respetarse el estado y el calendario de sincronización.

Los dos errores `stopAndClear` son una **decisión explícita de producto**: el backend ha rechazado la identidad de la aplicación y se descarta la cola existente. El manager detiene la sincronización y persiste el vaciado **después de drenar** los batches ya enviados.

Los demás errores `.stop` preservan los eventos, para que no se pierdan por una detención de configuración o autorización.

### 8.2 Rechazos individuales en respuestas válidas

| Tipo de rechazo | Acción | Efecto |
| --- | --- | --- |
| Temporal conocido (`internal_error`, `service_unavailable`, `rate_limit_exceeded`) | `retry` | Incrementar contador del evento; eliminarlo al superar/agotar la política `maxRetries`. |
| Permanente conocido (UUID, nombre, fecha, campos o metadatos inválidos) | `remove` | Eliminar solo ese evento. |
| Configuración/seguridad individual conocido (`invalid_app_key`, `application_not_found`, `unauthorized`, `forbidden`) | `keep` | Conservar ese evento sin aumentar `retryCount`. |
| Código individual desconocido para esta versión del SDK | `remove` | Eliminar ese evento para evitar colas perpetuas en clientes antiguos. |

`maxRetries` tiene valor por defecto 4 en la configuración de referencia. La lógica de rechazo individual no debe borrar toda la cola salvo que otra política global lo ordene.

**Ejemplo:** una respuesta HTTP 200 con dos eventos aceptados, un rechazo individual `service_unavailable` y un código individual desconocido elimina los aceptados, reintenta el temporal y elimina el desconocido. En cambio, una respuesta HTTP 503 no incrementa los contadores individuales de ninguno de los eventos del batch.

### 8.3 Prioridad de errores concurrentes

Cuando llegan respuestas distintas de batches concurrentes, el manager conserva la acción global de mayor prioridad. En la revisión se estableció que `stopAndClear` tiene prioridad máxima. Los tests existentes también cubren la prioridad de detención frente a reintento y de reducción de batch frente a reintento.

No se debe aplicar una respuesta exitosa tardía para restablecer el estado de error global que ya se ha detectado en el mismo ciclo de sincronización.

## 9. Red y contrato del backend

- Endpoint: `POST /api/v1/events/batch` (construido por `AnalyticsEndpoint`).
- Cuerpo JSON de batch; los eventos incluyen `event_uuid`, `event_name`, `occurred_at`, `session_uuid` opcional y `metadata` opcional.
- La respuesta exitosa permite procesar la lista `data.rejected`.
- Los errores HTTP pueden aportar `error.code`, `error.message` y cabecera `Retry-After`.
- El límite de referencia de batch es 40 eventos, alineado con la constante indicada para el backend.

El contrato definitivo de producción debe validarse con la API desplegada, especialmente límites, errores individuales y compatibilidad de versiones.

## 10. Instalación y datos técnicos

`AnalyticsInstallationManager` mantiene un UUID de instalación en `UserDefaults`, bajo la clave `iWolfAnalytics.installationUUID` en el código de referencia. `AnalyticsDeviceInfo` recoge versión de app, versión del sistema, identificador técnico del modelo de dispositivo y país cuando están disponibles.

Estos identificadores no deben confundirse con `sessionUUID` (opcional, por evento) ni con `event_uuid` (único por evento). La revisión no constituye una auditoría de privacidad ni verifica la política de conservación del backend.

## 11. Cobertura y límites de validación

La última ejecución comunicada de la suite fue de **114 tests correctos**. Se han revisado pruebas de:

- Persistencia y creación única de `app_open`.
- Configuración concurrente.
- `track()` que no espera la respuesta HTTP.
- Sincronización automática y manual, stop/restart y reactivación.
- Backoff y prevención de bucles sin progreso.
- Errores permanentes y vaciado persistente de cola.
- Batches concurrentes con distintos órdenes de respuesta.

La suite verde no sustituye la integración real. Antes de publicar AwakeNest, validar el flujo completo aplicación → SDK → backend → dashboard y la versión definitiva de `AnalyticsLimits.swift`.

## 12. Decisiones de diseño pendientes de ampliar

- Integración de AwakeNest y catálogo estable de nombres/metadatos de eventos.
- Verificación final de los valores del scheduler en el repositorio actual.
- Pruebas reales de red, cierre/reapertura de la aplicación y revisión de sandbox de macOS.
- Documentar la política de privacidad y retención del backend si se expone al usuario final.

No se plantea ampliar el alcance del SDK para completar esta primera integración.
