export default {
  async fetch(request: Request, env: any): Promise<Response> {
    const url = new URL(request.url);

    if (url.pathname === "/health") {
      return new Response(
        JSON.stringify({ ok: true, service: "ugswms-payments-worker" }),
        { headers: { "Content-Type": "application/json" } }
      );
    }

    if (url.pathname === "/flutterwave/paylink" && request.method === "POST") {
      return new Response(
        JSON.stringify({ message: "Flutterwave paylink endpoint ready" }),
        { headers: { "Content-Type": "application/json" } }
      );
    }

    if (url.pathname === "/flutterwave/webhook" && request.method === "POST") {
      return new Response(
        JSON.stringify({ received: true }),
        { headers: { "Content-Type": "application/json" } }
      );
    }

    return new Response("Not Found", { status: 404 });
  },
};
