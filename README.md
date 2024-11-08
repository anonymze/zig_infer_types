# Scan a directory for a specific type files (.svg here), and create a Typescript type for every filename

```typescript
// start-infer-types
type SVGNameIcons = "lol" | "coucou";
// end-infer-types
```
## ZIG

### commands

zig run src/main.zig -- --filename global.d.ts --directory public/icons
zig build
