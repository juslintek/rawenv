# Linux Architecture — GTK4 + Vala

## Stack

| Layer | Technology |
|-------|-----------|
| Language | Vala |
| UI Framework | GTK4 + Libadwaita |
| Reactivity | GObject properties + `notify` signals |
| Architecture | MVVM |
| Build | Meson |
| Testing | GLib.Test (unit) + dogtail/AT-SPI (e2e) |

## Directory Structure

```
gui/linux/
├── meson.build
├── src/
│   ├── app.vala                          # Application entry
│   ├── window.vala                       # Main window
│   ├── models/
│   │   ├── service.vala
│   │   ├── log_entry.vala
│   │   └── ai_action.vala
│   ├── interfaces/
│   │   ├── data_repository.vala          # GInterface
│   │   ├── navigation_service.vala
│   │   └── ai_provider.vala
│   ├── services/
│   │   ├── mock_data_repository.vala
│   │   ├── mock_ai_provider.vala
│   │   └── live_data_repository.vala
│   ├── viewmodels/
│   │   ├── dashboard_viewmodel.vala
│   │   ├── settings_viewmodel.vala
│   │   ├── services_viewmodel.vala
│   │   └── ai_chat_viewmodel.vala
│   └── views/
│       ├── dashboard/
│       ├── settings/
│       ├── services/
│       └── ai_chat/
├── tests/
│   ├── unit/                             # GLib.Test
│   │   ├── test_dashboard_viewmodel.vala
│   │   └── test_mock_data_repository.vala
│   └── e2e/                              # Python dogtail
│       ├── pages/
│       │   ├── dashboard_page.py
│       │   └── settings_page.py
│       └── test_dashboard.py
└── Dockerfile.test                       # Reproducible test environment
```

## Naming Conventions

| Element | Convention | Example |
|---------|-----------|---------|
| Files | snake_case | `dashboard_viewmodel.vala` |
| Classes, Interfaces | PascalCase | `DashboardViewModel`, `DataRepository` |
| Methods, properties | snake_case | `fetch_services()`, `service_list` |
| Constants | SCREAMING_SNAKE | `DEFAULT_PORT`, `MAX_RETRIES` |
| Signals | snake_case with hyphens in GObject | `notify::service-list` |

## GObject Patterns

| Concept | GObject Equivalent |
|---------|-------------------|
| Protocol | `GInterface` |
| Observer | `notify` signal on GObject properties |
| Reactive state | GObject properties with `get`/`set` |
| Dependency Injection | Constructor parameters typed as interfaces |

### Interface Definition

```vala
public interface DataRepository : Object {
    public abstract async Service[] fetch_services () throws Error;
    public abstract async LogEntry[] fetch_logs (Service service) throws Error;
}

public interface NavigationService : Object {
    public abstract void navigate_to (string destination);
    public abstract void go_back ();
}

public interface AIProvider : Object {
    public abstract async AIResponse send (string prompt) throws Error;
    public abstract void cancel ();
    public abstract AIAutonomyLevel autonomy_level { get; set; }
}
```

## Patterns Used

| Pattern | Implementation |
|---------|---------------|
| Observer | GObject `notify` signal on properties |
| Factory Method | Widget creation methods returning abstract `Gtk.Widget` |
| Mediator | Navigation controller mediating between views |
| Template Method | Base view class with virtual `setup()`, `bind()`, `teardown()` |
| Command | AI actions as `AICommand` objects with `execute()` / `undo()` |
| State | Service lifecycle via enum + transition methods |

## Testing

### Unit Tests (GLib.Test)

- ViewModel logic tested with mock interfaces
- Mock data loaded from `shared/mock-data.json`
- Run via `meson test`

### E2E Tests (dogtail / AT-SPI)

- Accessible names on ALL widgets (`accessible_name`, `accessible_description`)
- Page Object pattern in Python:

```python
class DashboardPage:
    def __init__(self, app):
        self.app = app
        self.window = app.child(roleName='frame', name='Rawenv')

    @property
    def services_list(self):
        return self.window.child(roleName='list', name='services_list')

    def select_service(self, name):
        self.services_list.child(name=name).click()
        return ServiceDetailPage(self.app)
```

### Dockerfile.test

Provides reproducible environment with GTK4, Libadwaita, Vala, AT-SPI, and dogtail pre-installed for CI.

## Build

```bash
meson setup builddir
meson compile -C builddir
meson test -C builddir
```
