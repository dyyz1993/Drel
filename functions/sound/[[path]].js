// Restrict the microphone exception to the sound demos.
export async function onRequest(context) {
  const upstream = await context.env.ASSETS.fetch(context.request);
  const response = new Response(upstream.body, upstream);
  response.headers.set('Permissions-Policy', 'camera=(), microphone=(self), geolocation=(), payment=()');
  return response;
}
