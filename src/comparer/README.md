# Etir Native Comparer

This directory holds everything for the DOCX compare engine:

```
src/comparer/
├── compare.zig            # Zig FFI wrapper + tests
├── dotnet/                # NativeAOT project wrapping WmlComparer
│   ├── EtirComparer.csproj
│   └── Program.cs
└── publish/<rid>/         # dotnet publish outputs produced by zig build comparer
```

Use `zig build comparer` to publish for the current RID. The build step runs:

```
.dotnet/dotnet publish src/comparer/dotnet/EtirComparer.csproj \
  -c Release -r <rid> -p:PublishAot=true --self-contained true \
  -o src/comparer/publish/<rid>
```

The Zig tests load the matching shared library from `src/comparer/publish/<rid>/EtirComparer.{dylib,so,dll}`.
