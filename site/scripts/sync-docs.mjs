// Copies the repository's own docs into the site, so each is written once. Generated files are gitignored.
import { cpSync, mkdirSync, readFileSync, rmSync, writeFileSync, existsSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const here = dirname(fileURLToPath(import.meta.url));
const repoDocs = join(here, '..', '..', 'docs');
const out = join(here, '..', 'src', 'content', 'docs', 'generated');
rmSync(out, { recursive: true, force: true });
mkdirSync(out, { recursive: true });

const pages = [
  { file: 'DEVELOPMENT.md', slug: 'development', title: 'Development guide', description: 'Build Crosswind, run it against a live guest, and debug it.', group: 'Develop', order: 10 },
  { file: 'security.md', slug: 'security', title: 'Security model', description: 'What the guest can and cannot do, and the trust boundaries.', group: 'Reference', order: 20 },
  { file: 'ROADMAP.md', slug: 'roadmap', title: 'Roadmap', description: 'What is built, what is next, and what is not planned.', group: 'Reference', order: 30 },
  { file: 'compat/matrix.md', slug: 'compatibility', title: 'App compatibility', description: 'Which Flathub apps were tested and how they behave.', group: 'Reference', order: 10 },
];

for (const page of pages) {
  const source = join(repoDocs, page.file);
  if (!existsSync(source)) continue;
  let body = readFileSync(source, 'utf8').replace(/^# .*\n+/, '');
  // The compatibility matrix links to screenshots next to it; they are served from /compat/.
  body = body.replaceAll('](screenshots/', '](/compat/screenshots/');
  const front = `---\ntitle: ${JSON.stringify(page.title)}\ndescription: ${JSON.stringify(page.description)}\ngroup: ${page.group}\norder: ${page.order}\n---\n\n`;
  writeFileSync(join(out, `${page.slug}.md`), front + body);
}

const shots = join(repoDocs, 'compat', 'screenshots');
if (existsSync(shots)) {
  const target = join(here, '..', 'public', 'compat', 'screenshots');
  mkdirSync(target, { recursive: true });
  cpSync(shots, target, { recursive: true });
}
