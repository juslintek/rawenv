# shared/

Single source of truth for mock data used across all 3 native GUI platforms (macOS, Linux, Windows).

## Files

| File | Purpose |
|------|---------|
| `mock-data.json` | All mock/demo data for services, logs, AI chat, connections, projects, settings, installer, and deploy |
| `schema.json` | JSON Schema (Draft 2020-12) that validates `mock-data.json` |

## Validate

```bash
npx ajv-cli validate --spec=draft2020 -s schema.json -d mock-data.json
```

## Platform Loading

### macOS (Swift)

```swift
guard let url = Bundle.main.url(forResource: "mock-data", withExtension: "json"),
      let data = try? Data(contentsOf: url) else { return }
let mockData = try JSONDecoder().decode(MockData.self, from: data)
```

### Linux (Vala)

```vala
var parser = new Json.Parser();
parser.load_from_file("shared/mock-data.json");
var root = parser.get_root().get_object();
```

### Windows (C#)

```csharp
using var stream = File.OpenRead("shared/mock-data.json");
var mockData = JsonSerializer.Deserialize<MockData>(stream);
```

## Schema Update Process

1. Modify `schema.json` with the new/changed structure
2. Update `mock-data.json` to match
3. Run validation to confirm
4. Update platform models (Swift structs, Vala classes, C# records)
