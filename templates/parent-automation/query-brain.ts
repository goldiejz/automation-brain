/**
 * Brain Query Interface — Bootstrap integrates with Obsidian Brain snapshot
 *
 * Queries embedded snapshot at .parent-automation/brain-snapshot/
 * Falls back to optional central API if snapshot is stale and network available
 */

import fs from "fs";
import path from "path";
import { fileURLToPath } from "url";

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

interface SnapshotManifest {
  version: string;
  generated_at: string;
  project_type: string;
  customer: string;
  contents: {
    lessons: number;
    cache_entries: number;
    templates: number;
  };
  manifest_version: string;
  offline_capable: boolean;
  optional_api_url?: string;
}

interface CacheResponse {
  query_id: string;
  content: string;
  metadata: {
    tier_recommendation?: string;
    cost_estimate?: string;
    cache_hit_rate?: string;
  };
}

interface QueryOptions {
  projectType?: string;
  customer?: string;
  offline?: boolean;
}

const SNAPSHOT_ROOT = path.join(
  __dirname,
  "brain-snapshot"
);

/**
 * Load snapshot manifest for version checking
 */
async function loadSnapshot(): Promise<SnapshotManifest | null> {
  const manifestPath = path.join(SNAPSHOT_ROOT, "SNAPSHOT-MANIFEST.json");

  if (!fs.existsSync(manifestPath)) {
    console.warn("⚠️  Snapshot manifest not found at", manifestPath);
    return null;
  }

  const manifest = JSON.parse(fs.readFileSync(manifestPath, "utf-8"));
  return manifest;
}

/**
 * Check if snapshot is stale (> 7 days old)
 */
function isSnapshotStale(manifest: SnapshotManifest): boolean {
  const generated = new Date(manifest.generated_at);
  const now = new Date();
  const days = (now.getTime() - generated.getTime()) / (1000 * 60 * 60 * 24);
  return days > 7;
}

/**
 * Query cached response from snapshot
 * @param queryId - ID of cached query (e.g., "01-project-section-draft")
 * @param options - Query options
 * @returns Cached response content + metadata
 */
export async function queryBrain(
  queryId: string,
  options: QueryOptions = {}
): Promise<CacheResponse | null> {
  const manifest = await loadSnapshot();

  if (!manifest) {
    console.error("❌ Brain snapshot not available");
    return null;
  }

  // Validate queryId to prevent path traversal
  if (!/^[a-z0-9-]+$/i.test(queryId)) {
    console.error(`❌ Invalid query ID: ${queryId}`);
    return null;
  }

  // Try local snapshot first (always available)
  const cacheDir = path.join(SNAPSHOT_ROOT, "cache");
  const cacheFile = path.join(cacheDir, `${queryId}.md`);

  // Verify resolved path stays within cache directory (defense in depth)
  if (!path.resolve(cacheFile).startsWith(path.resolve(cacheDir))) {
    console.error(`❌ Path traversal attempt blocked: ${queryId}`);
    return null;
  }

  if (fs.existsSync(cacheFile)) {
    const content = fs.readFileSync(cacheFile, "utf-8");

    // Extract metadata from YAML frontmatter
    const match = content.match(/^---\n([\s\S]*?)\n---/);
    const metadata = match
      ? parseYAML(match[1])
      : {};

    console.log(`✅ Query cache hit: ${queryId} (local snapshot)`);

    return {
      query_id: queryId,
      content,
      metadata: {
        tier_recommendation: metadata.tier_recommendation,
        cost_estimate: metadata.cost_estimate,
        cache_hit_rate: metadata.cache_hit_rate,
      },
    };
  }

  // Snapshot miss — try optional central brain API
  if (!options.offline && manifest.optional_api_url) {
    // SSRF protection: only allow https URLs to known brain domains
    const allowedDomains = [
      "brain.strategix.internal",
      "brain.strategix.co.za",
      "automation-brain.strategix.co.za",
    ];
    let apiUrl: URL;
    try {
      apiUrl = new URL(manifest.optional_api_url);
    } catch {
      console.warn("⚠️  Invalid central brain URL, skipping");
      return null;
    }
    if (
      apiUrl.protocol !== "https:" ||
      !allowedDomains.some((d) => apiUrl.hostname === d)
    ) {
      console.warn(
        `⚠️  Untrusted brain URL ${apiUrl.hostname}, skipping (SSRF guard)`
      );
      return null;
    }

    console.warn(
      `⚠️  Cache miss: ${queryId} not in snapshot. Trying central brain...`
    );

    try {
      const url = new URL(`${apiUrl.toString().replace(/\/$/, "")}/${encodeURIComponent(queryId)}`);
      if (options.projectType) {
        url.searchParams.set("project_type", options.projectType);
      }
      if (options.customer) {
        url.searchParams.set("customer", options.customer);
      }
      const response = await fetch(url.toString(), {
        signal: AbortSignal.timeout(10000),
      });

      if (response.ok) {
        const data = (await response.json()) as CacheResponse;
        // Validate shape before trusting
        if (
          typeof data?.query_id === "string" &&
          typeof data?.content === "string"
        ) {
          console.log(`✅ Query cache hit: ${queryId} (central brain API)`);
          return data;
        }
        console.warn("⚠️  Central brain returned malformed response");
      }
    } catch (err) {
      console.warn("⚠️  Central brain API unavailable, using local snapshot");
    }
  }

  console.error(`❌ Query not found: ${queryId}`);
  return null;
}

