# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Happy Server is a minimal, end-to-end encrypted synchronization backend for Claude Code clients. All data is encrypted client-side before reaching the server - the server stores encrypted blobs it cannot read.

**Tech Stack**: Node.js 20, TypeScript (strict), Fastify 5, PostgreSQL/Prisma, Redis (ioredis), Socket.io, Zod, Vitest

## Commands

```bash
yarn build          # TypeScript type checking (tsc --noEmit)
yarn start          # Start server
yarn dev            # Dev server with env files (kills existing process on port 3005)
yarn test           # Run all tests
yarn test path/to/file.spec.ts  # Run single test file
yarn generate       # Generate Prisma client after schema changes
yarn db             # Start local PostgreSQL in Docker
yarn redis          # Start local Redis in Docker
yarn s3             # Start local MinIO S3 in Docker
```

**Important**: Use `yarn` (not npm) for all package management.

## Code Style

- **4 spaces** for indentation (not 2)
- All imports use `@/` prefix: `import { db } from "@/storage/db"`
- Functional patterns; avoid classes (except Context)
- Prefer interfaces over types; avoid enums (use maps)
- Name files and exported functions identically for discoverability
- Test files use `.spec.ts` suffix

## Architecture

### Source Structure

```
/sources
├── main.ts                    # Entry point - initializes storage, auth, API
├── context.ts                 # Context class for user-scoped operations
├── /app                       # Application logic
│   ├── /api                   # Fastify API server
│   │   ├── api.ts            # Server setup, route registration
│   │   ├── socket.ts         # Socket.io connection handling
│   │   ├── /routes           # HTTP route handlers
│   │   └── /socket           # WebSocket event handlers
│   ├── /events               # Real-time event routing (eventRouter)
│   ├── /auth                 # Authentication module
│   ├── /session              # Session operations (sessionDelete, etc.)
│   ├── /social               # Friend/relationship features
│   ├── /feed                 # User feed operations
│   ├── /kv                   # Key-value storage operations
│   └── /presence             # Activity/timeout tracking
├── /storage                   # Database & storage layer
│   ├── db.ts                 # Prisma client singleton
│   ├── inTx.ts               # Transaction wrapper with afterTx callbacks
│   ├── redis.ts              # Redis client
│   └── files.ts              # S3/MinIO file storage
├── /modules                   # Reusable non-app-specific modules
│   ├── encrypt.ts            # Encryption utilities
│   └── github.ts             # GitHub OAuth integration
└── /utils                     # Low-level utilities
```

### Key Patterns

**Transaction Pattern**: Use `inTx` for database operations. Use `afterTx` for side effects (events, notifications) that should only run after commit:
```typescript
await inTx(async (tx) => {
    await tx.user.update(...);
    afterTx(tx, () => eventRouter.emitUpdate(...));
    return result;
});
```

**Action Functions**: For database operations (adding friends, creating sessions), create dedicated files in `/sources/app/` subfolders. Name pattern: `entityAction.ts` (e.g., `friendAdd.ts`, `sessionDelete.ts`). Add documentation comments explaining the logic.

**Event Router**: `eventRouter` in `/sources/app/events/eventRouter.ts` handles real-time updates via WebSocket. Three connection types:
- `user-scoped`: Mobile/web clients (receives all user updates)
- `session-scoped`: CLI connected to specific session
- `machine-scoped`: Daemon processes on machines

**Route Definition**: Routes use Fastify with Zod type provider. Authentication via `preHandler: app.authenticate`:
```typescript
app.post('/v1/endpoint', {
    schema: { body: z.object({ field: z.string() }) },
    preHandler: app.authenticate
}, async (request, reply) => {
    const userId = request.userId;
    // ...
});
```

## Database

- Prisma ORM with PostgreSQL
- **Never create migrations yourself** - only run `yarn generate` after schema changes
- Use `inTx` for transactional operations with serializable isolation
- Use `Json` type for complex fields
- Do not run non-transactional operations (file uploads) inside transactions

## Important Rules

- Design operations to be **idempotent** - clients may retry requests
- Do not return values from action functions "just in case" - only return essential data
- Do not add logging unless explicitly asked
- Use `privacyKit.encodeBase64` / `privacyKit.decodeBase64` instead of Buffer for base64
- Use GitHub usernames for user identification
- After writing an action function, add a documentation comment explaining the logic

## Debugging

Server logs to `.logs/` with timestamped files (`MM-DD-HH-MM-SS.log`). Enable remote logging with `DANGEROUSLY_LOG_TO_SERVER_FOR_AI_AUTO_DEBUGGING=true`.

```bash
# Check current time and latest logs
date && ls -la .logs/*.log | tail -5

# Search for errors
tail -100 .logs/*.log | grep -E "(error|Error|ERROR|failed|Failed)"

# Monitor real-time socket events
tail -f .logs/*.log | grep -E "(new-session|websocket|Socket.*connected)"
```

### Environment Variables
- **Server**: Use `yarn dev` (loads `.env` and `.env.dev`)
- **CLI**: Use `yarn dev:local-server` (NOT `yarn dev`) to load `.env.dev-local-server`
- Check `HAPPY_SERVER_URL` if wrong server; `HAPPY_HOME_DIR` should be `~/.happy-dev` for local
