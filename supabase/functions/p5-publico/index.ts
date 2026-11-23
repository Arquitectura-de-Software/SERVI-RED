import { serve } from 'https://deno.land/std@0.224.0/http/server.ts';
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';
serve(async (req) => {
  const origin = Deno.env.get('P5_ALLOWED_ORIGIN') || '';
  const headers = { 'Content-Type': 'application/json', 'Access-Control-Allow-Origin': origin || 'null', 'Vary': 'Origin' };
  if (req.method !== 'GET') return new Response(JSON.stringify({error:'Method not allowed'}),{status:405,headers});
  if (origin && req.headers.get('origin') && req.headers.get('origin') !== origin) return new Response(JSON.stringify({error:'Origin denied'}),{status:403,headers});
  const url=Deno.env.get('SUPABASE_URL'); const key=Deno.env.get('SUPABASE_ANON_KEY');
  if(!url||!key) return new Response(JSON.stringify({error:'Missing configuration'}),{status:500,headers});
  const client=createClient(url,key);
  const {data,error}=await client.rpc('p5_indicadores_publicos');
  if(error) return new Response(JSON.stringify({error:error.message}),{status:500,headers});
  return new Response(JSON.stringify({data:data||[]}),{headers});
});