/**
 * Get list of relevant lessons for this project
 * @param projectType - Type of project (e.g., "service-desk")
 * @returns Array of lesson files
 */
export async function getLessonsForProjectType(
  projectType: string
): Promise<string[]> {
  const lessonsDir = path.join(SNAPSHOT_ROOT, "lessons");

  if (!fs.existsSync(lessonsDir)) {
    return [];
  }

  const allLessons = fs
    .readdirSync(lessonsDir)
    .filter((f) => f.endsWith(".md"));

  // Filter to:
  // 1. Universal lessons
  // 2. Project-type-specific lessons
  // 3. Customer lessons
  const relevant = allLessons.filter((lesson) => {
    const isUniversal = lesson.includes("universal");
    const isProjectType = lesson.includes(projectType);
    const isGeneral = lesson === "README.md";
    return isUniversal || isProjectType || isGeneral;
  });

  return relevant;
}

/**
 * Get anti-patterns for this project type
 */
export async function getAntiPatterns(
  projectType: string
): Promise<string | null> {
  const antiPatternsFile = path.join(
    SNAPSHOT_ROOT,
    "templates",
    "anti-patterns.md"
  );

  if (!fs.existsSync(antiPatternsFile)) {
    return null;
  }

  const content = fs.readFileSync(antiPatternsFile, "utf-8");
  return content;
}

/**
 * Get project-type template
 */
export async function getProjectTemplate(
  projectType: string
): Promise<string | null> {
  const templateFile = path.join(
    SNAPSHOT_ROOT,
    "templates",
    `${projectType}-template.md`
  );

  if (!fs.existsSync(templateFile)) {
    return null;
  }

  const content = fs.readFileSync(templateFile, "utf-8");
  return content;
}

/**
 * Record bootstrap decision for Phase 6 observability
 */
export async function recordBootstrapDecision(decision: {
  projectType: string;
  customer: string;
  projectName: string;
  decisionsApplied: string[];
  contradictionsResolved: string[];
  lessonsUsed: string[];
  timeMs: number;
  tokenEstimate: number;
}): Promise<void> {
  const decisionLogPath = path.join(
    __dirname,
    "..",
    ".planning",
    "bootstrap-decisions.jsonl"
  );

  const timestamp = new Date().toISOString();
  const logEntry = JSON.stringify({
    timestamp,
    ...decision,
  });

  // Append to decision log (used by Phase 6 observability daemon)
  try {
    fs.appendFileSync(decisionLogPath, logEntry + "\n");
    console.log(`📝 Bootstrap decision recorded: ${decisionLogPath}`);
  } catch (err) {
    console.warn(
      `⚠️  Could not record bootstrap decision: ${(err as Error).message}`
    );
    return;
  }

  // Event-trigger: fire Phase 6 observability daemon detached
  // Continues running after bootstrap exits; failure does not block bootstrap.
  try {
    const { spawn } = await import("child_process");
    const vaultRoot = process.env.AUTOMATION_BRAIN_PATH ||
      path.join(require("os").homedir(), "vaults", "automation-brain");
    const daemonPath = path.join(vaultRoot, "observability", "phase-6-daemon.ts");
    if (fs.existsSync(daemonPath)) {
      const child = spawn("npx", ["ts-node", daemonPath], {
        cwd: vaultRoot,
        detached: true,
        stdio: "ignore",
        env: process.env,
      });
      child.unref();
      console.log(`🧠 Phase 6 daemon triggered (event-driven)`);
    }
  } catch (err) {
    console.warn(`⚠️  Could not trigger Phase 6: ${(err as Error).message}`);
  }
}

