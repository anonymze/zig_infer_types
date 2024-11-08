# Scan a directory for a cretain type files (.svg here), and create a Typescript type for every file

```typescript
// start-infer-types
type SVGNameIcons = "lol" | "coucou";
// end-infer-types
```
## ZIG

 zig run src/main.zig -- --filename global.d.ts --directory public/icons
 zig build

### commands
