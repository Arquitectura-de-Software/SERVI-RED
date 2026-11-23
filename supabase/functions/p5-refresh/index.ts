// Invocación programada con Authorization: Bearer <P5_CRON_SECRET>.
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';
Deno.serve(async (req) => {
 if (req.method !== 'POST') return new Response('Method not allowed',{status:405});
 const secret=Deno.env.get('P5_CRON_SECRET');
 if (!secret || req.headers.get('Authorization') !== `Bearer ${secret}`) return new Response('Unauthorized',{status:401});
 const url=Deno.env.get('SUPABASE_URL'),key=Deno.env.get('SUPABASE_SERVICE_ROLE_KEY');
 if (!url || !key) return new Response('Missing server configuration',{status:500});
 // RPC requiere que la función esté expuesta; se recomienda pg_cron para refresco directo.
 const db=createClient(url,key,{auth:{persistSession:false}});
 const {error}=await db.rpc('p5_refrescar_indicadores');
 if(error) return Response.json({ok:false,error:error.message},{status:500});
 return Response.json({ok:true});
});
