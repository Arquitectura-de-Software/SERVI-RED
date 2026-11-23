"""Prueba ligera de latencia HTTP, sin atacar la infraestructura. Uso: python3 scripts/p5_prueba_carga.py URL"""
import sys,time,urllib.request,statistics
if len(sys.argv)!=2: sys.exit('Uso: python3 scripts/p5_prueba_carga.py URL')
lat=[]
for i in range(10):
 t=time.perf_counter()
 try:
  with urllib.request.urlopen(sys.argv[1],timeout=8) as r: print(i+1,r.status)
 except Exception as e: print(i+1,type(e).__name__)
 lat.append(round((time.perf_counter()-t)*1000,2));time.sleep(.5)
print('ms promedio:',round(statistics.mean(lat),2),'máximo:',max(lat))
