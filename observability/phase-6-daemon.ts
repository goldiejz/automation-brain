/**
 * Phase 6: Observability Daemon — Cross-Project Pattern Detection
 *
 * Reads bootstrap decision logs from all projects, detects patterns, updates lesson effectiveness.
 * Runs weekly to feed self-improving loop.
 *
 * Usage (from ~/vaults/ark/):
 *   npx ts-node observability/phase-6-daemon.ts
 */

import fs from "fs";
import path from "path";

interface BootstrapDecision {
  timestamp: string;
  projectType: string;
  customer: string;
  projectName: string;
  decisionsApplied: string[];
  contradictionsResolved: string[];
  lessonsUsed: string[];
  timeMs: number;
  tokenEstimate: number;
}

interface ProjectPattern {
  projectRepo: string;
  decisions: string[];
  contradictions: string[];
  lessons: string[];
  timeMs: number;
  tokens: number;
}

interface CrossProjectPattern {
  pattern: string;
  occurrences: number;
  affectedRepos: string[];
  averageTimeMs: number;
  averageTokens: number;
  examples: BootstrapDecision[];
}

interface LessonEffectiveness {
  lessonId: string;
  preventedIncidents: number;
  violationsSince: number;
  affectedRepos: string[];
  firstSeen: string;
  lastUpdated: string;
  effectiveness: number; // Prevented / (Prevented + Violations)
}

async function loadBootstrapLogs(): Promise<BootstrapDecision[]> {
  const logs: BootstrapDecision[] = [];

  // Check three repos
  const repos = [
    "/Users/jongoldberg/code/strategix-servicedesk",
    "/Users/jongoldberg/code/strategix-crm",
    "/Users/jongoldberg/code/strategix-ioc",
  ];

  for (const repo of repos) {
    const logPath = path.join(repo, ".planning", "bootstrap-decisions.jsonl");

    if (fs.existsSync(logPath)) {
      const content = fs.readFileSync(logPath, "utf-8");
      const lines = content.split("\n").filter((l) => l.trim());

      for (const line of lines) {
        try {
          const parsed: unknown = JSON.parse(line);
          if (
            typeof parsed === "object" &&
            parsed !== null &&
            "projectName" in parsed &&
            "customer" in parsed &&
            "projectType" in parsed &&
            Array.isArray((parsed as BootstrapDecision).decisionsApplied) &&
            Array.isArray((parsed as BootstrapDecision).contradictionsResolved) &&
            Array.isArray((parsed as BootstrapDecision).lessonsUsed)
          ) {
            logs.push(parsed as BootstrapDecision);
          } else {
            console.warn(`Skipping malformed decision (missing required fields)`);
          }
        } catch (e) {
          console.warn(`Failed to parse decision log line: ${line.substring(0, 80)}...`);
        }
      }
    }
  }

  console.log(`✅ Loaded ${logs.length} bootstrap decisions from ${repos.length} repos\n`);
  return logs;
}

