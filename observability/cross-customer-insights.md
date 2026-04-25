# Cross-Customer Insights

**Last updated:** 2026-04-25T20:43:41.798Z

## Universal Patterns (80%+ of projects)

### Universal Decision: purpose-resolved
- Occurrences: 5 projects
- Affected repos: test service desk

### Universal Decision: project-section-cached
- Occurrences: 4 projects
- Affected repos: test service desk

### Universal Decision: scope-cached
- Occurrences: 4 projects
- Affected repos: test service desk

### Universal Decision: conventions-cached
- Occurrences: 4 projects
- Affected repos: test service desk

### Universal Decision: rbac-cached
- Occurrences: 4 projects
- Affected repos: test service desk

### Universal Decision: steps-6-10-cached
- Occurrences: 5 projects
- Affected repos: test service desk

### Universal Decision: project-section-sonnet
- Occurrences: 1 projects
- Affected repos: test service desk

### Universal Decision: scope-sonnet
- Occurrences: 1 projects
- Affected repos: test service desk

### Universal Decision: conventions-sonnet
- Occurrences: 1 projects
- Affected repos: test service desk

### Universal Decision: rbac-fresh
- Occurrences: 1 projects
- Affected repos: test service desk


## Token Cost by Project Type

### Token Efficiency: service-desk projects avg 9000 tokens
- Samples: 5 projects
- Affected customers: strategix


## Lesson Effectiveness Summary

### L-018 (80% effective)
- Prevented incidents: 4
- Violations: 0
- Used by: strategix

### L-021 (80% effective)
- Prevented incidents: 4
- Violations: 0
- Used by: strategix

### L-020 (80% effective)
- Prevented incidents: 4
- Violations: 0
- Used by: strategix


---

## Raw Pattern Data

