import { analytics, createApp, genie, server } from '@databricks/appkit';

createApp({
  plugins: [analytics(), server(), genie()],
  cache: { enabled: false },
  onPluginsReady(appkit) {
    appkit.server.extend((app) => {
      app.get('/api/score-estouro', async (_req, res) => {
        try {
          const rows: unknown = await appkit.analytics.query(
            'SELECT * FROM lakehouse_vertice.gold.score_estouro_30d',
          );
          const linhas: unknown[] = Array.isArray(rows) ? rows : [];
          res.json({ disponivel: true, linhas });
        } catch {
          res.json({ disponivel: false, linhas: [] });
        }
      });
    });
  },
}).catch(console.error);