function detectPatterns(logs: BootstrapDecision[]): CrossProjectPattern[] {
  const patterns = new Map<string, CrossProjectPattern>();

  // Pattern 1: Which decisions are universal (appear in 80%+ of projects)?
  const decisionFreq = new Map<string, { count: number; repos: Set<string> }>();

  for (const log of logs) {
    const repo = log.projectName.toLowerCase();
    for (const decision of log.decisionsApplied) {
      const key = decision;
      if (!decisionFreq.has(key)) {
        decisionFreq.set(key, { count: 0, repos: new Set() });
      }
      const freq = decisionFreq.get(key)!;
      freq.count++;
      freq.repos.add(repo);
    }
  }

  // Detect universal decisions (80%+)
  const totalProjects = new Set(logs.map((l) => l.projectName)).size;
  const threshold = Math.ceil(totalProjects * 0.8);

  for (const [decision, freq] of decisionFreq.entries()) {
    if (freq.count >= threshold) {
      patterns.set(`universal-decision:${decision}`, {
        pattern: `Universal Decision: ${decision}`,
        occurrences: freq.count,
        affectedRepos: Array.from(freq.repos),
        averageTimeMs: 0,
        averageTokens: 0,
        examples: logs.filter((l) => l.decisionsApplied.includes(decision)),
      });
    }
  }

  // Pattern 2: Which lessons prevent the most mistakes?
  const lessonVsContradiction = new Map<
    string,
    { prevented: number; violated: number }
  >();

  for (const log of logs) {
    // If a contradiction was found in a project WITHOUT this lesson, it's a violation
    for (const lesson of log.lessonsUsed) {
      if (!lessonVsContradiction.has(lesson)) {
        lessonVsContradiction.set(lesson, { prevented: 0, violated: 0 });
      }
      lessonVsContradiction.get(lesson)!.prevented++;
    }

    // For contradictions found: were they preventable by a lesson we know?
    for (const contradiction of log.contradictionsResolved) {
      // Try to map contradiction to a lesson (simple heuristic: L-NNN in the contradiction)
      const match = contradiction.match(/L-(\d+)/);
      if (match) {
        const lessonId = `L-${match[1]}`;
        if (!lessonVsContradiction.has(lessonId)) {
          lessonVsContradiction.set(lessonId, { prevented: 0, violated: 0 });
        }
        lessonVsContradiction.get(lessonId)!.violated++;
      }
    }
  }

  for (const [lesson, stats] of lessonVsContradiction.entries()) {
    if (stats.prevented + stats.violated > 1) {
      const effectiveness = stats.prevented / (stats.prevented + stats.violated);
      if (effectiveness >= 0.6) {
        // 60%+ effective
        patterns.set(`lesson-effectiveness:${lesson}`, {
          pattern: `Lesson Effectiveness: ${lesson} (${(effectiveness * 100).toFixed(0)}% effective)`,
          occurrences: stats.prevented + stats.violated,
          affectedRepos: Array.from(
            new Set(logs.filter((l) => l.lessonsUsed.includes(lesson)).map((l) => l.customer))
          ),
          averageTimeMs: 0,
          averageTokens: 0,
          examples: logs.filter((l) => l.lessonsUsed.includes(lesson)),
        });
      }
    }
  }

  // Pattern 3: Token cost optimization (which projects are most efficient?)
  const avgTokensByProject = new Map<string, number[]>();
  for (const log of logs) {
    const key = log.projectType;
    if (!avgTokensByProject.has(key)) {
      avgTokensByProject.set(key, []);
    }
    avgTokensByProject.get(key)!.push(log.tokenEstimate);
  }

  for (const [projectType, tokens] of avgTokensByProject.entries()) {
    const avg = tokens.reduce((a, b) => a + b, 0) / tokens.length;
    patterns.set(`token-efficiency:${projectType}`, {
      pattern: `Token Efficiency: ${projectType} projects avg ${Math.round(avg)} tokens`,
      occurrences: tokens.length,
      affectedRepos: Array.from(
        new Set(logs.filter((l) => l.projectType === projectType).map((l) => l.customer))
      ),
      averageTimeMs: 0,
      averageTokens: avg,
      examples: logs.filter((l) => l.projectType === projectType),
    });
  }

  return Array.from(patterns.values());
}

function generateLessonEffectivenessReport(
  logs: BootstrapDecision[]
): LessonEffectiveness[] {
  const lessons = new Map<string, LessonEffectiveness>();

  const allLessons = new Set<string>();
  for (const log of logs) {
    log.lessonsUsed.forEach((l) => allLessons.add(l));
  }

  for (const lesson of allLessons) {
    const usedIn = logs.filter((l) => l.lessonsUsed.includes(lesson));
    const preventedCount = usedIn.length;

    // Violations: contradictions in projects that DON'T use this lesson
    const violations = logs
      .filter((l) => !l.lessonsUsed.includes(lesson))
      .filter((l) => l.contradictionsResolved.length > 0).length;

    const effectiveness =
      preventedCount / (preventedCount + Math.max(violations, 1));

    lessons.set(lesson, {
      lessonId: lesson,
      preventedIncidents: preventedCount,
      violationsSince: violations,
      affectedRepos: Array.from(new Set(usedIn.map((l) => l.customer))),
      firstSeen: usedIn.length > 0 ? usedIn[0].timestamp : new Date().toISOString(),
      lastUpdated: new Date().toISOString(),
      effectiveness,
    });
  }

  return Array.from(lessons.values()).sort(
    (a, b) => b.effectiveness - a.effectiveness
  );
}