```json
[
  {
    "pattern": "Universal Decision: purpose-resolved",
    "occurrences": 5,
    "affectedRepos": [
      "test service desk"
    ],
    "averageTimeMs": 0,
    "averageTokens": 0,
    "examples": [
      {
        "timestamp": "2026-04-25T15:59:09.836Z",
        "projectType": "service-desk",
        "customer": "strategix",
        "projectName": "Test Service Desk",
        "decisionsApplied": [
          "purpose-resolved",
          "project-section-cached",
          "scope-cached",
          "conventions-cached",
          "rbac-cached",
          "steps-6-10-cached"
        ],
        "contradictionsResolved": [],
        "lessonsUsed": [
          "L-018",
          "L-021",
          "L-020",
          "L-018"
        ],
        "timeMs": 2,
        "tokenEstimate": 7400
      },
      {
        "timestamp": "2026-04-25T15:59:53.860Z",
        "projectType": "service-desk",
        "customer": "strategix",
        "projectName": "Test Service Desk",
        "decisionsApplied": [
          "purpose-resolved",
          "project-section-cached",
          "scope-cached",
          "conventions-cached",
          "rbac-cached",
          "steps-6-10-cached"
        ],
        "contradictionsResolved": [],
        "lessonsUsed": [
          "L-018",
          "L-021",
          "L-020",
          "L-018"
        ],
        "timeMs": 2,
        "tokenEstimate": 7400
      },
      {
        "timestamp": "2026-04-25T20:42:24.469Z",
        "projectType": "service-desk",
        "customer": "strategix",
        "projectName": "Test Service Desk",
        "decisionsApplied": [
          "purpose-resolved",
          "project-section-sonnet",
          "scope-sonnet",
          "conventions-sonnet",
          "rbac-fresh",
          "steps-6-10-cached"
        ],
        "contradictionsResolved": [],
        "lessonsUsed": [],
        "timeMs": 1,
        "tokenEstimate": 15400
      },
      {
        "timestamp": "2026-04-25T20:43:34.454Z",
        "projectType": "service-desk",
        "customer": "strategix",
        "projectName": "Test Service Desk",
        "decisionsApplied": [
          "purpose-resolved",
          "project-section-cached",
          "scope-cached",
          "conventions-cached",
          "rbac-cached",
          "steps-6-10-cached"
        ],
        "contradictionsResolved": [],
        "lessonsUsed": [
          "L-018",
          "L-021",
          "L-020",
          "L-018"
        ],
        "timeMs": 3,
        "tokenEstimate": 7400
      },
      {
        "timestamp": "2026-04-25T20:43:41.181Z",
        "projectType": "service-desk",
        "customer": "strategix",
        "projectName": "Test Service Desk",
        "decisionsApplied": [
          "purpose-resolved",
          "project-section-cached",
          "scope-cached",
          "conventions-cached",
          "rbac-cached",
          "steps-6-10-cached"
        ],
        "contradictionsResolved": [],
        "lessonsUsed": [
          "L-018",
          "L-021",
          "L-020",
          "L-018"
        ],
        "timeMs": 1,
        "tokenEstimate": 7400
      }
    ]
  },
  {
    "pattern": "Universal Decision: project-section-cached",
    "occurrences": 4,
    "affectedRepos": [
      "test service desk"
    ],
    "averageTimeMs": 0,
    "averageTokens": 0,
    "examples": [
      {
        "timestamp": "2026-04-25T15:59:09.836Z",
        "projectType": "service-desk",
        "customer": "strategix",
        "projectName": "Test Service Desk",
        "decisionsApplied": [
          "purpose-resolved",
          "project-section-cached",
          "scope-cached",
          "conventions-cached",
          "rbac-cached",
          "steps-6-10-cached"
        ],
        "contradictionsResolved": [],
        "lessonsUsed": [
          "L-018",
          "L-021",
          "L-020",
          "L-018"
        ],
        "timeMs": 2,
        "tokenEstimate": 7400
      },
      {
        "timestamp": "2026-04-25T15:59:53.860Z",
        "projectType": "service-desk",
        "customer": "strategix",
        "projectName": "Test Service Desk",
        "decisionsApplied": [
          "purpose-resolved",
          "project-section-cached",
          "scope-cached",
          "conventions-cached",
          "rbac-cached",
          "steps-6-10-cached"
        ],
        "contradictionsResolved": [],
        "lessonsUsed": [
          "L-018",
          "L-021",
          "L-020",
          "L-018"
        ],
        "timeMs": 2,
        "tokenEstimate": 7400
      },
      {
        "timestamp": "2026-04-25T20:43:34.454Z",
        "projectType": "service-desk",
        "customer": "strategix",
        "projectName": "Test Service Desk",
        "decisionsApplied": [
          "purpose-resolved",
          "project-section-cached",
          "scope-cached",
          "conventions-cached",
          "rbac-cached",
          "steps-6-10-cached"
        ],
        "contradictionsResolved": [],
        "lessonsUsed": [
          "L-018",
          "L-021",
          "L-020",
          "L-018"
        ],
        "timeMs": 3,
        "tokenEstimate": 7400
      },
      {
        "timestamp": "2026-04-25T20:43:41.181Z",
        "projectType": "service-desk",
        "customer": "strategix",
        "projectName": "Test Service Desk",
        "decisionsApplied": [
          "purpose-resolved",
          "project-section-cached",
          "scope-cached",
          "conventions-cached",
          "rbac-cached",
          "steps-6-10-cached"
        ],
        "contradictionsResolved": [],
        "lessonsUsed": [
          "L-018",
          "L-021",
          "L-020",
          "L-018"
        ],
        "timeMs": 1,
        "tokenEstimate": 7400
      }
    ]
  },
  {
    "pattern": "Universal Decision: scope-cached",
    "occurrences": 4,
    "affectedRepos": [
      "test service desk"
    ],
    "averageTimeMs": 0,
    "averageTokens": 0,
    "examples": [
      {
        "timestamp": "2026-04-25T15:59:09.836Z",
        "projectType": "service-desk",
        "customer": "strategix",
        "projectName": "Test Service Desk",
        "decisionsApplied": [
          "purpose-resolved",
          "project-section-cached",
          "scope-cached",
          "conventions-cached",
          "rbac-cached",
          "steps-6-10-cached"
        ],
        "contradictionsResolved": [],
        "lessonsUsed": [
          "L-018",
          "L-021",
          "L-020",
          "L-018"
        ],
        "timeMs": 2,
        "tokenEstimate": 7400
      },
      {
        "timestamp": "2026-04-25T15:59:53.860Z",
        "projectType": "service-desk",
        "customer": "strategix",
        "projectName": "Test Service Desk",
        "decisionsApplied": [
          "purpose-resolved",
          "project-section-cached",
          "scope-cached",
          "conventions-cached",
          "rbac-cached",
          "steps-6-10-cached"
        ],
        "contradictionsResolved": [],
        "lessonsUsed": [
          "L-018",
          "L-021",
          "L-020",
          "L-018"
        ],
        "timeMs": 2,
        "tokenEstimate": 7400
      },
      {
        "timestamp": "2026-04-25T20:43:34.454Z",
        "projectType": "service-desk",
        "customer": "strategix",
        "projectName": "Test Service Desk",
        "decisionsApplied": [
          "purpose-resolved",
          "project-section-cached",
          "scope-cached",
          "conventions-cached",
          "rbac-cached",
          "steps-6-10-cached"
        ],
        "contradictionsResolved": [],
        "lessonsUsed": [
          "L-018",
          "L-021",
          "L-020",
          "L-018"
        ],
        "timeMs": 3,
        "tokenEstimate": 7400
      },
      {
        "timestamp": "2026-04-25T20:43:41.181Z",
        "projectType": "service-desk",
        "customer": "strategix",
        "projectName": "Test Service Desk",
        "decisionsApplied": [
          "purpose-resolved",
          "project-section-cached",
          "scope-cached",
          "conventions-cached",
          "rbac-cached",
          "steps-6-10-cached"
        ],
        "contradictionsResolved": [],
        "lessonsUsed": [
          "L-018",
          "L-021",
          "L-020",
          "L-018"
        ],
        "timeMs": 1,
        "tokenEstimate": 7400
      }
    ]
  },
  {
    "pattern": "Universal Decision: conventions-cached",
    "occurrences": 4,
    "affectedRepos": [
      "test service desk"
    ],
    "averageTimeMs": 0,
    "averageTokens": 0,
    "examples": [
      {
        "timestamp": "2026-04-25T15:59:09.836Z",
        "projectType": "service-desk",
        "customer": "strategix",
        "projectName": "Test Service Desk",
        "decisionsApplied": [
          "purpose-resolved",
          "project-section-cached",
          "scope-cached",
          "conventions-cached",
          "rbac-cached",
          "steps-6-10-cached"
        ],
        "contradictionsResolved": [],
        "lessonsUsed": [
          "L-018",
          "L-021",
          "L-020",
          "L-018"
        ],
        "timeMs": 2,
        "tokenEstimate": 7400
      },
      {
        "timestamp": "2026-04-25T15:59:53.860Z",
        "projectType": "service-desk",
        "customer": "strategix",
        "projectName": "Test Service Desk",
        "decisionsApplied": [
          "purpose-resolved",
          "project-section-cached",
          "scope-cached",
          "conventions-cached",
          "rbac-cached",
          "steps-6-10-cached"
        ],
        "contradictionsResolved": [],
        "lessonsUsed": [
          "L-018",
          "L-021",
          "L-020",
          "L-018"
        ],
        "timeMs": 2,
        "tokenEstimate": 7400
      },
      {
        "timestamp": "2026-04-25T20:43:34.454Z",
        "projectType": "service-desk",
        "customer": "strategix",
        "projectName": "Test Service Desk",
        "decisionsApplied": [
          "purpose-resolved",
          "project-section-cached",
          "scope-cached",
          "conventions-cached",
          "rbac-cached",
          "steps-6-10-cached"
        ],
        "contradictionsResolved": [],
        "lessonsUsed": [
          "L-018",
          "L-021",
          "L-020",
          "L-018"
        ],
        "timeMs": 3,
        "tokenEstimate": 7400
      },
      {
        "timestamp": "2026-04-25T20:43:41.181Z",
        "projectType": "service-desk",
        "customer": "strategix",
        "projectName": "Test Service Desk",
        "decisionsApplied": [
          "purpose-resolved",
          "project-section-cached",
          "scope-cached",
          "conventions-cached",
          "rbac-cached",
          "steps-6-10-cached"
        ],
        "contradictionsResolved": [],
        "lessonsUsed": [
          "L-018",
          "L-021",
          "L-020",
          "L-018"
        ],
        "timeMs": 1,
        "tokenEstimate": 7400
      }
    ]
  },
  {
    "pattern": "Universal Decision: rbac-cached",
    "occurrences": 4,
    "affectedRepos": [
      "test service desk"
    ],
    "averageTimeMs": 0,
    "averageTokens": 0,
    "examples": [
      {
        "timestamp": "2026-04-25T15:59:09.836Z",
        "projectType": "service-desk",
        "customer": "strategix",
        "projectName": "Test Service Desk",
        "decisionsApplied": [
          "purpose-resolved",
          "project-section-cached",
          "scope-cached",
          "conventions-cached",
          "rbac-cached",
          "steps-6-10-cached"
        ],
        "contradictionsResolved": [],
        "lessonsUsed": [
          "L-018",
          "L-021",
          "L-020",
          "L-018"
        ],
        "timeMs": 2,
        "tokenEstimate": 7400
      },
      {
        "timestamp": "2026-04-25T15:59:53.860Z",
        "projectType": "service-desk",
        "customer": "strategix",
        "projectName": "Test Service Desk",
        "decisionsApplied": [
          "purpose-resolved",
          "project-section-cached",
          "scope-cached",
          "conventions-cached",
          "rbac-cached",
          "steps-6-10-cached"
        ],
        "contradictionsResolved": [],
        "lessonsUsed": [
          "L-018",
          "L-021",
          "L-020",
          "L-018"
        ],
        "timeMs": 2,
        "tokenEstimate": 7400
      },
      {
        "timestamp": "2026-04-25T20:43:34.454Z",
        "projectType": "service-desk",
        "customer": "strategix",
        "projectName": "Test Service Desk",
        "decisionsApplied": [
          "purpose-resolved",
          "project-section-cached",
          "scope-cached",
          "conventions-cached",
          "rbac-cached",
          "steps-6-10-cached"
        ],
        "contradictionsResolved": [],
        "lessonsUsed": [
          "L-018",
          "L-021",
          "L-020",
          "L-018"
        ],
        "timeMs": 3,
        "tokenEstimate": 7400
      },
      {
        "timestamp": "2026-04-25T20:43:41.181Z",
        "projectType": "service-desk",
        "customer": "strategix",
        "projectName": "Test Service Desk",
        "decisionsApplied": [
          "purpose-resolved",
          "project-section-cached",
          "scope-cached",
          "conventions-cached",
          "rbac-cached",
          "steps-6-10-cached"
        ],
        "contradictionsResolved": [],
        "lessonsUsed": [
          "L-018",
          "L-021",
          "L-020",
          "L-018"
        ],
        "timeMs": 1,
        "tokenEstimate": 7400
      }
    ]
  },
  {
    "pattern": "Universal Decision: steps-6-10-cached",
    "occurrences": 5,
    "affectedRepos": [
      "test service desk"
    ],
    "averageTimeMs": 0,
    "averageTokens": 0,
    "examples": [
      {
        "timestamp": "2026-04-25T15:59:09.836Z",
        "projectType": "service-desk",
        "customer": "strategix",
        "projectName": "Test Service Desk",
        "decisionsApplied": [
          "purpose-resolved",
          "project-section-cached",
          "scope-cached",
          "conventions-cached",
          "rbac-cached",
          "steps-6-10-cached"
        ],
        "contradictionsResolved": [],
        "lessonsUsed": [
          "L-018",
          "L-021",
          "L-020",
          "L-018"
        ],
        "timeMs": 2,
        "tokenEstimate": 7400
      },
      {
        "timestamp": "2026-04-25T15:59:53.860Z",
        "projectType": "service-desk",
        "customer": "strategix",
        "projectName": "Test Service Desk",
        "decisionsApplied": [
          "purpose-resolved",
          "project-section-cached",
          "scope-cached",
          "conventions-cached",
          "rbac-cached",
          "steps-6-10-cached"
        ],
        "contradictionsResolved": [],
        "lessonsUsed": [
          "L-018",
          "L-021",
          "L-020",
          "L-018"
        ],
        "timeMs": 2,
        "tokenEstimate": 7400
      },
      {
        "timestamp": "2026-04-25T20:42:24.469Z",
        "projectType": "service-desk",
        "customer": "strategix",
        "projectName": "Test Service Desk",
        "decisionsApplied": [
          "purpose-resolved",
          "project-section-sonnet",
          "scope-sonnet",
          "conventions-sonnet",
          "rbac-fresh",
          "steps-6-10-cached"
        ],
        "contradictionsResolved": [],
        "lessonsUsed": [],
        "timeMs": 1,
        "tokenEstimate": 15400
      },
      {
        "timestamp": "2026-04-25T20:43:34.454Z",
        "projectType": "service-desk",
        "customer": "strategix",
        "projectName": "Test Service Desk",
        "decisionsApplied": [
          "purpose-resolved",
          "project-section-cached",
          "scope-cached",
          "conventions-cached",
          "rbac-cached",
          "steps-6-10-cached"
        ],
        "contradictionsResolved": [],
        "lessonsUsed": [
          "L-018",
          "L-021",
          "L-020",
          "L-018"
        ],
        "timeMs": 3,
        "tokenEstimate": 7400
      },
      {
        "timestamp": "2026-04-25T20:43:41.181Z",
        "projectType": "service-desk",
        "customer": "strategix",
        "projectName": "Test Service Desk",
        "decisionsApplied": [
          "purpose-resolved",
          "project-section-cached",
          "scope-cached",
          "conventions-cached",
          "rbac-cached",
          "steps-6-10-cached"
        ],
        "contradictionsResolved": [],
        "lessonsUsed": [
          "L-018",
          "L-021",
          "L-020",
          "L-018"
        ],
        "timeMs": 1,
        "tokenEstimate": 7400
      }
    ]
  },
  {
    "pattern": "Universal Decision: project-section-sonnet",
    "occurrences": 1,
    "affectedRepos": [
      "test service desk"
    ],
    "averageTimeMs": 0,
    "averageTokens": 0,
    "examples": [
      {
        "timestamp": "2026-04-25T20:42:24.469Z",
        "projectType": "service-desk",
        "customer": "strategix",
        "projectName": "Test Service Desk",
        "decisionsApplied": [
          "purpose-resolved",
          "project-section-sonnet",
          "scope-sonnet",
          "conventions-sonnet",
          "rbac-fresh",
          "steps-6-10-cached"
        ],
        "contradictionsResolved": [],
        "lessonsUsed": [],
        "timeMs": 1,
        "tokenEstimate": 15400
      }
    ]
  },
  {
    "pattern": "Universal Decision: scope-sonnet",
    "occurrences": 1,
    "affectedRepos": [
      "test service desk"
    ],
    "averageTimeMs": 0,
    "averageTokens": 0,
    "examples": [
      {
        "timestamp": "2026-04-25T20:42:24.469Z",
        "projectType": "service-desk",
        "customer": "strategix",
        "projectName": "Test Service Desk",
        "decisionsApplied": [
          "purpose-resolved",
          "project-section-sonnet",
          "scope-sonnet",
          "conventions-sonnet",
          "rbac-fresh",
          "steps-6-10-cached"
        ],
        "contradictionsResolved": [],
        "lessonsUsed": [],
        "timeMs": 1,
        "tokenEstimate": 15400
      }
    ]
  },
  {
    "pattern": "Universal Decision: conventions-sonnet",
    "occurrences": 1,
    "affectedRepos": [
      "test service desk"
    ],
    "averageTimeMs": 0,
    "averageTokens": 0,
    "examples": [
      {
        "timestamp": "2026-04-25T20:42:24.469Z",
        "projectType": "service-desk",
        "customer": "strategix",
        "projectName": "Test Service Desk",
        "decisionsApplied": [
          "purpose-resolved",
          "project-section-sonnet",
          "scope-sonnet",
          "conventions-sonnet",
          "rbac-fresh",
          "steps-6-10-cached"
        ],
        "contradictionsResolved": [],
        "lessonsUsed": [],
        "timeMs": 1,
        "tokenEstimate": 15400
      }
    ]
  },
  {
    "pattern": "Universal Decision: rbac-fresh",
    "occurrences": 1,
    "affectedRepos": [
      "test service desk"
    ],
    "averageTimeMs": 0,
    "averageTokens": 0,
    "examples": [
      {
        "timestamp": "2026-04-25T20:42:24.469Z",
        "projectType": "service-desk",
        "customer": "strategix",
        "projectName": "Test Service Desk",
        "decisionsApplied": [
          "purpose-resolved",
          "project-section-sonnet",
          "scope-sonnet",
          "conventions-sonnet",
          "rbac-fresh",
          "steps-6-10-cached"
        ],
        "contradictionsResolved": [],
        "lessonsUsed": [],
        "timeMs": 1,
        "tokenEstimate": 15400
      }
    ]
  },
  {
    "pattern": "Lesson Effectiveness: L-018 (100% effective)",
    "occurrences": 8,
    "affectedRepos": [
      "strategix"
    ],
    "averageTimeMs": 0,
    "averageTokens": 0,
    "examples": [
      {
        "timestamp": "2026-04-25T15:59:09.836Z",
        "projectType": "service-desk",
        "customer": "strategix",
        "projectName": "Test Service Desk",
        "decisionsApplied": [
          "purpose-resolved",
          "project-section-cached",
          "scope-cached",
          "conventions-cached",
          "rbac-cached",
          "steps-6-10-cached"
        ],
        "contradictionsResolved": [],
        "lessonsUsed": [
          "L-018",
          "L-021",
          "L-020",
          "L-018"
        ],
        "timeMs": 2,
        "tokenEstimate": 7400
      },
      {
        "timestamp": "2026-04-25T15:59:53.860Z",
        "projectType": "service-desk",
        "customer": "strategix",
        "projectName": "Test Service Desk",
        "decisionsApplied": [
          "purpose-resolved",
          "project-section-cached",
          "scope-cached",
          "conventions-cached",
          "rbac-cached",
          "steps-6-10-cached"
        ],
        "contradictionsResolved": [],
        "lessonsUsed": [
          "L-018",
          "L-021",
          "L-020",
          "L-018"
        ],
        "timeMs": 2,
        "tokenEstimate": 7400
      },
      {
        "timestamp": "2026-04-25T20:43:34.454Z",
        "projectType": "service-desk",
        "customer": "strategix",
        "projectName": "Test Service Desk",
        "decisionsApplied": [
          "purpose-resolved",
          "project-section-cached",
          "scope-cached",
          "conventions-cached",
          "rbac-cached",
          "steps-6-10-cached"
        ],
        "contradictionsResolved": [],
        "lessonsUsed": [
          "L-018",
          "L-021",
          "L-020",
          "L-018"
        ],
        "timeMs": 3,
        "tokenEstimate": 7400
      },
      {
        "timestamp": "2026-04-25T20:43:41.181Z",
        "projectType": "service-desk",
        "customer": "strategix",
        "projectName": "Test Service Desk",
        "decisionsApplied": [
          "purpose-resolved",
          "project-section-cached",
          "scope-cached",
          "conventions-cached",
          "rbac-cached",
          "steps-6-10-cached"
        ],
        "contradictionsResolved": [],
        "lessonsUsed": [
          "L-018",
          "L-021",
          "L-020",
          "L-018"
        ],
        "timeMs": 1,
        "tokenEstimate": 7400
      }
    ]
  },
  {
    "pattern": "Lesson Effectiveness: L-021 (100% effective)",
    "occurrences": 4,
    "affectedRepos": [
      "strategix"
    ],
    "averageTimeMs": 0,
    "averageTokens": 0,
    "examples": [
      {
        "timestamp": "2026-04-25T15:59:09.836Z",
        "projectType": "service-desk",
        "customer": "strategix",
        "projectName": "Test Service Desk",
        "decisionsApplied": [
          "purpose-resolved",
          "project-section-cached",
          "scope-cached",
          "conventions-cached",
          "rbac-cached",
          "steps-6-10-cached"
        ],
        "contradictionsResolved": [],
        "lessonsUsed": [
          "L-018",
          "L-021",
          "L-020",
          "L-018"
        ],
        "timeMs": 2,
        "tokenEstimate": 7400
      },
      {
        "timestamp": "2026-04-25T15:59:53.860Z",
        "projectType": "service-desk",
        "customer": "strategix",
        "projectName": "Test Service Desk",
        "decisionsApplied": [
          "purpose-resolved",
          "project-section-cached",
          "scope-cached",
          "conventions-cached",
          "rbac-cached",
          "steps-6-10-cached"
        ],
        "contradictionsResolved": [],
        "lessonsUsed": [
          "L-018",
          "L-021",
          "L-020",
          "L-018"
        ],
        "timeMs": 2,
        "tokenEstimate": 7400
      },
      {
        "timestamp": "2026-04-25T20:43:34.454Z",
        "projectType": "service-desk",
        "customer": "strategix",
        "projectName": "Test Service Desk",
        "decisionsApplied": [
          "purpose-resolved",
          "project-section-cached",
          "scope-cached",
          "conventions-cached",
          "rbac-cached",
          "steps-6-10-cached"
        ],
        "contradictionsResolved": [],
        "lessonsUsed": [
          "L-018",
          "L-021",
          "L-020",
          "L-018"
        ],
        "timeMs": 3,
        "tokenEstimate": 7400
      },
      {
        "timestamp": "2026-04-25T20:43:41.181Z",
        "projectType": "service-desk",
        "customer": "strategix",
        "projectName": "Test Service Desk",
        "decisionsApplied": [
          "purpose-resolved",
          "project-section-cached",
          "scope-cached",
          "conventions-cached",
          "rbac-cached",
          "steps-6-10-cached"
        ],
        "contradictionsResolved": [],
        "lessonsUsed": [
          "L-018",
          "L-021",
          "L-020",
          "L-018"
        ],
        "timeMs": 1,
        "tokenEstimate": 7400
      }
    ]
  },
  {
    "pattern": "Lesson Effectiveness: L-020 (100% effective)",
    "occurrences": 4,
    "affectedRepos": [
      "strategix"
    ],
    "averageTimeMs": 0,
    "averageTokens": 0,
    "examples": [
      {
        "timestamp": "2026-04-25T15:59:09.836Z",
        "projectType": "service-desk",
        "customer": "strategix",
        "projectName": "Test Service Desk",
        "decisionsApplied": [
          "purpose-resolved",
          "project-section-cached",
          "scope-cached",
          "conventions-cached",
          "rbac-cached",
          "steps-6-10-cached"
        ],
        "contradictionsResolved": [],
        "lessonsUsed": [
          "L-018",
          "L-021",
          "L-020",
          "L-018"
        ],
        "timeMs": 2,
        "tokenEstimate": 7400
      },
      {
        "timestamp": "2026-04-25T15:59:53.860Z",
        "projectType": "service-desk",
        "customer": "strategix",
        "projectName": "Test Service Desk",
        "decisionsApplied": [
          "purpose-resolved",
          "project-section-cached",
          "scope-cached",
          "conventions-cached",
          "rbac-cached",
          "steps-6-10-cached"
        ],
        "contradictionsResolved": [],
        "lessonsUsed": [
          "L-018",
          "L-021",
          "L-020",
          "L-018"
        ],
        "timeMs": 2,
        "tokenEstimate": 7400
      },
      {
        "timestamp": "2026-04-25T20:43:34.454Z",
        "projectType": "service-desk",
        "customer": "strategix",
        "projectName": "Test Service Desk",
        "decisionsApplied": [
          "purpose-resolved",
          "project-section-cached",
          "scope-cached",
          "conventions-cached",
          "rbac-cached",
          "steps-6-10-cached"
        ],
        "contradictionsResolved": [],
        "lessonsUsed": [
          "L-018",
          "L-021",
          "L-020",
          "L-018"
        ],
        "timeMs": 3,
        "tokenEstimate": 7400
      },
      {
        "timestamp": "2026-04-25T20:43:41.181Z",
        "projectType": "service-desk",
        "customer": "strategix",
        "projectName": "Test Service Desk",
        "decisionsApplied": [
          "purpose-resolved",
          "project-section-cached",
          "scope-cached",
          "conventions-cached",
          "rbac-cached",
          "steps-6-10-cached"
        ],
        "contradictionsResolved": [],
        "lessonsUsed": [
          "L-018",
          "L-021",
          "L-020",
          "L-018"
        ],
        "timeMs": 1,
        "tokenEstimate": 7400
      }
    ]
  },
  {
    "pattern": "Token Efficiency: service-desk projects avg 9000 tokens",
    "occurrences": 5,
    "affectedRepos": [
      "strategix"
    ],
    "averageTimeMs": 0,
    "averageTokens": 9000,
    "examples": [
      {
        "timestamp": "2026-04-25T15:59:09.836Z",
        "projectType": "service-desk",
        "customer": "strategix",
        "projectName": "Test Service Desk",
        "decisionsApplied": [
          "purpose-resolved",
          "project-section-cached",
          "scope-cached",
          "conventions-cached",
          "rbac-cached",
          "steps-6-10-cached"
        ],
        "contradictionsResolved": [],
        "lessonsUsed": [
          "L-018",
          "L-021",
          "L-020",
          "L-018"
        ],
        "timeMs": 2,
        "tokenEstimate": 7400
      },
      {
        "timestamp": "2026-04-25T15:59:53.860Z",
        "projectType": "service-desk",
        "customer": "strategix",
        "projectName": "Test Service Desk",
        "decisionsApplied": [
          "purpose-resolved",
          "project-section-cached",
          "scope-cached",
          "conventions-cached",
          "rbac-cached",
          "steps-6-10-cached"
        ],
        "contradictionsResolved": [],
        "lessonsUsed": [
          "L-018",
          "L-021",
          "L-020",
          "L-018"
        ],
        "timeMs": 2,
        "tokenEstimate": 7400
      },
      {
        "timestamp": "2026-04-25T20:42:24.469Z",
        "projectType": "service-desk",
        "customer": "strategix",
        "projectName": "Test Service Desk",
        "decisionsApplied": [
          "purpose-resolved",
          "project-section-sonnet",
          "scope-sonnet",
          "conventions-sonnet",
          "rbac-fresh",
          "steps-6-10-cached"
        ],
        "contradictionsResolved": [],
        "lessonsUsed": [],
        "timeMs": 1,
        "tokenEstimate": 15400
      },
      {
        "timestamp": "2026-04-25T20:43:34.454Z",
        "projectType": "service-desk",
        "customer": "strategix",
        "projectName": "Test Service Desk",
        "decisionsApplied": [
          "purpose-resolved",
          "project-section-cached",
          "scope-cached",
          "conventions-cached",
          "rbac-cached",
          "steps-6-10-cached"
        ],
        "contradictionsResolved": [],
        "lessonsUsed": [
          "L-018",
          "L-021",
          "L-020",
          "L-018"
        ],
        "timeMs": 3,
        "tokenEstimate": 7400
      },
      {
        "timestamp": "2026-04-25T20:43:41.181Z",
        "projectType": "service-desk",
        "customer": "strategix",
        "projectName": "Test Service Desk",
        "decisionsApplied": [
          "purpose-resolved",
          "project-section-cached",
          "scope-cached",
          "conventions-cached",
          "rbac-cached",
          "steps-6-10-cached"
        ],
        "contradictionsResolved": [],
        "lessonsUsed": [
          "L-018",
          "L-021",
          "L-020",
          "L-018"
        ],
        "timeMs": 1,
        "tokenEstimate": 7400
      }
    ]
  }
]
```
