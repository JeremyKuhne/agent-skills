import fs from 'node:fs';
import process from 'node:process';
import { parseDocument } from 'yaml';

if (process.argv.length !== 3) {
  console.error('Usage: node read-workflow-runs.mjs <workflow-path>');
  process.exit(2);
}

const workflowPath = process.argv[2];
let source = fs.readFileSync(workflowPath, 'utf8');
source = source.replace(/^[ \t]*\{\{PLUGIN_SMOKE_STEPS\}\}[ \t]*$/m, '');
if (/(?<!\$)\{\{[A-Z][A-Z0-9_]*\}\}/.test(source)) {
  console.error('Workflow template contains an unsupported placeholder.');
  process.exit(1);
}
const document = parseDocument(source, {
  prettyErrors: false,
  strict: true,
  uniqueKeys: true,
});

if (document.errors.length > 0) {
  for (const error of document.errors) {
    console.error(error.message);
  }
  process.exit(1);
}

const workflow = document.toJS({ maxAliasCount: 100 });
if (workflow === null || typeof workflow !== 'object' || Array.isArray(workflow)) {
  console.error('Workflow root must be a mapping.');
  process.exit(1);
}

function getDefaultShell(container, label) {
  const defaults = container.defaults;
  if (defaults === undefined) {
    return null;
  }
  if (defaults === null || typeof defaults !== 'object' || Array.isArray(defaults)) {
    console.error(`${label} defaults must be a mapping.`);
    process.exit(1);
  }
  const run = defaults.run;
  if (run === undefined) {
    return null;
  }
  if (run === null || typeof run !== 'object' || Array.isArray(run)) {
    console.error(`${label} defaults.run must be a mapping.`);
    process.exit(1);
  }
  if (run.shell !== undefined && typeof run.shell !== 'string') {
    console.error(`${label} defaults.run.shell must be a scalar.`);
    process.exit(1);
  }
  return run.shell ?? null;
}

const records = [];
const workflowDefaultShell = getDefaultShell(workflow, 'Workflow');
const jobs = workflow.jobs;
if (jobs !== undefined) {
  if (jobs === null || typeof jobs !== 'object' || Array.isArray(jobs)) {
    console.error("Workflow 'jobs' must be a mapping.");
    process.exit(1);
  }

  for (const [jobName, job] of Object.entries(jobs)) {
    if (job === null || typeof job !== 'object' || Array.isArray(job)) {
      continue;
    }
    const jobDefaultShell = getDefaultShell(job, `Workflow job '${jobName}'`) ?? workflowDefaultShell;

    const steps = job.steps;
    if (steps === undefined) {
      continue;
    }
    if (!Array.isArray(steps)) {
      console.error(`Workflow job '${jobName}' steps must be a sequence.`);
      process.exit(1);
    }

    for (let index = 0; index < steps.length; index += 1) {
      const step = steps[index];
      if (step === null || typeof step !== 'object' || Array.isArray(step)) {
        continue;
      }
      if (step.run === undefined) {
        continue;
      }
      if (typeof step.run !== 'string') {
        console.error(`Workflow job '${jobName}' step ${index} run must be a scalar.`);
        process.exit(1);
      }
      if (step.shell !== undefined && typeof step.shell !== 'string') {
        console.error(`Workflow job '${jobName}' step ${index} shell must be a scalar.`);
        process.exit(1);
      }

      records.push({
        job: jobName,
        step: index,
        shell: step.shell ?? jobDefaultShell,
        run: step.run,
      });
    }
  }
}

process.stdout.write(JSON.stringify(records));