async function updateBrainDocuments(
  patterns: CrossProjectPattern[],
  lessons: LessonEffectiveness[]
) {
  const brainRoot = "/Users/jongoldberg/vaults/automation-brain";

  // Update cross-customer-insights.md
  const insightsPath = path.join(
    brainRoot,
    "observability",
    "cross-customer-insights.md"
  );
  const insightsContent = `# Cross-Customer Insights

**Last updated:** ${new Date().toISOString()}

## Universal Patterns (80%+ of projects)

${patterns
  .filter((p) => p.pattern.includes("Universal"))
  .map(
    (p) =>
      `### ${p.pattern}
- Occurrences: ${p.occurrences} projects
- Affected repos: ${p.affectedRepos.join(", ")}
`
  )
  .join("\n")}

## Token Cost by Project Type

${patterns
  .filter((p) => p.pattern.includes("Token Efficiency"))
  .map(
    (p) =>
      `### ${p.pattern}
- Samples: ${p.occurrences} projects
- Affected customers: ${p.affectedRepos.join(", ")}
`
  )
  .join("\n")}

## Lesson Effectiveness Summary

${lessons
  .slice(0, 10)
  .map(
    (l) =>
      `### ${l.lessonId} (${(l.effectiveness * 100).toFixed(0)}% effective)
- Prevented incidents: ${l.preventedIncidents}
- Violations: ${l.violationsSince}
- Used by: ${l.affectedRepos.join(", ")}
`
  )
  .join("\n")}

---

## Raw Pattern Data

\`\`\`json
${JSON.stringify(patterns, null, 2)}
\`\`\`
`;

  atomicWrite(insightsPath, insightsContent);
  console.log(`✅ Updated ${insightsPath}`);

  // Update lesson-effectiveness.md
  const effectivenessPath = path.join(
    brainRoot,
    "observability",
    "lesson-effectiveness.md"
  );
  const effectivenessContent = `# Lesson Effectiveness Tracking

**Last updated:** ${new Date().toISOString()}

## Effectiveness Scores (sorted by effectiveness)

${lessons
  .map(
    (l) => `
### ${l.lessonId}
- **Effectiveness:** ${(l.effectiveness * 100).toFixed(1)}%
- **Prevented incidents:** ${l.preventedIncidents}
- **Violations:** ${l.violationsSince}
- **Affected customers:** ${l.affectedRepos.join(", ")}
- **First seen:** ${l.firstSeen}
`
  )
  .join("\n")}

---

## Interpretation

- **80%+:** Highly effective, widely applicable
- **60-80%:** Effective in most cases
- **40-60%:** Mixed results, needs refinement
- **<40%:** Consider deprecating or reframing

## False Positives to Watch

Lessons with low violation counts (n < 3) may have artificially high scores due to sample size.
`;

  atomicWrite(effectivenessPath, effectivenessContent);
  console.log(`✅ Updated ${effectivenessPath}`);
}

/**
 * Write file atomically via temp + rename (POSIX rename is atomic).
 * Prevents corruption if process is interrupted mid-write or two daemons run concurrently.
 */
function atomicWrite(targetPath: string, content: string): void {
  const tmpPath = `${targetPath}.${process.pid}.tmp`;
  fs.writeFileSync(tmpPath, content);
  fs.renameSync(tmpPath, targetPath);
}

async function run() {
  console.log("🧠 Phase 6 Observability Daemon — Cross-Project Pattern Detection\n");

  const logs = await loadBootstrapLogs();
  if (logs.length === 0) {
    console.log("⚠️  No bootstrap decision logs found. Phase 6 daemon offline.");
    return;
  }

  console.log("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━");
  console.log("STEP 1: Detect Cross-Project Patterns");
  const patterns = detectPatterns(logs);
  console.log(`✅ Found ${patterns.length} significant patterns\n`);

  patterns.forEach((p) => {
    console.log(`  • ${p.pattern} (${p.occurrences} occurrences)`);
  });

  console.log("");
  console.log("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━");
  console.log("STEP 2: Generate Lesson Effectiveness Report");
  const lessons = generateLessonEffectivenessReport(logs);
  console.log(`✅ Tracked effectiveness for ${lessons.length} lessons\n`);

  lessons.slice(0, 5).forEach((l) => {
    console.log(
      `  • ${l.lessonId}: ${(l.effectiveness * 100).toFixed(0)}% (prevented ${l.preventedIncidents}, violated ${l.violationsSince})`
    );
  });

  console.log("");
  console.log("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━");
  console.log("STEP 3: Update Brain Documents");
  await updateBrainDocuments(patterns, lessons);
  console.log("");

  console.log("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━");
  console.log("✅ OBSERVABILITY DAEMON COMPLETE\n");
  console.log(`Summary:`);
  console.log(`  - Decisions analysed: ${logs.length}`);
  console.log(`  - Patterns detected: ${patterns.length}`);
  console.log(`  - Lessons tracked: ${lessons.length}`);
  console.log(`  - Most effective lesson: ${lessons[0]?.lessonId} (${(lessons[0]?.effectiveness * 100).toFixed(0)}%)`);
  console.log("");
  console.log("Next cycle: Phase 7 tier resolver optimization\n");
}

run().catch((err) => {
  console.error("❌ Daemon failed:", err);
  process.exit(1);
});