/**
 * Simple YAML parser for frontmatter metadata
 */
function parseYAML(yaml: string): Record<string, string> {
  const result: Record<string, string> = {};
  const lines = yaml.split("\n");

  for (const line of lines) {
    const match = line.match(/^\s*(.+?):\s*(.+?)\s*$/);
    if (match) {
      const [, key, value] = match;
      result[key] = value.replace(/^["']|["']$/g, ""); // Remove quotes
    }
  }

  return result;
}

/**
 * Initialize brain query on project startup
 */
export async function initializeBrain(): Promise<{
  status: "ready" | "degraded" | "offline";
  snapshot: SnapshotManifest | null;
  message: string;
}> {
  const manifest = await loadSnapshot();

  if (!manifest) {
    return {
      status: "offline",
      snapshot: null,
      message:
        "⚠️  Brain snapshot not found. Bootstrap will proceed without brain guidance.",
    };
  }

  const stale = isSnapshotStale(manifest);

  if (stale) {
    return {
      status: "degraded",
      snapshot: manifest,
      message: `⚠️  Brain snapshot is ${Math.floor((new Date().getTime() - new Date(manifest.generated_at).getTime()) / (1000 * 60 * 60 * 24))} days old. Consider running: brain-sync`,
    };
  }

  return {
    status: "ready",
    snapshot: manifest,
    message: `✅ Brain ready. ${manifest.contents.cache_entries} cached queries, ${manifest.contents.lessons} lessons available.`,
  };
}

/**
 * Sync this project's brain snapshot from the central vault.
 * Pulls latest from GitHub, copies lessons/cache/templates into local snapshot.
 *
 * Returns true on success, false if vault unreachable.
 */
export async function syncBrain(): Promise<{
  success: boolean;
  vaultCommit?: string;
  lessons?: number;
  cache?: number;
  templates?: number;
  message: string;
}> {
  const { spawnSync } = await import("child_process");
  const os = await import("os");
  const vaultPath =
    process.env.AUTOMATION_BRAIN_PATH ||
    path.join(os.homedir(), "vaults", "automation-brain");
  const syncScript = path.join(vaultPath, "scripts", "brain-sync.sh");

  if (!fs.existsSync(syncScript)) {
    return {
      success: false,
      message: `Brain sync script not found at ${syncScript}`,
    };
  }

  // Project root is parent of .parent-automation
  const projectRoot = path.resolve(__dirname, "..");

  const result = spawnSync("bash", [syncScript, projectRoot], {
    encoding: "utf-8",
    timeout: 60000,
  });

  if (result.status !== 0) {
    return {
      success: false,
      message: `Sync failed: ${result.stderr || result.stdout}`,
    };
  }

  // Read updated manifest
  const manifest = await loadSnapshot();
  return {
    success: true,
    vaultCommit: manifest?.version,
    lessons: manifest?.contents.lessons,
    cache: manifest?.contents.cache_entries,
    templates: manifest?.contents.templates,
    message: "Brain sync complete",
  };
}

// Export convenience functions
export const brain = {
  queryCache: queryBrain,
  getLessons: getLessonsForProjectType,
  getAntiPatterns,
  getTemplate: getProjectTemplate,
  recordDecision: recordBootstrapDecision,
  initialize: initializeBrain,
  sync: syncBrain,
};
