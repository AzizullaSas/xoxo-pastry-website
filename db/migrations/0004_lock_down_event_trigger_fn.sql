-- Security hygiene: rls_auto_enable is an event-trigger helper, never a public
-- RPC. A function's default EXECUTE grant goes to PUBLIC, which anon/authenticated
-- inherit; the earlier hardening revoked only anon/authenticated and missed PUBLIC,
-- so the grant still resolved true. Revoke from PUBLIC explicitly.
revoke execute on function public.rls_auto_enable() from public, anon, authenticated;
