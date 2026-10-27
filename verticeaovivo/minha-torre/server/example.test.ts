import { Plugin, type PluginManifest, toPlugin } from '@databricks/appkit';
import { createTestApp, createTestPluginContext } from '@databricks/appkit/testing';
import { describe, expect, test } from 'vitest';

class GreeterPlugin extends Plugin {
  static manifest = {
    name: 'greeter',
    displayName: 'Greeter',
    description: 'Example plugin for the testing-kit demo',
    resources: { required: [], optional: [] },
  } as PluginManifest<'greeter'>;

  setup() {
    this.context?.addRoute('get', '/hello', (_req, res) => {
      res.end();
    });
    return Promise.resolve();
  }

  injectRoutes(router: Parameters<Plugin['injectRoutes']>[0]) {
    this.route(router, {
      name: 'greet',
      method: 'post',
      path: '/greet',
      handler: (req, res) => {
        const { name } = req.body as { name: string };
        res.json({ message: `Hello, ${name}!` });
        return Promise.resolve();
      },
    });
  }
}

const greeter = toPlugin(GreeterPlugin);

describe('testing kit example', () => {
  test('attaches a real PluginContext and records registered routes', async () => {
    const mock = createTestPluginContext();
    const plugin = new GreeterPlugin({});

    await mock.attach(plugin);
    await plugin.setup();

    expect(mock.routes).toContainEqual(
      expect.objectContaining({ method: 'get', path: '/hello' }),
    );
  });

  test('boots a real app and calls the plugin over HTTP', async () => {
    const app = await createTestApp({ plugins: [greeter()] });

    try {
      const res = await app.post('/api/greeter/greet', { body: { name: 'world' } });

      expect(res.status).toBe(200);
      expect(await res.json()).toEqual({ message: 'Hello, world!' });
    } finally {
      await app.close();
    }
  });
});
