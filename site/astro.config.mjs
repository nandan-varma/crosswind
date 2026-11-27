import { defineConfig } from 'astro/config';

export default defineConfig({
  site: 'https://crosswind.nandan.fyi',
  markdown: { shikiConfig: { themes: { light: 'github-light', dark: 'github-dark' } } },
});
