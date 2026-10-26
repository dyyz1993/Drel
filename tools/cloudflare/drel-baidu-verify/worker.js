export default {
  async fetch() {
    return new Response('37a386d7b220c5fc81c033fbd27c2098', {
      status: 200,
      headers: { 'content-type': 'text/html; charset=utf-8' },
    });
  },
};
